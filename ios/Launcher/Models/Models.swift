import Foundation

// MARK: - Constants

enum AppConstants {
    static let defaultServerURLs = ["https://opensourcefreerealms.com"]
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
    var locale: GameLocale = .en_US
    var didSeedDefaultServers = false

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

    enum CodingKeys: String, CodingKey {
        case id, url, name
        case descriptionText = "description"
        case webAPIURL = "webApiUrl"
        case loginServer, savePath, username, rememberUsername, rememberPassword, locale
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
            locale: .en_US
        )
    }
}

// MARK: - Game locales

enum GameLocale: String, Codable, CaseIterable, Identifiable {
    case none = "None"
    case zh_CN, de_DE, fr_FR, en_GB, ja_JP, ko_KR, zh_TW, en_US
    case es_ES, it_IT, pt_PT, ru_RU, sv_SE, pt_BR, es_MX
    case nl_NL, pl_PL, fi_FL, da_DK, nn_NO

    var id: String { rawValue }

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

    /// The original C# enum contains the historical typo `fi_FL`. Accept the
    /// correct `fi_FI` from manifests and map it to that legacy value.
    static func fromManifest(_ rawValue: String) -> GameLocale? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "fi_FI" { return .fi_FL }
        return GameLocale(rawValue: trimmed)
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

struct ClientFile {
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

    enum CodingKeys: String, CodingKey {
        case sessionId = "SessionId"
        case launchArguments = "LaunchArguments"
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
    case httpStatus(Int)
    case unauthorized
    case conflict
    case badContentType(String)
    case invalidManifestVersion(Int)
    case unsupportedManifestVersion(Int)
    case malformedManifest(String)
    case unsafePath(String)
    case checksumMismatch(String)
    case keychain(Int)
    case canceled

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value): return "Invalid URL: \(value)"
        case .unsupportedScheme(let scheme): return "Unsupported URL scheme: \(scheme)"
        case .httpStatus(let code): return "Server returned HTTP \(code)."
        case .unauthorized: return "Incorrect username or password."
        case .conflict: return "That username is already registered."
        case .badContentType(let type): return "Expected XML but received \(type)."
        case .invalidManifestVersion(let version): return "Invalid manifest version: \(version)."
        case .unsupportedManifestVersion(let version): return "Manifest version \(version) is not supported."
        case .malformedManifest(let detail): return "Malformed manifest: \(detail)"
        case .unsafePath(let value): return "Unsafe path in manifest: \(value)"
        case .checksumMismatch(let name): return "Checksum mismatch for \(name)."
        case .keychain(let status): return "Keychain error (\(status))."
        case .canceled: return "Canceled."
        }
    }
}

struct AppNotice: Identifiable, Equatable {
    let id: UUID
    let message: String
    let isError: Bool

    init(id: UUID = UUID(), message: String, isError: Bool = false) {
        self.id = id
        self.message = message
        self.isError = isError
    }
}
