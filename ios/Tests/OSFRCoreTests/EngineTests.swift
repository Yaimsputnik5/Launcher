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

    private func le32(_ value: UInt32) -> Data {
        Data([
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 24)
        ])
    }

    private func be32(_ value: UInt32) -> Data {
        Data([
            UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value)
        ])
    }

    /// Minimal uncompressed BGRA DDS, laid out like the decoded client images.
    private func testDDS(width: Int, height: Int) -> Data {
        var data = Data("DDS ".utf8)
        data.append(le32(124))
        data.append(le32(0x1007))
        data.append(le32(UInt32(height)))
        data.append(le32(UInt32(width)))
        data.append(le32(UInt32(width * 4)))
        data.append(le32(0))
        data.append(le32(0))
        for _ in 0..<11 { data.append(le32(0)) }
        data.append(le32(32))
        data.append(le32(0x41))
        data.append(Data(repeating: 0, count: 4))
        data.append(le32(32))
        data.append(le32(0x00FF_0000))
        data.append(le32(0x0000_FF00))
        data.append(le32(0x0000_00FF))
        data.append(le32(0xFF00_0000))
        data.append(le32(0x1000))
        for _ in 0..<4 { data.append(le32(0)) }
        precondition(data.count == 128)
        for index in 0..<(width * height) {
            let red: UInt8 = index % 2 == 0 ? 220 : 40
            data.append(contentsOf: [0, 0, red, 255])
        }
        return data
    }

    /// Single-entry `.pack` with the observed big-endian directory layout.
    private func testPack(name: String, payload: Data) -> Data {
        let nameBytes = Data(name.utf8)
        var directory = be32(0)
        directory.append(be32(1))
        directory.append(be32(UInt32(nameBytes.count)))
        directory.append(nameBytes)
        directory.append(be32(UInt32(directory.count + 12)))
        directory.append(be32(UInt32(payload.count)))
        directory.append(be32(CRC32.checksum(payload)))
        var result = directory
        result.append(payload)
        return result
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

    func testClientTextureCatalogPointsAtVerifiedFabledRealmsTile() {
        XCTAssertEqual(
            ClientTextureCatalog.texturePath(forZoneName: "FabledRealms"),
            "Assets_000.pack#FabledRealms_Tile_000_-08_0_0.dds"
        )
        XCTAssertNil(ClientTextureCatalog.texturePath(forZoneName: "UnknownZone"))
    }

    func testEngineLoadsDecodedClientTextureIntoRenderFrame() throws {
        let root = try makeResourceRoot()
        let simulation = try WorldSimulation(rootURL: root, zoneID: 1)
        let payload = testDDS(width: 4, height: 4)
        let pack = testPack(name: "tile.dds", payload: payload)
        let reference = "Assets_test.pack#tile.dds"
        let loader = TextureLoader { path in
            path == "Assets_test.pack" ? pack : nil
        }
        let engine = OSFREngine(
            simulation: simulation,
            assetPipeline: EngineAssetPipeline(loader: loader),
            terrainTexturePath: reference
        )

        let textured = try XCTUnwrap(engine.frame.drawables.first { $0.kind == .clientTexture })
        XCTAssertEqual(textured.textureName, reference)
        let image = try XCTUnwrap(engine.frame.textures[reference])
        XCTAssertEqual(image.width, 4)
        XCTAssertEqual(image.height, 4)
        XCTAssertEqual(image.byteCount, 4 * 4 * 4)
        XCTAssertTrue(engine.frame.textureStatus?.contains("Embedded client DDS 4x4") == true)
    }

    func testEngineDrawsShippedMinimapTilesAtTileInfoWorldRectangles() throws {
        let root = try makeResourceRoot()
        let simulation = try WorldSimulation(rootURL: root, zoneID: 1)
        let name = "FabledRealms_Tile_005_-32_0_0.dds"
        let payload = testDDS(width: 4, height: 4)
        let tilePack = testPack(name: name, payload: payload)
        let row = "\(name)\t-2048.000000\t0.000000\t320.000000\t128.000000\t128.000000\n"
        let infoPack = testPack(name: "FabledRealms_TileInfo.txt", payload: Data(row.utf8))
        let atlas = ClientMinimapAtlas(dataLoader: ClientAssetDataLoader { path in
            switch path {
            case "Assets_000.pack": return tilePack
            case "Assets_002.pack": return infoPack
            default: return nil
            }
        })
        XCTAssertEqual(atlas.tiles.count, 1)

        let texturePath = "Assets_000.pack#\(name)"
        let engine = OSFREngine(
            simulation: simulation,
            assetPipeline: EngineAssetPipeline(loader: TextureLoader { path in
                path == "Assets_000.pack" ? tilePack : nil
            }),
            terrainTexturePath: "",
            minimapAtlas: atlas
        )

        let minimapTile = try XCTUnwrap(engine.frame.drawables.first {
            $0.kind == .tile && $0.textureName == texturePath
        })
        XCTAssertTrue(minimapTile.label.contains(name))
        XCTAssertEqual(engine.frame.textures[texturePath]?.width, 4)
        XCTAssertTrue(engine.frame.textureStatus?.contains("decoded 1") == true)
    }

    func testRemoteEngineDoesNotInjectStaticMinimapTiles() throws {
        let root = try makeResourceRoot()
        let simulation = try WorldSimulation(rootURL: root, zoneID: 1)
        let name = "FabledRealms_Tile_005_-32_0_0.dds"
        let tilePack = testPack(name: name, payload: testDDS(width: 4, height: 4))
        let row = "\(name)\t-2048.000000\t0.000000\t320.000000\t128.000000\t128.000000\n"
        let infoPack = testPack(name: "FabledRealms_TileInfo.txt", payload: Data(row.utf8))
        let atlas = ClientMinimapAtlas(dataLoader: ClientAssetDataLoader { path in
            switch path {
            case "Assets_000.pack": return tilePack
            case "Assets_002.pack": return infoPack
            default: return nil
            }
        })
        XCTAssertEqual(atlas.tiles.count, 1)

        let engine = OSFREngine(
            simulation: simulation,
            presentationMode: .remote,
            minimapAtlas: atlas
        )
        XCTAssertFalse(engine.frame.drawables.contains {
            $0.textureName == "Assets_000.pack#\(name)"
        })
        XCTAssertFalse(engine.frame.textureStatus?.contains("decoded 1") == true)
    }

    private func cString(_ value: String) -> Data {
        Data(value.utf8) + Data([0])
    }

    /// Minimal GZNE v3 with one material and bounds matching the test zone JSON.
    private func testZone() -> Data {
        var data = Data("GZNE".utf8)
        data.append(le32(3))
        data.append(le32(0))
        data.append(le32(0x0002_0000))
        data.append(le32(128))
        data.append(le32(Float(100).bitPattern))
        data.append(le32(8))
        data.append(le32(4))
        data.append(le32(UInt32(bitPattern: -32)))
        data.append(le32(8))
        data.append(le32(UInt32(bitPattern: -28)))
        data.append(le32(0x0016_5C59))
        data.append(le32(1))
        data.append(le32(0))
        precondition(data.count == 56)
        data.append(cString("SG_Dirt"))
        data.append(cString("sg_dirt.dds"))
        data.append(le32(8))
        data.append(le32(0))
        data.append(le32(1))
        return data
    }

    func testEngineTerrainColorsComeFromClientGroundTexture() throws {
        let root = try makeResourceRoot()
        let simulation = try WorldSimulation(rootURL: root, zoneID: 1)
        let payload = testDDS(width: 4, height: 4)
        let terrainPack = testPack(name: "sg_dirt.dds", payload: payload)
        let loader = TextureLoader { path in
            path == "Assets_008.pack" ? terrainPack : nil
        }
        let engine = OSFREngine(
            simulation: simulation,
            assetPipeline: EngineAssetPipeline(loader: loader),
            terrainTexturePath: "",
            zoneManifest: try ClientZoneManifest(data: testZone())
        )

        XCTAssertTrue(engine.frame.zoneStatus?.contains("confirmed") == true)
        XCTAssertNotNil(engine.terrainPalette.colorsByEnvironmentID[10])
        let tile = try XCTUnwrap(engine.frame.drawables.first { $0.kind == .tile && $0.label.contains("SG_Dirt") })
        XCTAssertEqual(tile.color, engine.terrainPalette.color(environmentID: 10))
        XCTAssertNotEqual(tile.color, EngineColor(r: 0.18, g: 0.18, b: 0.20, a: 1))
        XCTAssertTrue(engine.frame.textures["Assets_008.pack#sg_dirt.dds"] != nil)
    }

    func testGatewayWorldObservationDrivesRemoteEngineWithoutOfflineEntities() throws {
        let root = try makeResourceRoot()
        let simulation = try WorldSimulation(rootURL: root, zoneID: 1)
        let guid: UInt64 = 42
        var observation = GatewayWorldObservation.empty
        observation.apply(
            .positionUpdate(WorldPositionUpdate(
                guid: guid,
                position: GatewayVector3(x: -1904, y: 0, z: 412),
                rotation: GatewayVector3(x: 0, y: 0, z: 0),
                state: 0,
                teleportSequence: 0
            )),
            now: Date(timeIntervalSince1970: 1)
        )
        XCTAssertEqual(observation.positionCount, 1)

        let engine = OSFREngine(
            simulation: simulation,
            terrainTexturePath: "",
            presentationMode: .remote,
            selfGUID: guid,
            remoteObservation: observation
        )
        let marker = try XCTUnwrap(engine.frame.drawables.first { $0.kind == .player })
        XCTAssertEqual(marker.label, "Packet you · 42")
        XCTAssertFalse(engine.frame.drawables.contains { $0.kind == .npc })
        XCTAssertFalse(engine.frame.drawables.contains { $0.kind == .collection })
        XCTAssertTrue(engine.frame.worldStatus?.contains("1 positions") == true)

        engine.applyRemoteObservation(.empty)
        XCTAssertFalse(engine.frame.drawables.contains { $0.kind == .player })
        XCTAssertEqual(engine.frame.worldStatus?.contains("0 positions"), true)
    }

    func testGatewayWorldObservationStoresDecodedChatOnly() {
        var observation = GatewayWorldObservation.empty
        let chat = GatewayChatMessage(
            channel: .worldSay,
            fromGUID: 7,
            toGUID: 0,
            fromName: GatewayName(
                firstNameID: 0,
                lastNamePrefixID: 0,
                lastNameSuffixID: 0,
                firstName: "Ada",
                lastName: "Lovelace"
            ),
            toName: GatewayName(
                firstNameID: 0,
                lastNamePrefixID: 0,
                lastNameSuffixID: 0,
                firstName: "",
                lastName: ""
            ),
            message: "packet-backed hello",
            position: GatewayVector4(x: 0, y: 0, z: 0, w: 0),
            guildGUID: 0,
            languageID: 0
        )
        observation.apply(.chat(chat), now: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(observation.chatCount, 1)
        XCTAssertEqual(observation.chatMessages.first?.fromName, "Ada Lovelace")
        XCTAssertEqual(observation.chatMessages.first?.message, "packet-backed hello")
        XCTAssertEqual(observation.chatMessages.first?.id, 1)
    }

    func testEngineDrawsClientChunkObjectsOfflineButNeverInRemoteMode() throws {
        let root = try makeResourceRoot()
        let simulation = try WorldSimulation(rootURL: root, zoneID: 1)
        let object = ClientChunkObject(
            chunkName: "FabledRealms_4_-32.gcnk",
            assetName: "sg_tree_giant_03.adr",
            position: ZoneVector(x: -1904, y: 0, z: 412, w: 0),
            rotation: ClientChunkRotation(x: 0, y: 0, z: 0),
            scale: 1
        )
        let catalog = ClientChunkCatalog(
            objects: [object],
            chunkCount: 1,
            status: "1 client object from 1 GCNK chunk"
        )

        let offline = OSFREngine(
            simulation: simulation,
            terrainTexturePath: "",
            clientObjectCatalog: catalog
        )
        let marker = try XCTUnwrap(
            offline.frame.drawables.first { $0.kind == .clientObject }
        )
        XCTAssertEqual(marker.label, "sg_tree_giant_03.adr")
        XCTAssertEqual(offline.frame.clientObjectStatus, catalog.status)

        let remote = OSFREngine(
            simulation: simulation,
            terrainTexturePath: "",
            presentationMode: .remote,
            clientObjectCatalog: catalog
        )
        XCTAssertFalse(remote.frame.drawables.contains { $0.kind == .clientObject })
        XCTAssertNil(remote.frame.clientObjectStatus)
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
