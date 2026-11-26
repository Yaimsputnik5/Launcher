import Foundation

// MARK: - Schema and state models

/// A native, offline-only account/character store. This is deliberately not a
/// Sanctuary database replacement: it is a small JSON store for in-process play.
/// See `LocalSession` for the command surface and persistence rules.
enum LocalSessionSchema {
    /// Bump only with an explicit migration. Older versions are rejected.
    static let version = 1
    static let fileName = "local-session.json"
}

/// Position and rotation in world-space units, matching the fields persisted by
/// Sanctuary's `DbCharacter` (`PositionX/Y/Z`, `RotationX/Z`).
struct LocalWorldPosition: Codable, Equatable {
    var x: Float
    var y: Float
    var z: Float
    var rotationX: Float
    var rotationZ: Float

    /// Spawn point from `Resources/Zones/FabledRealms.json` (zone 1).
    static let fabledRealmsSpawn = LocalWorldPosition(
        x: -1904.883,
        y: -39.7098,
        z: 412.6024,
        rotationX: 0.5531712,
        rotationZ: 0.8330676
    )

    var isValid: Bool {
        [x, y, z, rotationX, rotationZ].allSatisfy(\.isFinite)
    }
}

/// One inventory row. `id` corresponds to Sanctuary's `DbItem.Id` (an item
/// instance GUID), `definitionID` to `DbItem.Definition`.
struct LocalInventoryItem: Codable, Equatable, Identifiable {
    let id: UInt64
    var definitionID: Int
    var tint: Int
    var count: Int
}

/// Per-goal counters in the Sanctuary `CharacterQuestProgress` table.
struct LocalQuestGoalProgress: Codable, Equatable {
    var goalID: Int
    var targetID: UInt64
    var count: Int
}

/// Persisted quest row, mirroring `DbCharacterQuest` plus its progress rows.
struct LocalQuestProgress: Codable, Equatable {
    var questID: Int
    var currentGoalID: Int
    var completed: Bool
    var goalProgress: [LocalQuestGoalProgress]
}

/// Everything one character needs to enter an offline world session.
struct LocalCharacter: Codable, Equatable, Identifiable {
    let id: UInt64
    var name: String
    var zoneID: Int
    var position: LocalWorldPosition
    var coins: Int64
    var stationCash: Int64
    var inventory: [LocalInventoryItem]
    var quests: [LocalQuestProgress]
    var activeQuestID: Int?
    var isInWorld: Bool
    var locale: GameLocale
    var unlockAllProfiles: Bool
    var unlockAllTitles: Bool
    /// Offline-only host flag revealed by the native engine: every map tile in
    /// the loaded zone is walkable instead of only the server environment grid.
    var unlockAllTiles: Bool

    init(
        id: UInt64,
        name: String,
        zoneID: Int,
        position: LocalWorldPosition,
        coins: Int64,
        stationCash: Int64,
        inventory: [LocalInventoryItem],
        quests: [LocalQuestProgress],
        activeQuestID: Int?,
        isInWorld: Bool,
        locale: GameLocale,
        unlockAllProfiles: Bool,
        unlockAllTitles: Bool,
        unlockAllTiles: Bool = false
    ) {
        self.id = id
        self.name = name
        self.zoneID = zoneID
        self.position = position
        self.coins = coins
        self.stationCash = stationCash
        self.inventory = inventory
        self.quests = quests
        self.activeQuestID = activeQuestID
        self.isInWorld = isInWorld
        self.locale = locale
        self.unlockAllProfiles = unlockAllProfiles
        self.unlockAllTitles = unlockAllTitles
        self.unlockAllTiles = unlockAllTiles
    }

