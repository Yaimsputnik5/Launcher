import Foundation

/// How the app obtains a world session.
enum PlayMode: String, Codable, CaseIterable, Identifiable {
    case offline
    case remote

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .offline: return "Play Offline"
        case .remote: return "Join Server"
        }
    }

    var systemImage: String {
        switch self {
        case .offline: return "wifi.slash"
        case .remote: return "network"
        }
    }
}

/// Configuration for the in-process server used by offline play.
struct LocalHostConfiguration: Codable, Equatable {
    var accountName: String = "local"
    var characterName: String = "Player"
    var locale: GameLocale = .en_US
    var startingZoneID: Int = 1
    var unlockAllProfiles: Bool = true
    var unlockAllTitles: Bool = true
    var startingCoins: Int64 = 999_999_999
    var startingStationCash: Int64 = 999_999_999
}

/// Everything needed to enter a world after login/character select.
struct WorldSessionConfiguration: Codable, Equatable {
    var mode: PlayMode
    var host: String?
    var username: String
    var sessionID: String?
    var characterID: UInt64?
    var ticket: String?
    var cryptoKey: String?
    var loginArguments: [String]
    var locale: GameLocale

    var isOffline: Bool { mode == .offline }
}

/// Compact state used by the UI before the engine is fully initialized.
struct AssetReadiness: Codable, Equatable {
    var bundledClientFileCount: Int = 0
    var bundledClientTotalBytes: Int64 = 0
    var sanctuaryFileCount: Int = 0
    var sanctuaryTotalBytes: Int64 = 0
    var hasClientManifest: Bool = false
    var hasSanctuaryManifest: Bool = false

    var clientBytesDescription: String {
        Self.byteCountFormatter.string(fromByteCount: bundledClientTotalBytes)
    }

    var sanctuaryBytesDescription: String {
        Self.byteCountFormatter.string(fromByteCount: sanctuaryTotalBytes)
    }

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter
    }()
}

struct AssetVerificationReport: Equatable {
    var checked: Int = 0
    var verified: Int = 0
    var missing: [String] = []
    var mismatched: [String] = []

    var isFullyVerified: Bool { missing.isEmpty && mismatched.isEmpty }
}
