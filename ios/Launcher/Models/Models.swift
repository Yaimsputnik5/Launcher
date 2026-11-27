import Foundation

// MARK: - Constants

enum AppConstants {
    static let defaultServerURLs = [DefaultServer.url]
    static let serverManifestFile = "servermanifest.xml"
    static let clientManifestFile = "clientmanifest.xml"
    static let clientRoot = "client"
    static let statusPort: UInt16 = 20042
    static let desktopExecutable = "FreeRealms.exe"
}

// MARK: - Persisted settings

struct AppSettings: Codable {
    var servers: [ServerInfo] = []
    var downloadThreads: Int = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
    var parallelDownloads: Bool = true
    var locale: GameLocale = .en_US
    /// Persisted offline host settings. Older settings files predate this field,
    /// so decoding below supplies the historical defaults explicitly.
    var hostConfiguration: LocalHostConfiguration = LocalHostConfiguration()
    var didSeedDefaultServers = false

    private enum CodingKeys: String, CodingKey {
        case servers
        case downloadThreads
        case parallelDownloads
        case locale
        case hostConfiguration
        case didSeedDefaultServers
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        servers = try container.decodeIfPresent([ServerInfo].self, forKey: .servers) ?? []
        downloadThreads = try container.decodeIfPresent(Int.self, forKey: .downloadThreads)
            ?? max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
        parallelDownloads = try container.decodeIfPresent(Bool.self, forKey: .parallelDownloads) ?? true
        locale = try container.decodeIfPresent(GameLocale.self, forKey: .locale) ?? .en_US
        hostConfiguration = try container.decodeIfPresent(
            LocalHostConfiguration.self,
            forKey: .hostConfiguration
        ) ?? LocalHostConfiguration()
        didSeedDefaultServers = try container.decodeIfPresent(Bool.self, forKey: .didSeedDefaultServers) ?? false
    }

    static func load() -> AppSettings {
        let url = AppPaths.settingsFile
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return decoded
    }

    func save() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: AppPaths.root, withIntermediateDirectories: true)
        var data = try JSONEncoder().encode(self)
        data.append(0x0A)
        try data.write(to: AppPaths.settingsFile, options: .atomic)
    }
}

struct ServerInfo: Codable, Identifiable, Equatable {
    let id: UUID
    var url: String
    var name: String
    var descriptionText: String
    var webAPIURL: String
    var loginServer: String
    var savePath: String
    var username: String
    var rememberUsername: Bool
    var rememberPassword: Bool
    var locale: GameLocale
    /// Optional per-server overrides. Sanctuary's bundled gateway publishes its
    /// required client version in gateway.json, not in servermanifest.xml, so a
    /// server with a different build must be configurable without a code change.
    var gatewayVersion: String?
    /// Sent in the login request. Sanctuary logs it but does not validate it.
    var loginFingerprint: String?
    /// True until a live servermanifest.xml has supplied real endpoints. The
    /// C# launcher never persists a bootstrap record; iOS keeps one so the
    /// public server is visible offline, but must not present it as live data.
    var isBootstrapOnly: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, url, name
        case descriptionText = "description"
        case webAPIURL = "webApiUrl"
        case loginServer, savePath, username, rememberUsername, rememberPassword, locale
        case gatewayVersion, loginFingerprint
        case isBootstrapOnly
    }

    static func make(
        url: String,
        name: String,
        description: String,
        webAPIURL: String,
        loginServer: String
    ) -> ServerInfo {
        ServerInfo(
            id: UUID(),
            url: url,
            name: name,
            descriptionText: description,
            webAPIURL: webAPIURL,
            loginServer: loginServer,
            savePath: SafePath.sanitizedLeaf(name),
            username: "",
            rememberUsername: false,
            rememberPassword: false,
            locale: .en_US,
            isBootstrapOnly: false
        )
    }
}

/// Mirrors the C# `ServerStatus` enum plus transient refresh/error states used
/// by native UI. The C# app initializes to Offline and uses red Locked when the
/// status reply reports a joining/locked server.
enum ServerPresentationState: String, Codable {
    case unknown
    case refreshing
    case online
    case locked
    case offline
    case unsupported
    case error
}

// MARK: - Game locales

enum GameLocale: String, Codable, CaseIterable, Identifiable {
    case none = "None"
    case zh_CN, de_DE, fr_FR, en_GB, ja_JP, ko_KR, zh_TW, en_US
    case es_ES, it_IT, pt_PT, ru_RU, sv_SE, pt_BR, es_MX
    case nl_NL, pl_PL, fi_FL, da_DK, nn_NO

    var id: String { rawValue }