    /// Existing iOS stores predate `unlockAllTiles`; decode it as disabled.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UInt64.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        zoneID = try container.decode(Int.self, forKey: .zoneID)
        position = try container.decode(LocalWorldPosition.self, forKey: .position)
        coins = try container.decode(Int64.self, forKey: .coins)
        stationCash = try container.decode(Int64.self, forKey: .stationCash)
        inventory = try container.decode([LocalInventoryItem].self, forKey: .inventory)
        quests = try container.decode([LocalQuestProgress].self, forKey: .quests)
        activeQuestID = try container.decodeIfPresent(Int.self, forKey: .activeQuestID)
        isInWorld = try container.decode(Bool.self, forKey: .isInWorld)
        locale = try container.decode(GameLocale.self, forKey: .locale)
        unlockAllProfiles = try container.decode(Bool.self, forKey: .unlockAllProfiles)
        unlockAllTitles = try container.decode(Bool.self, forKey: .unlockAllTitles)
        unlockAllTiles = try container.decodeIfPresent(Bool.self, forKey: .unlockAllTiles) ?? false
    }

    /// Builds the first-run character from host configuration. The starter kit
    /// uses the Adventurer/Wizard default items and tints from Sanctuary's
    /// `Resources/Profiles.json` and `ClientItemDefinitions.json`; the starting
    /// quest is `2563` ("Introduce Yourself") from `Resources/Quests.json`.
    static func makeDefault(id: UInt64, name: String, configuration: LocalHostConfiguration) -> LocalCharacter {
        let starterDefinitions: [(definition: Int, tint: Int)] = [
            (12178, 244), (12060, 244), (12709, 233),
            (12416, 233), (12574, 232), (12252, 232), (4914, 234)
        ]
        let inventory = starterDefinitions.enumerated().map { index, item in
            LocalInventoryItem(id: UInt64(index + 1), definitionID: item.definition, tint: item.tint, count: 1)
        }
        let quests = [
            LocalQuestProgress(
                questID: 2563,
                currentGoalID: 0,
                completed: false,
                goalProgress: [LocalQuestGoalProgress(goalID: 0, targetID: 2049, count: 0)]
            )
        ]
        return LocalCharacter(
            id: id,
            name: name,
            zoneID: configuration.startingZoneID,
            position: .fabledRealmsSpawn,
            coins: configuration.startingCoins,
            stationCash: configuration.startingStationCash,
            inventory: inventory,
            quests: quests,
            activeQuestID: quests.first?.questID,
            isInWorld: false,
            locale: configuration.locale,
            unlockAllProfiles: configuration.unlockAllProfiles,
            unlockAllTitles: configuration.unlockAllTitles,
            unlockAllTiles: configuration.unlockAllTiles
        )
    }
}

/// Password record. Only the derived digest and salt are stored; no plaintext
/// and no bcrypt claim is made here.
struct LocalPasswordHash: Codable, Equatable {
    var algorithm: String
    var version: Int
    var iterations: Int
    var salt: Data
    var digest: Data
}

/// One offline account. `selectedCharacterID` is persisted so character select
/// can be restored after a relaunch; `maxCharacters` follows Sanctuary's default.
struct LocalAccount: Codable, Equatable, Identifiable {
    let id: UInt64
    var username: String
    var passwordHash: LocalPasswordHash
    var maxCharacters: Int
    var characters: [LocalCharacter]
    var selectedCharacterID: UInt64?
}

/// Top-level JSON document written to `local-session.json`.
struct LocalSessionFile: Codable, Equatable {
    var schemaVersion: Int = LocalSessionSchema.version
    var nextAccountID: UInt64 = 1
    var nextCharacterID: UInt64 = 1
    var nextItemID: UInt64 = 1
    var accounts: [LocalAccount] = []
}

// MARK: - Errors

enum LocalSessionError: LocalizedError, Equatable {
    case invalidDirectory(String)
    case corruptedStore(String)
    case unsupportedSchemaVersion(Int)
    case persistence(String)
    case invalidUsername(String)
    case invalidPassword
    case invalidCredentials
    case accountExists(String)
    case noActiveAccount
    case invalidCharacterName(String)
    case characterExists(String)
    case characterNotFound(UInt64)
    case characterLimitReached(Int)
    case noSelectedCharacter
    case alreadyInWorld
    case notInWorld
    case invalidPosition
    case invalidItem
    case invalidQuest(Int)
    case questAlreadyCompleted(Int)

