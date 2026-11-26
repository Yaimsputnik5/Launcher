import Foundation

final class HTTPClient {
    static let shared = HTTPClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let userAgent: String

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.httpMaximumConnectionsPerHost = max(2, ProcessInfo.processInfo.activeProcessorCount)
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)

        decoder = JSONDecoder()
        encoder = JSONEncoder()
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "OSFR Launcher"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        userAgent = "\(appName)/\(version) (iOS)"
    }

    func serverManifest(from url: URL) async throws -> ServerManifest {
        let data = try await fetchXML(url)
        return try ServerManifestParser().parse(data)
    }

    func clientManifest(from url: URL) async throws -> ClientManifest {
        let data = try await fetchXML(url)
        return try ClientManifestParser().parse(data)
    }

    func login(webAPI: URL, username: String, password: String) async throws -> LoginResponse {
        let endpoint = URLHelper.joining(webAPI, "login")
        let request = try jsonRequest(endpoint, body: LoginRequest(username: username, password: password))
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        if let status = (response as? HTTPURLResponse)?.statusCode {
            if status == 401 { throw LauncherError.unauthorized }
            guard (200..<300).contains(status) else { throw LauncherError.httpStatus(status) }
        }
        do {
            return try decoder.decode(LoginResponse.self, from: data)
        } catch {
            throw LauncherError.malformedLoginResponse(Self.loginResponseDetail(error))
        }
    }

    private static func loginResponseDetail(_ error: Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let key, _):
            return "missing \(key.stringValue)"
        case DecodingError.typeMismatch(let type, _):
            return "invalid \(type)"
        case DecodingError.dataCorrupted(let context):
            return context.debugDescription
        default:
            return "unexpected format"
        }
    }

    func register(webAPI: URL, username: String, password: String) async throws {
        let endpoint = URLHelper.joining(webAPI, "register")
        let request = try jsonRequest(endpoint, body: RegisterRequest(username: username, password: password))
        let (_, response) = try await session.data(for: request)
        try validate(response: response)
        if let status = (response as? HTTPURLResponse)?.statusCode {
            if status == 409 { throw LauncherError.conflict }
            guard (200..<300).contains(status) else { throw LauncherError.httpStatus(status) }
        }
    }

    func downloadFile(from url: URL,
                      to destination: URL,
                      expectedSize: UInt64?,
                      expectedHash: UInt64?,
                      progress: @escaping (Double) -> Void) async throws {
        let fm = FileManager.default
        let directory = destination.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let temp = directory.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).part")
        var succeeded = false
        defer {
            if !succeeded { try? fm.removeItem(at: temp) }
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LauncherError.httpStatus(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LauncherError.httpStatus(http.statusCode)
        }

        let expectedBytes = http.expectedContentLength >= 0 ? UInt64(http.expectedContentLength) : nil

        // FileHandle(forWritingTo:) requires the file to exist.
        fm.createFile(atPath: temp.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temp)
        try await write(
            bytes,
            using: handle,
            expectedBytes: expectedBytes ?? expectedSize,
            progress: progress
        )

        try verify(temp, size: expectedSize, hash: expectedHash)
        if fm.fileExists(atPath: destination.path) {
            let replacement = try fm.replaceItemAt(
                destination,
                withItemAt: temp,
                backupItemName: nil,
                options: .usingNewMetadataOnly
            )
            guard replacement != nil else {
                throw LauncherError.fileSystem("Could not replace \(destination.lastPathComponent)")
            }
        } else {
            try fm.moveItem(at: temp, to: destination)
        }
        succeeded = true
    }

    private func write(_ bytes: URLSession.AsyncBytes,
                       using handle: FileHandle,
                       expectedBytes: UInt64?,
                       progress: @escaping (Double) -> Void) async throws {
        defer { try? handle.close() }
        var received: UInt64 = 0
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)

        // URLSession.AsyncBytes yields individual UInt8 values, not Data chunks.
        for try await byte in bytes {
            buffer.append(byte)
            received += 1
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
            if let expectedBytes, expectedBytes > 0 {
                progress(min(1, max(0, Double(received) / Double(expectedBytes))))
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }
        try handle.synchronize()
    }

    private func verify(_ file: URL, size: UInt64?, hash: UInt64?) throws {
        let fm = FileManager.default
        let attributes = try fm.attributesOfItem(atPath: file.path)
        let actualSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        if let size, actualSize != size {
            throw LauncherError.checksumMismatch(file.lastPathComponent + " (size)")
        }
        if let hash {
            let data = try Data(contentsOf: file, options: .mappedIfSafe)
            guard XXHash64.hash(data) == hash else {
                throw LauncherError.checksumMismatch(file.lastPathComponent)
            }
        }
    }

    private func fetchXML(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/xml, text/xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw LauncherError.httpStatus(-1)
        }
        guard (200..<300).contains(status) else { throw LauncherError.httpStatus(status) }

        let rawType = response.mimeType?.lowercased() ?? ""
        let looksLikeXML = data.prefix(5) == Data("<?xml".utf8)
        guard rawType == "text/xml" || rawType == "application/xml" || (rawType.isEmpty && looksLikeXML) else {
            throw LauncherError.badContentType(rawType.isEmpty ? "unknown" : rawType)
        }
        return data
    }

    private func jsonRequest<T: Encodable>(_ url: URL, body: T) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try encoder.encode(body)
        return request
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LauncherError.httpStatus(-1)
        }
        guard let scheme = http.url?.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw LauncherError.unsupportedScheme(http.url?.scheme ?? "unknown")
        }
    }
}