    /// The C# settings UI omits `None`; keep the stored enum value for manifest
    /// compatibility but do not offer it to users.
    static let selectable: [GameLocale] = allCases.filter { $0 != .none }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .zh_CN: return "Chinese (Simplified, China)"
        case .de_DE: return "German (Germany)"
        case .fr_FR: return "French (France)"
        case .en_GB: return "English (United Kingdom)"
        case .ja_JP: return "Japanese (Japan)"
        case .ko_KR: return "Korean (South Korea)"
        case .zh_TW: return "Chinese (Traditional, Taiwan)"
        case .en_US: return "English (United States)"
        case .es_ES: return "Spanish (Spain)"
        case .it_IT: return "Italian (Italy)"
        case .pt_PT: return "Portuguese (Portugal)"
        case .ru_RU: return "Russian (Russia)"
        case .sv_SE: return "Swedish (Sweden)"
        case .pt_BR: return "Portuguese (Brazil)"
        case .es_MX: return "Spanish (Mexico)"
        case .nl_NL: return "Dutch (Netherlands)"
        case .pl_PL: return "Polish (Poland)"
        case .fi_FL: return "Finnish (Finland)"
        case .da_DK: return "Danish (Denmark)"
        case .nn_NO: return "Norwegian Nynorsk (Norway)"
        }
    }

    /// `ClientManifest.Languages` uses C#'s `Enum.TryParse(..., ignoreCase: true)`.
    /// The live OSFR manifest writes `en_us`, so matching must be
    /// case-insensitive. The original C# enum contains the historical typo
    /// `fi_FL`; accept the correct `fi_FI` from manifests and map it to that
    /// legacy value.
    static func fromManifest(_ rawValue: String) -> GameLocale? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("fi_FI") == .orderedSame { return .fi_FL }
        return allCases.first { $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame }
    }
}

// MARK: - Manifest models

struct ServerManifest {
    var version: Int
    var name: String
    var descriptionText: String
    var webAPIURL: String
    var loginServer: String
}

struct ClientManifest {
    var version: Int
    var languages: [GameLocale]
    var rootFolder: ClientFolder
}

struct ClientFolder {
    var name: String
    var files: [ClientFile]
    var folders: [ClientFolder]
}

struct ClientFile: Sendable {
    var name: String
    var size: UInt64
    var hash: UInt64
}

struct LoginRequest: Codable {
    let username: String
    let password: String
}

struct LoginResponse: Codable {
    let sessionId: String
    let launchArguments: String?

    private enum CodingKeys: String, CodingKey {
        case sessionId
        case launchArguments
    }

    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(sessionId: String, launchArguments: String?) {
        self.sessionId = sessionId
        self.launchArguments = launchArguments
    }

    /// Sanctuary's minimal WebAPI uses System.Text.Json's default camelCase,
    /// so the wire keys are `sessionId`/`launchArguments`. Older or customized
    /// APIs may use the C# model names (`SessionId`/`LaunchArguments`); accept
    /// both case-insensitively so credentials are never blamed for a JSON
    /// naming mismatch.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let keys = Dictionary(
            container.allKeys.map { ($0.stringValue.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        func decoded<T: Decodable>(_ type: T.Type, named names: [String]) throws -> T? {
            for name in names {
                if let key = keys[name.lowercased()] {
                    return try container.decodeIfPresent(T.self, forKey: key)
                }
            }
            return nil
        }

        guard let sessionId: String = try decoded(String.self, named: ["sessionId", "SessionId"]) else {
            throw DecodingError.keyNotFound(
                AnyCodingKey(stringValue: "sessionId"),
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "WebAPI login response is missing sessionId"
                )
            )
        }
        self.sessionId = sessionId
        launchArguments = try decoded(String.self, named: ["launchArguments", "LaunchArguments"])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encodeIfPresent(launchArguments, forKey: .launchArguments)
    }
}

struct RegisterRequest: Codable {
    let username: String
    let password: String
}

// MARK: - Errors

enum LauncherError: LocalizedError {
    case invalidURL(String)
    case unsupportedScheme(String)
    case insecureCredentials(String)
    case httpStatus(Int)
    case unauthorized
    case malformedLoginResponse(String)
    case loginRejected(Int32)
    case conflict
    case badContentType(String)
    case invalidManifestVersion(Int)
    case unsupportedManifestVersion(Int)
    case malformedManifest(String)
    case unsafePath(String)
    case checksumMismatch(String)
    case fileSystem(String)
    case keychain(Int)
    case canceled

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value): return "Invalid URL: \(value)"
        case .unsupportedScheme(let scheme): return "Unsupported URL scheme: \(scheme)"
        case .insecureCredentials(let host):
            return "Refusing to send credentials over plain HTTP to \(host). Use HTTPS or a localhost server."
        case .httpStatus(let code): return "Server returned HTTP \(code)."
        case .unauthorized: return "Incorrect username or password."
        case .malformedLoginResponse(let detail):
            return "The server returned an unreadable sign-in response (\(detail))."
        case .loginRejected(let status): return "The game login server rejected the session (status \(status))."
        case .conflict: return "That username is already registered."
        case .badContentType(let type): return "Expected XML but received \(type)."
        case .invalidManifestVersion(let version): return "Invalid manifest version: \(version)."
        case .unsupportedManifestVersion(let version): return "Manifest version \(version) is not supported."
        case .malformedManifest(let detail): return "Malformed manifest: \(detail)"
        case .unsafePath(let value): return "Unsafe path in manifest: \(value)"
        case .checksumMismatch(let name): return "Checksum mismatch for \(name)."
        case .fileSystem(let detail): return "File system error: \(detail)"
        case .keychain(let status): return "Keychain error (\(status))."
        case .canceled: return "Canceled."
        }
    }
}

struct AppNotice: Identifiable, Equatable {
    let id: UUID
    let message: String
    let isError: Bool
    /// A download-interruption notice stays visible until the download is
    /// retried; ordinary notices expire after three seconds.
    let persistent: Bool

    init(id: UUID = UUID(), message: String, isError: Bool = false, persistent: Bool = false) {
        self.id = id
        self.message = message
        self.isError = isError
        self.persistent = persistent
    }
}
