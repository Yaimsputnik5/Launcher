import Foundation
import XCTest
@testable import OSFRCore

/// In-memory fixtures for the native simulation. The zone is a 4x4 grid with a
/// single walkable tile so blocked movement and inferred NPC placement are easy
/// to assert without depending on the bundled FabledRealms resources.
final class GameWorldTests: XCTestCase {
    private var tempRoots: [URL] = []

    override func tearDown() {
        for root in tempRoots {
            try? FileManager.default.removeItem(at: root)
        }
        tempRoots.removeAll()
        super.tearDown()
    }

    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "GameWorldTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempRoots.append(url)
        return url
    }

    private func write(_ text: String, relativePath: String, in root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeFixtures(in root: URL) throws {
        try write(Self.zoneJSON, relativePath: "Resources/Zones/FabledRealms.json", in: root)
        try write(Self.environmentJSON, relativePath: "Resources/Zones/Environments/FabledRealms.json", in: root)
        try write(Self.npcJSON, relativePath: "Resources/Npcs.json", in: root)
        try write(Self.questJSON, relativePath: "Resources/Quests.json", in: root)
        try write(Self.collectionJSON, relativePath: "Resources/Collections.json", in: root)
        try write(Self.nodeTypesJSON, relativePath: "Resources/CollectionNodeTypes.json", in: root)
        try write(Self.poolsJSON, relativePath: "Resources/CollectionNodePools.json", in: root)
        try write(
            Self.spawnJSON,
            relativePath: "Resources/CollectionNodeSpawns/1/mushrooms.json",
            in: root
        )
        try write(Self.poiJSON, relativePath: "Resources/PointOfInterests.json", in: root)
    }

    private func makeSimulation(withSession: Bool = false) throws -> (WorldSimulation, LocalSession?, URL) {
        let root = try makeRoot()
        try writeFixtures(in: root)

        var session: LocalSession?
        var character: LocalCharacter?
        if withSession {
            let localSession = try LocalSession(directory: root.appendingPathComponent("session", isDirectory: true))
            _ = try localSession.createAccount(username: "local", password: "offline-pass-123")
            _ = try localSession.login(username: "local", password: "offline-pass-123")
            let created = try localSession.createCharacter(named: "Tester")
            try localSession.selectCharacter(id: created.id)
            _ = try localSession.enterWorld()
            session = localSession
            character = localSession.selectedCharacter
        } else {
            var configuration = LocalHostConfiguration()
            configuration.characterName = "Tester"
            character = LocalCharacter.makeDefault(id: 1, name: "Tester", configuration: configuration)
        }

        guard let character else {
            throw XCTestError(.failureWhileWaiting)
        }
        let simulation = try WorldSimulation(
            rootURL: root,
            zoneName: "FabledRealms",
            character: character,
            session: session
        )
        return (simulation, session, root)
    }

    func testLoadingBuildsExactCollectionSpawnAndInferredNPC() throws {
        let (simulation, _, _) = try makeSimulation()
        let snapshot = simulation.snapshot

        XCTAssertEqual(snapshot.zoneID, 1)
        XCTAssertEqual(snapshot.zoneName, "FabledRealms")
        XCTAssertEqual(snapshot.playerName, "Tester")
        XCTAssertEqual(snapshot.nearbyPOIs.map(\.id), [3])

        XCTAssertEqual(snapshot.collectionNodes.count, 1)
        let node = try XCTUnwrap(snapshot.collectionNodes.first)
        XCTAssertEqual(node.id, 946)
        XCTAssertEqual(node.poolKey, "mushrooms")
        XCTAssertEqual(node.nodeTypeKey, "mushrooms")
        XCTAssertEqual(node.collectionID, 10)
        XCTAssertEqual(node.collectionEntryID, 41)
        XCTAssertTrue(node.available)
        XCTAssertEqual(node.position.x, -1904, accuracy: 0.000_001)
        XCTAssertEqual(node.position.y, 0.45, accuracy: 0.000_001) // PlacementYOffset -0.05
        XCTAssertEqual(node.position.z, 412, accuracy: 0.000_001)

        let npc = try XCTUnwrap(snapshot.visibleEntities.first { $0.kind == .npc })
        XCTAssertEqual(npc.definitionID, 2049)
        XCTAssertEqual(npc.name, "Greeter")
        XCTAssertEqual(npc.modelFileName, "greeter.model")
        XCTAssertTrue(npc.isInferredPosition)
        XCTAssertTrue(npc.positionSource.contains("inferred from area definition 4224"))
        XCTAssertTrue(simulation.isWalkable(npc.position))

        let collectionEntity = try XCTUnwrap(snapshot.visibleEntities.first { $0.kind == .collection })
        XCTAssertFalse(collectionEntity.isInferredPosition)
        XCTAssertTrue(collectionEntity.positionSource.contains("exact spawn"))
    }

    func testMovementBlocksOutOfBoundsAndStepsWithinTile() throws {
        let (simulation, _, _) = try makeSimulation()
        let start = simulation.snapshot.player

        let blockedTile = ZoneVector(x: -1888, y: Double(start.y), z: 480, w: 0)
        XCTAssertFalse(simulation.isWalkable(blockedTile))
        XCTAssertFalse(simulation.movePlayer(to: blockedTile))
        XCTAssertEqual(simulation.snapshot.player, start)

        let outsideGrid = ZoneVector(x: 10_000, y: Double(start.y), z: 10_000, w: 0)
        XCTAssertFalse(simulation.movePlayer(to: outsideGrid))

        let destination = ZoneVector(x: -1890, y: Double(start.y), z: 414, w: 0)
        XCTAssertTrue(simulation.isWalkable(destination))
        XCTAssertTrue(simulation.stepPlayer(toward: destination, deltaTime: 0.1))
        let moved = simulation.snapshot.player
        XCTAssertGreaterThan(moved.x, start.x)
        XCTAssertGreaterThan(moved.z, start.z)
        XCTAssertTrue(simulation.isWalkable(ZoneVector(
            x: Double(moved.x), y: Double(moved.y), z: Double(moved.z), w: 0
        )))
    }

    func testFixedStepTicksAreDeterministic() throws {
        let (first, _, _) = try makeSimulation()
        let (second, _, _) = try makeSimulation()

        first.update(deltaTime: 0.05)
        first.update(deltaTime: 0.05)
        second.update(deltaTime: 0.1)

        XCTAssertEqual(first.movementTicks, 1)
        XCTAssertEqual(second.movementTicks, 1)
        XCTAssertEqual(first.secondTicks, 0)
        XCTAssertEqual(second.secondTicks, 0)
        XCTAssertEqual(first.snapshot, second.snapshot)

        first.update(deltaTime: 2.0)
        second.update(deltaTime: 2.0)

        XCTAssertEqual(first.movementTicks, 11)
        XCTAssertEqual(second.movementTicks, 11)
        XCTAssertEqual(first.secondTicks, 1)
        XCTAssertEqual(second.secondTicks, 1)
        XCTAssertEqual(first.snapshot, second.snapshot)
    }

    func testCollectionInteractionRequiresRangeAdvancesQuestAndRespawns() throws {
        let (simulation, session, root) = try makeSimulation(withSession: true)
        XCTAssertNotNil(session)

        let initial = try XCTUnwrap(simulation.snapshot.quests.first)
        if let initialRow = initial.progress.goalProgress.first(where: { $0.targetID == 946 }) {
            XCTAssertEqual(initialRow.count, 0)
        }

        let away = ZoneVector(x: -1860, y: -39.7098, z: 416, w: 0)
        XCTAssertTrue(simulation.isWalkable(away))
        XCTAssertTrue(simulation.movePlayer(to: away))
        XCTAssertFalse(simulation.interactWithCollectionNode(id: 946))

        XCTAssertTrue(simulation.movePlayer(to: ZoneVector(x: -1904, y: -39.7098, z: 412, w: 0)))
        XCTAssertTrue(simulation.interactWithCollectionNode(id: 946))
        XCTAssertFalse(simulation.interactWithCollectionNode(id: 946))

        let afterCollect = simulation.snapshot
        let depletedNode = try XCTUnwrap(afterCollect.collectionNodes.first)
        XCTAssertFalse(depletedNode.available)
        XCTAssertEqual(depletedNode.collectedCount, 1)
        XCTAssertEqual(depletedNode.respawnTicksRemaining, 50)

        let quest = try XCTUnwrap(afterCollect.quests.first)
        XCTAssertEqual(quest.progress.questID, 2563)
        XCTAssertTrue(quest.progress.completed)
        XCTAssertEqual(quest.progress.goalProgress.first(where: { $0.targetID == 946 })?.count, 1)

        let reopened = try LocalSession(directory: root.appendingPathComponent("session", isDirectory: true))
        _ = try reopened.login(username: "local", password: "offline-pass-123")
        let persisted = try XCTUnwrap(reopened.selectedCharacter?.quests.first { $0.questID == 2563 })
        XCTAssertTrue(persisted.completed)

        for _ in 0..<10 {
            simulation.update(deltaTime: 0.5)
        }
        let respawned = try XCTUnwrap(simulation.snapshot.collectionNodes.first)
        XCTAssertTrue(respawned.available)
        XCTAssertEqual(respawned.respawnTicksRemaining, 0)
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
      "AreaDefinitions": [
        {
          "Id": 4224,
          "NameId": 1,
          "AreaId": 0,
          "ChatAreaNameId": 0,
          "EnvironmentIds": [10]
        }
      ]
    }
    """

    private static let environmentJSON = """
    {
      "Environments": { "-1": "OutOfBounds", "10": "Blackspore" },
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

    private static let npcJSON = """
    [
      {
        "Id": 2049,
        "NameId": 1,
        "Name": "Greeter",
        "ModelId": 249,
        "ModelFileName": "greeter.model",
        "AreaDefinitionId": 4224,
        "VerticalOffset": 0,
        "IsPlacedObject": true
      }
    ]
    """

    private static let questJSON = """
    [
      {
        "QuestId": 2563,
        "Name": "Gather Test",
        "TitleId": 1,
        "DescriptionId": 2,
        "GiverNpcId": 2049,
        "TargetNpcId": 2049,
        "Goals": [
          {
            "Type": 2,
            "NameId": 94359,
            "DescriptionId": 2,
            "CollectNodeType": "mushrooms",
            "RequiredCount": 1,
            "InteractRange": 12
          }
        ]
      }
    ]
    """

    private static let collectionJSON = """
    [
      {
        "Id": 10,
        "NameId": 17054,
        "Entries": [{ "Id": 41, "NameId": 17056, "ItemDefinitionId": 11082 }]
      }
    ]
    """

    private static let nodeTypesJSON = """
    [
      {
        "Key": "mushrooms",
        "Name": "Mushrooms",
        "ModelId": 249,
        "Scale": 1,
        "InteractRange": 12,
        "PlacementYOffset": -0.05,
        "CollectionId": 10,
        "CollectionEntryId": 41
      }
    ]
    """

    private static let poolsJSON = """
    [
      {
        "Key": "mushrooms",
        "ZoneDefinitionId": 1,
        "NodeType": "mushrooms",
        "MaxActiveNodes": 1,
        "RespawnSeconds": 5,
        "DropTable": [{ "ItemDefinitionId": 11082, "Weight": 100 }]
      }
    ]
    """

    private static let spawnJSON = """
    [
      { "Id": 946, "Position": [-1904, 0.5, 412], "Heading": 0 }
    ]
    """

    private static let poiJSON = """
    [
      {
        "Id": 3,
        "Comment": "Test Camp",
        "Position": [-1904, 0, 412],
        "SpawnPosition": [-1904, 0, 412],
        "AtlasName": "camp"
      }
    ]
    """
}