    var errorDescription: String? {
        switch self {
        case .invalidDirectory(let path): return "Invalid local session directory: \(path)"
        case .corruptedStore(let detail): return "Corrupted local session store: \(detail)"
        case .unsupportedSchemaVersion(let version): return "Unsupported local session schema version \(version)."
        case .persistence(let detail): return "Could not save the local session: \(detail)"
        case .invalidUsername(let name): return "Invalid offline account name: \(name)"
        case .invalidPassword: return "Password must be 6–100 ASCII characters."
        case .invalidCredentials: return "Incorrect offline account name or password."
        case .accountExists(let name): return "An offline account named \(name) already exists."
        case .noActiveAccount: return "Log in to an offline account first."
        case .invalidCharacterName(let name): return "Invalid character name: \(name)"
        case .characterExists(let name): return "A character named \(name) already exists."
        case .characterNotFound(let id): return "No character with ID \(id)."
        case .characterLimitReached(let limit): return "This account has reached its limit of \(limit) characters."
        case .noSelectedCharacter: return "Select a character first."
        case .alreadyInWorld: return "The selected character is already in the world."
        case .notInWorld: return "Enter the world before issuing this command."
        case .invalidPosition: return "Position contains a non-finite value."
        case .invalidItem: return "Item definition ID and count must be positive."
        case .invalidQuest(let id): return "Invalid quest ID \(id)."
        case .questAlreadyCompleted(let id): return "Quest \(id) is already completed."
        }
    }
}

// MARK: - SHA-256 / HMAC / PBKDF2

/// Portable SHA-256. The app target is Foundation-only and must also build on
/// Linux, so CryptoKit/CommonCrypto are not imported; this pure-Swift
/// implementation is the portable fallback used on every platform. It is a
/// complete SHA-256 implementation (FIPS 180-4), not a stub.
enum LocalSHA256 {
    private static let constants: [UInt32] = [
        0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
        0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
        0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
        0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
        0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
        0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
        0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
        0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2
    ]

    static func hash(_ message: Data) -> Data {
        var state: [UInt32] = [
            0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
            0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19
        ]
        var bytes = [UInt8](message)
        let bitLength = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
        }

        var schedule = [UInt32](repeating: 0, count: 64)
        for blockStart in stride(from: 0, to: bytes.count, by: 64) {
            for index in 0..<16 {
                let offset = blockStart + index * 4
                schedule[index] = (UInt32(bytes[offset]) << 24)
                    | (UInt32(bytes[offset + 1]) << 16)
                    | (UInt32(bytes[offset + 2]) << 8)
                    | UInt32(bytes[offset + 3])
            }
            for index in 16..<64 {
                let wordA = schedule[index - 15]
                let wordB = schedule[index - 2]
                let sigma0 = rotateRight(wordA, 7) ^ rotateRight(wordA, 18) ^ (wordA >> 3)
                let sigma1 = rotateRight(wordB, 17) ^ rotateRight(wordB, 19) ^ (wordB >> 10)
                schedule[index] = schedule[index - 16] &+ sigma0 &+ schedule[index - 7] &+ sigma1
            }

            var a = state[0], b = state[1], c = state[2], d = state[3]
            var e = state[4], f = state[5], g = state[6], h = state[7]
            for index in 0..<64 {
                let sum1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25)
                let choose = (e & f) ^ (~e & g)
                let temp1 = h &+ sum1 &+ choose &+ constants[index] &+ schedule[index]
                let sum0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = sum0 &+ majority
                h = g; g = f; f = e; e = d &+ temp1
                d = c; c = b; b = a; a = temp1 &+ temp2
            }
            state[0] &+= a; state[1] &+= b; state[2] &+= c; state[3] &+= d
            state[4] &+= e; state[5] &+= f; state[6] &+= g; state[7] &+= h
        }

        var digest = Data()
        for word in state {
            digest.append(UInt8(truncatingIfNeeded: word >> 24))
            digest.append(UInt8(truncatingIfNeeded: word >> 16))
            digest.append(UInt8(truncatingIfNeeded: word >> 8))
            digest.append(UInt8(truncatingIfNeeded: word))
        }
        return digest
    }

    private static func rotateRight(_ value: UInt32, _ amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}

