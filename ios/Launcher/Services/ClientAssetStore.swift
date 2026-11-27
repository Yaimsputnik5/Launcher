import Foundation

struct ClientAssetIndexEntry: Codable, Equatable, Sendable {
    let path: String
    let size: Int64
    let hash: UInt64
}

struct ClientAssetIndex: Codable, Equatable, Sendable {
    let manifestURL: String
    let baseURL: String
    let fileCount: Int
    let totalBytes: Int64
    let files: [ClientAssetIndexEntry]

    enum CodingKeys: String, CodingKey {
        case manifestURL = "manifestUrl"
        case baseURL = "baseUrl"
        case fileCount, totalBytes, files
    }
}

enum ClientAssetLocation: Equatable {
    case bundled(URL)
    case sandbox(URL)
    case server(URL)

    var url: URL {
        switch self {
        case .bundled(let url), .sandbox(let url), .server(let url): return url
        }
    }

    var label: String {
        switch self {
        case .bundled: return "Embedded"
        case .sandbox: return "Local copy"
        case .server: return "Server"
        }
    }
}

/// Resolves and verifies original client files from the app bundle or sandbox.
///
/// The store never executes files it locates. It only hands verified byte URLs
/// to the native asset parser.
final class ClientAssetStore: @unchecked Sendable {
    static let shared = ClientAssetStore()

    private let decoder = JSONDecoder()
    private let fileManager = FileManager.default

    /// True when a build-time embedded entry describes the exact bytes named
    /// by a live client-manifest file. Used to avoid re-downloading the payload
    /// already inside the IPA.
    static func embeddedEntryMatches(_ entry: ClientAssetIndexEntry, file: ClientFile) -> Bool {
        guard entry.size >= 0 else { return false }
        return UInt64(entry.size) == file.size && entry.hash == file.hash
    }

    func index() -> ClientAssetIndex? {
        guard let root = AppPaths.bundledClientAssets else { return nil }
        return loadIndex(from: root)
    }

    func sandboxIndex() -> ClientAssetIndex? {
        loadIndex(from: AppPaths.sandboxClientAssets)
    }

    func availability(server: ServerInfo? = nil) -> AssetReadiness {
        let index = index() ?? sandboxIndex()
        var readiness = AssetReadiness()
        readiness.hasClientManifest = index != nil

        guard let index else { return readiness }
        readiness.bundledClientFileCount = index.fileCount
        readiness.bundledClientTotalBytes = index.totalBytes

        let roots = candidateRoots(server: server)
        for entry in index.files {
            if roots.contains(where: { exists(entry, in: $0) }) {
                // Counted in the index totals above.
            }
        }
        return readiness
    }

    /// Returns the first usable location for a manifest-relative path.
    func location(for relativePath: String, server: ServerInfo? = nil) -> ClientAssetLocation? {
        for root in candidateRoots(server: server) {
            guard let url = try? Self.containedURL(relativePath, in: root.url, resolveSymlinks: false),
                  fileManager.fileExists(atPath: url.path)
            else { continue }
            switch root {
            case .bundled: return .bundled(url)
            case .sandbox: return .sandbox(url)
            case .server: return .server(url)
            }
        }
        return nil
    }

    func data(for relativePath: String, server: ServerInfo? = nil) -> Data? {
        guard let url = location(for: relativePath, server: server)?.url else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    /// Full XXH64 verification. This reads every bundled file and should be run
    /// from a detached task, not on the main actor.
    func verify(server: ServerInfo? = nil) -> AssetVerificationReport {
        guard let index = index() ?? sandboxIndex() else {
            return AssetVerificationReport(missing: ["client-assets-index.json"])
        }

        var report = AssetVerificationReport(checked: index.files.count)
        for entry in index.files {
            guard let url = location(for: entry.path, server: server)?.url else {
                report.missing.append(entry.path)
                continue
            }
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let size = (attributes[.size] as? NSNumber)?.int64Value,
                  size == entry.size
            else {
                report.mismatched.append(entry.path)
                continue
            }
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  XXHash64.hash(data) == entry.hash
            else {
                report.mismatched.append(entry.path)
                continue
            }
            report.verified += 1
        }
        return report
    }

    private func loadIndex(from root: URL) -> ClientAssetIndex? {
        let url = root.appendingPathComponent("client-assets-index.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(ClientAssetIndex.self, from: data)
    }

    private func candidateRoots(server: ServerInfo?) -> [ClientAssetLocation] {
        var roots: [ClientAssetLocation] = []
        if let bundled = AppPaths.bundledClientAssets {
            roots.append(.bundled(bundled))
        }
        roots.append(.sandbox(AppPaths.sandboxClientAssets))
        if let server, let serverRoot = try? AppPaths.clientDirectory(server) {
            roots.append(.server(serverRoot))
        }
        return roots
    }

    private func exists(_ entry: ClientAssetIndexEntry, in root: ClientAssetLocation) -> Bool {
        guard let url = try? Self.containedURL(entry.path, in: root.url, resolveSymlinks: false)
        else { return false }
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value
        else { return false }
        return size == entry.size
    }

    private static func containedURL(
        _ relativePath: String,
        in base: URL,
        resolveSymlinks: Bool = true
    ) throws -> URL {
        let components = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty else { throw LauncherError.unsafePath(relativePath) }
        return try SafePath.contained(
            base: base,
            components: components,
            resolveSymlinks: resolveSymlinks
        )
    }
}
