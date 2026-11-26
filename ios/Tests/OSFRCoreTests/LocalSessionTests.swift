import Foundation
import XCTest
@testable import OSFRCore

final class LocalSessionTests: XCTestCase {
    private var directory: URL!
    private let password = "offline-pass-123"

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LocalSessionTests-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        super.tearDown()
    }

    func testCreateAccountPersistsAndLoadsFromExplicitDirectory() throws {
        let session = try LocalSession(directory: directory)
        let account = try session.createAccount(username: "local", password: password)

        XCTAssertEqual(account.username, "local")
        XCTAssertEqual(account.maxCharacters, 10)
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.storeURL.path))

        let rawJSON = String(data: try Data(contentsOf: session.storeURL), encoding: .utf8)
        XCTAssertNotNil(rawJSON?.range(of: #""schemaVersion":1"#))
        XCTAssertFalse(rawJSON?.contains(password) ?? true)

        let reopened = try LocalSession(directory: directory)
        let loaded = try reopened.login(username: "LOCAL", password: password)
        XCTAssertEqual(loaded.id, account.id)
        XCTAssertEqual(loaded.username, "local")
    }

    func testWrongPasswordIsRejectedWithoutChangingSession() throws {
        let session = try LocalSession(directory: directory)
        let account = try session.createAccount(username: "local", password: password)
        _ = try session.login(username: "local", password: password)

        XCTAssertThrowsError(try session.login(username: "local", password: "not-the-password")) { error in
            XCTAssertEqual(error as? LocalSessionError, .invalidCredentials)
        }
        XCTAssertEqual(session.activeAccountID, account.id)

        let reopened = try LocalSession(directory: directory)
        XCTAssertThrowsError(try reopened.login(username: "local", password: "not-the-password")) { error in
            XCTAssertEqual(error as? LocalSessionError, .invalidCredentials)
        }
        XCTAssertNil(reopened.activeAccountID)
    }

    func testBootstrapCreatesDefaultCharacterFromConfiguration() throws {
        var configuration = LocalHostConfiguration()
        configuration.accountName = "local"
        configuration.characterName = "Tester"
        configuration.startingZoneID = 7
        configuration.startingCoins = 1_234
        configuration.startingStationCash = 56
        configuration.locale = .en_GB
        configuration.unlockAllProfiles = false
        configuration.unlockAllTitles = true

        let session = try LocalSession(directory: directory)
        let character = try session.bootstrapOffline(configuration: configuration, password: password)

        XCTAssertEqual(character.name, "Tester")
        XCTAssertEqual(character.zoneID, 7)
        XCTAssertEqual(character.position, .fabledRealmsSpawn)
        XCTAssertEqual(character.coins, 1_234)
        XCTAssertEqual(character.stationCash, 56)
        XCTAssertEqual(character.locale, .en_GB)
        XCTAssertFalse(character.unlockAllProfiles)
        XCTAssertTrue(character.unlockAllTitles)
        XCTAssertEqual(character.inventory.count, 7)
        XCTAssertEqual(character.inventory.first?.definitionID, 12178)
        XCTAssertEqual(character.quests.map(\.questID), [2563])
        XCTAssertEqual(character.quests.first?.goalProgress.first?.targetID, 2049)
        XCTAssertEqual(session.selectedCharacter?.id, character.id)
    }

    func testDuplicateCharacterNamesAreRejectedCaseInsensitively() throws {
        let session = try LocalSession(directory: directory)
        let first = try session.bootstrapOffline(configuration: LocalHostConfiguration(), password: password)

        XCTAssertThrowsError(try session.createCharacter(named: "PLAYER")) { error in
            XCTAssertEqual(error as? LocalSessionError, .characterExists("PLAYER"))
        }
        XCTAssertEqual(session.characters.count, 1)

        let second = try session.createCharacter(named: "Second")
        XCTAssertNotEqual(second.id, first.id)
        XCTAssertEqual(session.characters.count, 2)

        let reopened = try LocalSession(directory: directory)
        _ = try reopened.login(username: "local", password: password)
        XCTAssertEqual(reopened.characters.count, 2)
    }

    func testStateTransitionSurvivesReload() throws {
        let configuration = LocalHostConfiguration()
        let session = try LocalSession(directory: directory)
        let created = try session.bootstrapOffline(configuration: configuration, password: password)

        try session.enterWorld()
        let destination = LocalWorldPosition(x: 1.5, y: -2, z: 30, rotationX: 0.25, rotationZ: -0.5)
        try session.movePlayer(to: destination)
        let granted = try session.grantItem(definitionID: 9999, count: 2, tint: 5)
        _ = try session.grantItem(definitionID: 9999, count: 3, tint: 5)
        _ = try session.completeQuest(questID: 2563)

        let reopened = try LocalSession(directory: directory)
        _ = try reopened.login(username: configuration.accountName, password: password)
        let loaded = try XCTUnwrap(reopened.selectedCharacter)
        XCTAssertEqual(loaded.id, created.id)
        XCTAssertTrue(loaded.isInWorld)
        XCTAssertEqual(loaded.position, destination)
        XCTAssertEqual(loaded.inventory.first(where: { $0.id == granted.id })?.count, 5)
        XCTAssertEqual(loaded.quests.first(where: { $0.questID == 2563 })?.completed, true)

        XCTAssertThrowsError(try reopened.enterWorld()) { error in
            XCTAssertEqual(error as? LocalSessionError, .alreadyInWorld)
        }
        let invalid = LocalWorldPosition(x: .nan, y: 0, z: 0, rotationX: 0, rotationZ: 0)
        XCTAssertThrowsError(try reopened.movePlayer(to: invalid)) { error in
            XCTAssertEqual(error as? LocalSessionError, .invalidPosition)
        }
    }

    func testQuestGoalProgressPersistsBeforeCompletion() throws {
        let configuration = LocalHostConfiguration()
        let session = try LocalSession(directory: directory)
        _ = try session.bootstrapOffline(configuration: configuration, password: password)
        try session.enterWorld()

        var progress = try XCTUnwrap(session.selectedCharacter?.quests.first { $0.questID == 2563 })
        progress.currentGoalID = 99
        progress.goalProgress[0].count = 2
        try session.updateQuestProgress(progress)

        let reopened = try LocalSession(directory: directory)
        _ = try reopened.login(username: configuration.accountName, password: password)
        let loaded = try XCTUnwrap(reopened.selectedCharacter)
        XCTAssertEqual(loaded.quests.first(where: { $0.questID == 2563 })?.currentGoalID, 99)
        XCTAssertEqual(loaded.quests.first(where: { $0.questID == 2563 })?.goalProgress.first?.count, 2)
        XCTAssertEqual(loaded.activeQuestID, 2563)

        _ = try reopened.completeQuest(questID: 2563)
        let completed = try LocalSession(directory: directory)
        _ = try completed.login(username: configuration.accountName, password: password)
        XCTAssertTrue(completed.selectedCharacter?.quests.first(where: { $0.questID == 2563 })?.completed == true)
        XCTAssertNil(completed.selectedCharacter?.activeQuestID)
    }

    func testUnsupportedSchemaVersionIsRejected() throws {
        let session = try LocalSession(directory: directory)
        _ = try session.createAccount(username: "local", password: password)
        var json = try XCTUnwrap(String(data: Data(contentsOf: session.storeURL), encoding: .utf8))
        json = json.replacingOccurrences(of: #""schemaVersion":1"#, with: #""schemaVersion":99"#)
        try Data(json.utf8).write(to: session.storeURL)

        XCTAssertThrowsError(try LocalSession(directory: directory)) { error in
            XCTAssertEqual(error as? LocalSessionError, .unsupportedSchemaVersion(99))
        }
    }

    func testPortableSHA256Vector() {
        let digest = LocalSHA256.hash(Data("abc".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