/// HMAC-SHA256 over the portable digest above.
enum LocalHMACSHA256 {
    static func authenticate(key: Data, message: Data) -> Data {
        var keyBytes = [UInt8](key)
        if keyBytes.count > 64 { keyBytes = [UInt8](LocalSHA256.hash(Data(keyBytes))) }
        keyBytes += [UInt8](repeating: 0, count: 64 - keyBytes.count)
        let inner = keyBytes.map { $0 ^ 0x36 }
        let outer = keyBytes.map { $0 ^ 0x5C }
        var innerInput = Data(inner)
        innerInput.append(message)
        var outerInput = Data(outer)
        outerInput.append(LocalSHA256.hash(innerInput))
        return LocalSHA256.hash(outerInput)
    }
}

/// PBKDF2-HMAC-SHA256 using the portable primitives above. This is a standard
/// KDF, but the offline store does NOT claim bcrypt/Sanctuary compatibility.
enum LocalPBKDF2 {
    static func derive(password: Data, salt: Data, iterations: Int, keyLength: Int = 32) -> Data {
        precondition(iterations > 0 && keyLength > 0)
        var output = Data()
        var block: UInt32 = 1
        while output.count < keyLength {
            var blockIndex = Data()
            for shift in stride(from: 24, through: 0, by: -8) {
                blockIndex.append(UInt8(truncatingIfNeeded: block >> UInt32(shift)))
            }
            var saltInput = salt
            saltInput.append(blockIndex)
            var u = LocalHMACSHA256.authenticate(key: password, message: saltInput)
            var t = u
            for _ in 1..<iterations {
                u = LocalHMACSHA256.authenticate(key: password, message: u)
                for index in 0..<32 { t[index] ^= u[index] }
            }
            output.append(t.prefix(keyLength - output.count))
            block &+= 1
        }
        return output
    }
}

enum LocalPasswordHasher {
    static let algorithm = "pbkdf2-hmac-sha256"
    static let version = 1
    /// Offline-first default. Not tuned to match Sanctuary's bcrypt cost.
    static let defaultIterations = 20_000
    private static let saltByteCount = 16
    private static let digestByteCount = 32

    static func makeHash(_ password: String, iterations: Int = defaultIterations) -> LocalPasswordHash {
        var salt = Data()
        for _ in 0..<saltByteCount { salt.append(UInt8.random(in: 0...255)) }
        return makeHash(password, salt: salt, iterations: iterations)
    }

    static func makeHash(_ password: String, salt: Data, iterations: Int) -> LocalPasswordHash {
        LocalPasswordHash(
            algorithm: algorithm,
            version: version,
            iterations: iterations,
            salt: salt,
            digest: LocalPBKDF2.derive(
                password: Data(password.utf8),
                salt: salt,
                iterations: iterations,
                keyLength: digestByteCount
            )
        )
    }

    static func verify(_ password: String, against record: LocalPasswordHash) -> Bool {
        guard record.algorithm == algorithm,
              record.version == version,
              record.iterations > 0,
              record.salt.count >= 8,
              !record.digest.isEmpty
        else { return false }
        let candidate = LocalPBKDF2.derive(
            password: Data(password.utf8),
            salt: record.salt,
            iterations: record.iterations,
            keyLength: record.digest.count
        )
        guard candidate.count == record.digest.count else { return false }
        var difference: UInt8 = 0
        for index in candidate.indices { difference |= candidate[index] ^ record.digest[index] }
        return difference == 0
    }
}

// MARK: - Session

/// In-process offline session. Every command mutates an in-memory Codable
/// snapshot and atomically writes it to `directory/local-session.json`.
///
/// The directory is supplied by the caller (tests use a temporary directory);
/// nothing here reads `Bundle.main`, app support paths, or network resources.
final class LocalSession {
    let directory: URL

    var storeURL: URL {
        directory.appendingPathComponent(LocalSessionSchema.fileName)
    }

    private var file: LocalSessionFile
    private(set) var activeAccountID: UInt64?
    private(set) var selectedCharacterID: UInt64?

