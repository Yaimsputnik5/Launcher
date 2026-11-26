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
///
/// Every field is consumed by `PlayOfflineView`/`SettingsView` and applied by
/// `LocalSession.bootstrapOffline` plus `WorldSimulation`: the profile name is
/// the offline account, the player name is the character, the zone is resolved
/// through `ResourceCatalog.zone(id:)`, and the unlock/currency values seed the
/// persisted character and HUD.
struct LocalHostConfiguration: Codable, Equatable {
    var accountName: String = "local"
    var characterName: String = "Player"
    var locale: GameLocale = .en_US
    var startingZoneID: Int = 1
    var unlockAllProfiles: Bool = true
    var unlockAllTitles: Bool = true
    var unlockAllTiles: Bool = false
    var startingCoins: Int64 = 999_999_999
    var startingStationCash: Int64 = 999_999_999

    /// UI-facing aliases matching the terminology used by the launcher fields.
    var profileName: String {
        get { accountName }
        set { accountName = newValue }
    }

    var playerName: String {
        get { characterName }
        set { characterName = newValue }
    }
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

    /// Values from Sanctuary's `ClientCharacterData`. They are optional because
    /// a WebAPI-only session predates character login and has no gateway ticket.
    var characterName: String? = nil
    var gatewayAddress: String? = nil
    var gatewayGUID: UInt64? = nil
    /// Sanctuary's gateway.json default; a server may require a different value.
    var gatewayVersion: String? = nil
    var serverID: Int32? = nil

    /// Offline profile name (the local account) and the exact host settings used
    /// to enter this world. Remote sessions leave both nil.
    var profileName: String? = nil
    var localConfiguration: LocalHostConfiguration? = nil

    var isOffline: Bool { mode == .offline }

    /// True only after the full Login UDP character/gateway exchange completed.
    var canJoinGateway: Bool {
        mode == .remote && ticket != nil && gatewayAddress != nil && gatewayGUID != nil
    }
}

/// A world session that has actually been entered. It is deliberately separate
/// from `remoteSession`: signing in to a WebAPI session is not the same as being
/// in a server, and never by itself unlocks the World tab.
struct ActiveWorldSession: Equatable {
    let id: UUID
    let configuration: WorldSessionConfiguration
    let hostConfiguration: LocalHostConfiguration?
    let startedAt: Date

    var mode: PlayMode { configuration.mode }
    var displayName: String {
        configuration.characterName ?? configuration.username
    }
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
