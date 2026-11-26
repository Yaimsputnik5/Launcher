import Foundation
import XCTest
@testable import OSFRCore

/// Covers the active-session value types, persisted offline host settings, and
/// the Foundation-only engine that feeds the Metal renderer.
final class EngineTests: XCTestCase {
    private var tempRoots: [URL] = []

    override func tearDown() {
        for root in tempRoots { try? FileManager.default.removeItem(at: root) }
        tempRoots.removeAll()
        super.tearDown()
    }

    private func makeResourceRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "EngineTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        tempRoots.append(root)
        try write(Self.zoneJSON, relativePath: "Resources/Zones/FabledRealms.json", in: root)
        try write(Self.environmentJSON, relativePath: "Resources/Zones/Environments/FabledRealms.json", in: root)
        for name in ["Npcs", "Quests", "Collections", "CollectionNodeTypes", "CollectionNodePools"] {
            try write("[]", relativePath: "Resources/\(name).json", in: root)
        }
        try write("[]", relativePath: "Resources/PointOfInterests.json", in: root)
        try write("[]", relativePath: "Resources/Profiles.json", in: root)
        try write("[]", relativePath: "Resources/PlayerTitles.json", in: root)
        return root
    }

    private func write(_ text: String, relativePath: String, in root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testLegacyAppSettingsDecodeSuppliesOfflineHostDefaults() throws {
        let json = """
        {"servers":[],"downloadThreads":4,"parallelDownloads":true,"locale":"en_US","didSeedDefaultServers":true}
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertTrue(settings.didSeedDefaultServers)
        XCTAssertEqual(settings.hostConfiguration.accountName, "local")
        XCTAssertEqual(settings.hostConfiguration.characterName, "Player")
        XCTAssertEqual(settings.hostConfiguration.startingZoneID, 1)
        XCTAssertFalse(settings.hostConfiguration.unlockAllTiles)
        XCTAssertEqual(settings.hostConfiguration.profileName, "local")
        XCTAssertEqual(settings.hostConfiguration.playerName, "Player")
    }

    func testHostConfigurationIsAppliedToSimulation() throws {
        let root = try makeResourceRoot()
        var configuration = LocalHostConfiguration()
        configuration.accountName = "Profile One"
        configuration.characterName = "Hero"
        configuration.locale = .en_GB
        configuration.startingZoneID = 1
        configuration.unlockAllProfiles = false
        configuration.unlockAllTitles = false
        configuration.unlockAllTiles = true
        configuration.startingCoins = 123
        configuration.startingStationCash = 456

        let simulation = try WorldSimulation(
            rootURL: root,
            zoneID: configuration.startingZoneID,
            hostConfiguration: configuration
        )
        let snapshot = simulation.snapshot
        XCTAssertEqual(snapshot.zoneID, 1)
        XCTAssertEqual(snapshot.playerName, "Hero")
        XCTAssertEqual(snapshot.profileName, "Profile One")
        XCTAssertEqual(snapshot.locale, .en_GB)
        XCTAssertEqual(snapshot.coins, 123)
        XCTAssertEqual(snapshot.stationCash, 456)
        XCTAssertFalse(snapshot.options.unlockAllProfiles)
        XCTAssertFalse(snapshot.options.unlockAllTitles)
        XCTAssertTrue(snapshot.options.unlockAllTiles)
    }

    func testUnlockAllTilesChangesWalkability() throws {
        let root = try makeResourceRoot()
        let blocked = ZoneVector(x: -2_016, y: 0, z: 288, w: 0)
        let normal = try WorldSimulation(rootURL: root, zoneID: 1)
        XCTAssertFalse(normal.isWalkable(blocked))

        var configuration = LocalHostConfiguration()
        configuration.unlockAllTiles = true
        let unlocked = try WorldSimulation(
            rootURL: root,
            zoneID: 1,
            hostConfiguration: configuration
        )
        XCTAssertTrue(unlocked.isWalkable(blocked))
    }

    func testEngineOwnsTicksAndProducesProjectedScene() throws {
        let root = try makeResourceRoot()
        let simulation = try WorldSimulation(rootURL: root, zoneID: 1)
        let engine = OSFREngine(simulation: simulation)
        XCTAssertFalse(engine.frame.drawables.isEmpty)
        XCTAssertTrue(engine.frame.drawables.contains { $0.kind == .tile })
        XCTAssertTrue(engine.frame.drawables.contains { $0.kind == .player })

        let start = Date()
        engine.advance(now: start)
        engine.advance(now: start.addingTimeInterval(0.1))
        engine.advance(now: start.addingTimeInterval(0.2))
        XCTAssertGreaterThanOrEqual(engine.frame.movementTick, 2)

        engine.handle(.zoom(2))
        XCTAssertEqual(engine.camera.zoom, 2)
        let projected = try XCTUnwrap(engine.frame.drawables.first { $0.kind == .player })
        XCTAssertEqual(projected.rect.width, 0.009 * 2 * 2, accuracy: 0.000_001)

        engine.handle(.recenter())
        XCTAssertEqual(engine.camera.zoom, 2)
        XCTAssertGreaterThanOrEqual(engine.sceneGraph.flattenedDrawables.count, 1)
    }

    func testActiveWorldSessionIdentitySeparatesLoginFromWorld() {
        let login = WorldSessionConfiguration(
            mode: .remote,
            host: "play.example",
            username: "user",
            sessionID: "session",
            characterID: nil,
            ticket: nil,
            cryptoKey: nil,
            loginArguments: [],
            locale: .en_US
        )
        XCTAssertFalse(login.canJoinGateway)

        var world = login
        world.ticket = "ticket"
        world.gatewayAddress = "127.0.0.1:20260"
        world.gatewayGUID = 7
        XCTAssertTrue(world.canJoinGateway)

        let active = ActiveWorldSession(
            id: UUID(),
            configuration: world,
            hostConfiguration: nil,
            startedAt: Date()
        )
        XCTAssertEqual(active.mode, .remote)
        XCTAssertEqual(active.displayName, "user")
    }

    private static let zoneJSON = """
    {
      "$type": "World",
      "Id": 1,
      "Name": "FabledRealms",
      "TileSize": 64,
      "StartLatitude": -32,
      "EndLatitude": -28,
      "StartLongitude": 4,
      "EndLongitude": 8,
      "SpawnPosition": [-1904, -39.7098, 412],
      "SpawnRotation": [0.55, 0.83],
      "Scripts": [],
      "EnabledClientAreaIds": [],
      "AreaDefinitions": []
    }
    """

    private static let environmentJSON = """
    {
      "Environments": { "-1": "OutOfBounds", "10": "Grass" },
      "StartLongitude": 4,
      "StartLatitude": -32,
      "Rows": [
        [-1, -1, -1, -1],
        [-1, -1, -1, -1],
        [-1, -1, 10, -1],
        [-1, -1, -1, -1]
      ]
    }
    """
}