    /// Opens an existing store or starts a new in-memory one. Corrupt files and
    /// unknown schema versions fail loudly instead of being silently reset.
    init(directory: URL) throws {
        guard directory.isFileURL, !directory.path.isEmpty else {
            throw LocalSessionError.invalidDirectory(directory.absoluteString)
        }
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw LocalSessionError.invalidDirectory(directory.path)
            }
        } else {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let resolvedDirectory = directory.standardizedFileURL
        let resolvedStoreURL = resolvedDirectory.appendingPathComponent(LocalSessionSchema.fileName)
        self.directory = resolvedDirectory
        if manager.fileExists(atPath: resolvedStoreURL.path) {
            let data: Data
            do {
                data = try Data(contentsOf: resolvedStoreURL)
            } catch {
                throw LocalSessionError.persistence(error.localizedDescription)
            }
            do {
                file = try JSONDecoder().decode(LocalSessionFile.self, from: data)
            } catch {
                throw LocalSessionError.corruptedStore(error.localizedDescription)
            }
            guard file.schemaVersion == LocalSessionSchema.version else {
                throw LocalSessionError.unsupportedSchemaVersion(file.schemaVersion)
            }
        } else {
            file = LocalSessionFile()
        }
    }

    // MARK: Read-only views for the UI

    var activeAccount: LocalAccount? {
        activeAccountID.flatMap { id in file.accounts.first { $0.id == id } }
    }

    var selectedCharacter: LocalCharacter? {
        selectedCharacterID.flatMap { id in activeAccount?.characters.first { $0.id == id } }
    }

    var characters: [LocalCharacter] { activeAccount?.characters ?? [] }

    // MARK: Account commands

    @discardableResult
    func createAccount(username rawName: String, password: String) throws -> LocalAccount {
        let name = try Self.validatedUsername(rawName)
        try Self.validatePassword(password)
        guard !file.accounts.contains(where: { $0.username.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw LocalSessionError.accountExists(name)
        }
        let account = LocalAccount(
            id: file.nextAccountID,
            username: name,
            passwordHash: LocalPasswordHasher.makeHash(password),
            maxCharacters: 10,
            characters: [],
            selectedCharacterID: nil
        )
        file.nextAccountID += 1
        file.accounts.append(account)
        try save()
        return account
    }

    /// Logs in and restores the previously selected character, if still present.
    @discardableResult
    func login(username rawName: String, password: String) throws -> LocalAccount {
        let name = try Self.validatedUsername(rawName)
        guard let index = file.accounts.firstIndex(where: {
            $0.username.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            // Do not reveal whether the name exists.
            throw LocalSessionError.invalidCredentials
        }
        guard LocalPasswordHasher.verify(password, against: file.accounts[index].passwordHash) else {
            throw LocalSessionError.invalidCredentials
        }
        activeAccountID = file.accounts[index].id
        let savedSelection = file.accounts[index].selectedCharacterID
        selectedCharacterID = savedSelection.flatMap { id in
            file.accounts[index].characters.contains(where: { $0.id == id }) ? id : nil
        }
        return file.accounts[index]
    }

    func logout() {
        activeAccountID = nil
        selectedCharacterID = nil
    }

    /// First-run helper matching the offline flow in ARCHITECTURE.md: create or
    /// log in the configured account, ensure the configured character exists,
    /// select it, and persist. A wrong password never creates a second account.
    @discardableResult
    func bootstrapOffline(configuration: LocalHostConfiguration, password: String) throws -> LocalCharacter {
        let matchingAccount = file.accounts.first {
            $0.username.caseInsensitiveCompare(configuration.accountName) == .orderedSame
        }
        if matchingAccount != nil {
            if activeAccountID != matchingAccount?.id {
                _ = try login(username: configuration.accountName, password: password)
            }
        } else {
            let account = try createAccount(username: configuration.accountName, password: password)
            activeAccountID = account.id
        }
        let name = try Self.validatedCharacterName(configuration.characterName)
        let accountIndex = try requireAccountIndex()
        let character: LocalCharacter
        if let characterIndex = file.accounts[accountIndex].characters.firstIndex(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            // Host settings are authoritative for this offline character. Apply
            // them to an existing save so changing zone/currency/unlocks in
            // Settings is visible immediately instead of only on a new game.
            let existing = file.accounts[accountIndex].characters[characterIndex]
            var updated = existing
            updated.zoneID = configuration.startingZoneID
            updated.coins = configuration.startingCoins
            updated.stationCash = configuration.startingStationCash
            updated.locale = configuration.locale
            updated.unlockAllProfiles = configuration.unlockAllProfiles
            updated.unlockAllTitles = configuration.unlockAllTitles
            updated.unlockAllTiles = configuration.unlockAllTiles
            if updated.zoneID != existing.zoneID {
                updated.position = .fabledRealmsSpawn
            }
            if updated != existing {
                file.accounts[accountIndex].characters[characterIndex] = updated
            }
            character = updated
        } else {
            character = try createCharacter(named: name, configuration: configuration)
        }
        selectedCharacterID = character.id
        file.accounts[accountIndex].selectedCharacterID = character.id
        try save()
        return character
    }

    // MARK: Character commands

    @discardableResult
    func createCharacter(
        named rawName: String,
        configuration: LocalHostConfiguration = LocalHostConfiguration()
    ) throws -> LocalCharacter {
        let name = try Self.validatedCharacterName(rawName)
        let index = try requireAccountIndex()
        guard !file.accounts[index].characters.contains(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            throw LocalSessionError.characterExists(name)
        }
        guard file.accounts[index].characters.count < file.accounts[index].maxCharacters else {
            throw LocalSessionError.characterLimitReached(file.accounts[index].maxCharacters)
        }
        let character = LocalCharacter.makeDefault(id: file.nextCharacterID, name: name, configuration: configuration)
        file.nextCharacterID += 1
        // Starter items occupy IDs 1..N; keep future grants globally unique.
        if let highestStarterID = character.inventory.map(\.id).max() {
            file.nextItemID = max(file.nextItemID, highestStarterID + 1)
        }
        file.accounts[index].characters.append(character)
        try save()
        return character
    }

    func selectCharacter(id: UInt64) throws {
        let index = try requireAccountIndex()
        guard file.accounts[index].characters.contains(where: { $0.id == id }) else {
            throw LocalSessionError.characterNotFound(id)
        }
        file.accounts[index].selectedCharacterID = id
        selectedCharacterID = id
        try save()
    }

    @discardableResult
    func enterWorld() throws -> LocalCharacter {
        let (accountIndex, characterIndex) = try requireSelectedCharacter()
        guard !file.accounts[accountIndex].characters[characterIndex].isInWorld else {
            throw LocalSessionError.alreadyInWorld
        }
        file.accounts[accountIndex].characters[characterIndex].isInWorld = true
        try save()
        return file.accounts[accountIndex].characters[characterIndex]
    }

    func leaveWorld() throws {
        let (accountIndex, characterIndex) = try requireSelectedCharacter()
        file.accounts[accountIndex].characters[characterIndex].isInWorld = false
        try save()
    }

    func movePlayer(to position: LocalWorldPosition) throws {
        guard position.isValid else { throw LocalSessionError.invalidPosition }
        let (accountIndex, characterIndex) = try requireSelectedCharacter(requireInWorld: true)
        file.accounts[accountIndex].characters[characterIndex].position = position
        try save()
    }

    @discardableResult
    func grantItem(definitionID: Int, count: Int = 1, tint: Int = 0) throws -> LocalInventoryItem {
        guard definitionID > 0, count > 0, tint >= 0 else { throw LocalSessionError.invalidItem }
        let (accountIndex, characterIndex) = try requireSelectedCharacter(requireInWorld: true)
        var inventory = file.accounts[accountIndex].characters[characterIndex].inventory
        if let existing = inventory.firstIndex(where: {
            $0.definitionID == definitionID && $0.tint == tint
        }) {
            inventory[existing].count += count
            file.accounts[accountIndex].characters[characterIndex].inventory = inventory
            try save()
            return inventory[existing]
        }
        let item = LocalInventoryItem(
            id: file.nextItemID,
            definitionID: definitionID,
            tint: tint,
            count: count
        )
        file.nextItemID += 1
        inventory.append(item)
        file.accounts[accountIndex].characters[characterIndex].inventory = inventory
        try save()
        return item
    }

    /// Persists per-goal progress for an active quest. Sanctuary keeps one
    /// `CharacterQuestProgress` row plus its goal counters, so advancing a goal
    /// must be durable before the quest is completed.
    @discardableResult
    func updateQuestProgress(_ progress: LocalQuestProgress) throws -> LocalQuestProgress {
        guard progress.questID > 0 else { throw LocalSessionError.invalidQuest(progress.questID) }
        guard progress.goalProgress.allSatisfy({ $0.count >= 0 }) else {
            throw LocalSessionError.invalidQuest(progress.questID)
        }
        let (accountIndex, characterIndex) = try requireSelectedCharacter(requireInWorld: true)
        var quests = file.accounts[accountIndex].characters[characterIndex].quests
        if let index = quests.firstIndex(where: { $0.questID == progress.questID }) {
            // Completed rows are immutable; WorldSimulation persists completion
            // through completeQuest, which also clears the active quest.
            guard !quests[index].completed else { return quests[index] }
            quests[index] = progress
        } else {
            guard !progress.completed else { throw LocalSessionError.invalidQuest(progress.questID) }
            quests.append(progress)
        }
        quests.sort { $0.questID < $1.questID }
        file.accounts[accountIndex].characters[characterIndex].quests = quests
        file.accounts[accountIndex].characters[characterIndex].activeQuestID =
            quests.first(where: { !$0.completed })?.questID
        try save()
        return progress
    }

    /// Marks quest progress complete. Rewards, prerequisites, and goal rules are
    /// intentionally not simulated in this first layer.
    @discardableResult
    func completeQuest(questID: Int) throws -> LocalQuestProgress {
        guard questID > 0 else { throw LocalSessionError.invalidQuest(questID) }
        let (accountIndex, characterIndex) = try requireSelectedCharacter(requireInWorld: true)
        var quests = file.accounts[accountIndex].characters[characterIndex].quests
        let completed: LocalQuestProgress
        if let index = quests.firstIndex(where: { $0.questID == questID }) {
            guard !quests[index].completed else { throw LocalSessionError.questAlreadyCompleted(questID) }
            quests[index].completed = true
            completed = quests[index]
        } else {
            completed = LocalQuestProgress(
                questID: questID,
                currentGoalID: 0,
                completed: true,
                goalProgress: []
            )
            quests.append(completed)
        }
        quests.sort { $0.questID < $1.questID }
        file.accounts[accountIndex].characters[characterIndex].quests = quests
        file.accounts[accountIndex].characters[characterIndex].activeQuestID =
            quests.first(where: { !$0.completed })?.questID
        try save()
        return completed
    }

    /// Explicit save for callers that batch in-memory edits. All commands above
    /// already save, so UI code usually does not need to call this.
    func save() throws {
        var data: Data
        do {
            data = try JSONEncoder().encode(file)
        } catch {
            throw LocalSessionError.persistence(error.localizedDescription)
        }
        data.append(0x0A)
        do {
            try data.write(to: storeURL, options: .atomic)
        } catch {
            throw LocalSessionError.persistence(error.localizedDescription)
        }
    }

    // MARK: Internals

    private func requireAccountIndex() throws -> Int {
        guard let accountID = activeAccountID,
              let index = file.accounts.firstIndex(where: { $0.id == accountID })
        else {
            throw LocalSessionError.noActiveAccount
        }
        return index
    }

    private func requireSelectedCharacter(requireInWorld: Bool = false) throws -> (Int, Int) {
        let accountIndex = try requireAccountIndex()
        guard let selectedID = selectedCharacterID,
              let characterIndex = file.accounts[accountIndex].characters.firstIndex(where: { $0.id == selectedID })
        else {
            throw LocalSessionError.noSelectedCharacter
        }
        if requireInWorld && !file.accounts[accountIndex].characters[characterIndex].isInWorld {
            throw LocalSessionError.notInWorld
        }
        return (accountIndex, characterIndex)
    }

    private static func validatedUsername(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.")
        guard (3...50).contains(name.utf8.count),
              name.unicodeScalars.allSatisfy({ allowed.contains($0) })
        else {
            throw LocalSessionError.invalidUsername(raw)
        }
        return name
    }

    private static func validatePassword(_ password: String) throws {
        guard (6...100).contains(password.utf8.count),
              password.utf8.allSatisfy({ $0 < 128 })
        else {
            throw LocalSessionError.invalidPassword
        }
    }

    private static func validatedCharacterName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...32).contains(name.utf8.count),
              !name.contains("/"),
              !name.contains("\\"),
              name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else {
            throw LocalSessionError.invalidCharacterName(raw)
        }
        return name
    }
}
