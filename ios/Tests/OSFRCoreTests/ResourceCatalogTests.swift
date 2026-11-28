import Foundation
import XCTest
@testable import OSFRCore

final class ResourceCatalogTests: XCTestCase {
    private var tempRoots: [URL] = []

    override func tearDown() {
        for root in tempRoots {
            try? FileManager.default.removeItem(at: root)
        }
        tempRoots.removeAll()
        super.tearDown()
    }

    private func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ResourceCatalogTests-\(UUID().uuidString)", isDirectory: true)
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

    func testLoadsRealSchemaShapes() throws {
        let root = try makeRoot()
        try write(Self.npcsJSON, relativePath: "Npcs.json", in: root)
        try write(Self.questsJSON, relativePath: "Quests.json", in: root)
        try write(Self.itemsJSON, relativePath: "ClientItemDefinitions.json", in: root)
        try write(Self.coinStoreJSON, relativePath: "CoinStoreItems.json", in: root)
        try write(Self.collectionCoinsJSON, relativePath: "CollectionCoins.json", in: root)
        try write(Self.zoneJSON, relativePath: "Zones/FabledRealms.json", in: root)
        try write(Self.environmentJSON, relativePath: "Zones/Environments/FabledRealms.json", in: root)
        try write(Self.hairMappings, relativePath: "CharacterCreate/HairMappings.txt", in: root)

        let catalog = try ResourceCatalog(rootURL: root)

        XCTAssertEqual(catalog.loadedFiles.count, 8)
        XCTAssertFalse(catalog.missingFiles.contains("Npcs.json"))
        XCTAssertFalse(catalog.missingFiles.contains("Zones"))
        XCTAssertFalse(catalog.missingFiles.contains("Zones/Environments"))

        let npc = try XCTUnwrap(catalog.npc(id: 2045))
        XCTAssertEqual(npc.name, "Therin")
        XCTAssertEqual(npc.modelFileName, "dwarf_m_therin.adr")
        XCTAssertEqual(npc.scripts, ["welcomer"])
        XCTAssertEqual(npc.interactions.first?.type, 33)
        XCTAssertEqual(npc.merchantItems.first?.itemDefinitionID, 13231)
        XCTAssertEqual(npc.notifications.first?.notificationType, 1)

        let quest = try XCTUnwrap(catalog.quest(id: 2563))
        XCTAssertEqual(quest.rewardCoins, 5)
        XCTAssertEqual(quest.goals.count, 1)
        switch quest.goals[0] {
        case .talkToNPC(let goal):
            XCTAssertEqual(goal.targets.first?.npcID, 2049)
            XCTAssertEqual(goal.common.dialogueID, 94388)
        case .reachLocation, .collect:
            XCTFail("Expected a talk-to-NPC goal")
        }

        let item = try XCTUnwrap(catalog.item(id: 1432))
        XCTAssertEqual(item.iconID, 3235)
        XCTAssertEqual(item.iconTintID, 255)
        XCTAssertEqual(item.stats[27]?.value, 1_119_485_952)
        XCTAssertEqual(item.abilities.first?.id, 4936)

        XCTAssertEqual(catalog.coinStoreItem(id: 2)?.categoryID, 101)
        XCTAssertEqual(catalog.collectionCoins.first?.entryID, 1937)

        let zone = try XCTUnwrap(catalog.zone(id: 1))
        XCTAssertEqual(zone.kind, .world)
        XCTAssertEqual(zone.spawnPosition.z, 412.6024)
        XCTAssertEqual(zone.areaDefinitions.first?.tiles.first?.longitude, -1)
        XCTAssertEqual(zone.seasonalClientAreas.first?.areaIDs, [3992, 3993])

        let grid = try XCTUnwrap(catalog.zoneEnvironments["FabledRealms"])
        XCTAssertEqual(grid.environmentNames[10], "Blackspore")
        XCTAssertEqual(grid.environmentID(longitude: 0, latitude: 1), 10)
        XCTAssertEqual(grid.environmentID(longitude: 0, latitude: 2), -1)

        XCTAssertEqual(
            catalog.characterCreate[.hair][1],
            "<race>_m_hair_afro_<hairtype>.adr"
        )
    }

    func testZoneNameMatchesServerDisplayNames() throws {
        let root = try makeRoot()
        try write(Self.zoneJSON, relativePath: "Zones/FabledRealms.json", in: root)
        try write(Self.environmentJSON, relativePath: "Zones/Environments/FabledRealms.json", in: root)
        let catalog = try ResourceCatalog(rootURL: root)

        XCTAssertEqual(catalog.zoneName(matching: "Fabled Realms"), "FabledRealms")
        XCTAssertEqual(catalog.zoneName(matching: "fabled_realms"), "FabledRealms")
        XCTAssertEqual(catalog.zoneName(matching: "FabledRealms"), "FabledRealms")
        XCTAssertNil(catalog.zoneName(matching: "Unknown Zone"))
    }

    func testMissingFilesAreOptional() throws {
        let root = try makeRoot()
        let catalog = try ResourceCatalog(rootURL: root)

        XCTAssertTrue(catalog.loadedFiles.isEmpty)
        XCTAssertTrue(catalog.npcs.isEmpty)
        XCTAssertTrue(catalog.quests.isEmpty)
        XCTAssertTrue(catalog.itemDefinitions.isEmpty)
        XCTAssertTrue(catalog.zones.isEmpty)
        XCTAssertTrue(catalog.characterCreate[.hair].isEmpty)
        XCTAssertTrue(catalog.missingFiles.contains("Npcs.json"))
        XCTAssertTrue(catalog.missingFiles.contains("Zones"))
        XCTAssertTrue(catalog.missingFiles.contains("CharacterCreate/HairMappings.txt"))
    }

    func testMalformedJSONThrows() throws {
        let root = try makeRoot()
        try write("""
        [
          { "Id": 2045, "NameId": 185, "ModelFileName":
        ]
        """, relativePath: "Npcs.json", in: root)

        XCTAssertThrowsError(try ResourceCatalog(rootURL: root)) { error in
            guard case ResourceCatalogError.malformedJSON(let file, let detail) = error else {
                return XCTFail("Expected malformedJSON, got \(error)")
            }
            XCTAssertEqual(file, "Npcs.json")
            XCTAssertFalse(detail.isEmpty)
        }
    }

    func testDuplicateIDsAreRejected() throws {
        let root = try makeRoot()
        try write("""
        [
          { "Id": 2045, "ModelFileName": "a.adr" },
          { "Id": 2045, "ModelFileName": "b.adr" }
        ]
        """, relativePath: "Npcs.json", in: root)

        XCTAssertThrowsError(try ResourceCatalog(rootURL: root)) { error in
            guard case ResourceCatalogError.duplicateID(let file, let id) = error else {
                return XCTFail("Expected duplicateID, got \(error)")
            }
            XCTAssertEqual(file, "Npcs.json")
            XCTAssertEqual(id, 2045)
        }
    }

    func testContainedURLUsesSafePath() throws {
        let root = try makeRoot()
        let catalog = try ResourceCatalog(rootURL: root)

        XCTAssertEqual(
            try catalog.url(forRelativePath: "Npcs.json").lastPathComponent,
            "Npcs.json"
        )
        for unsafe in ["../Npcs.json", "CharacterCreate/../../Npcs.json", "a/b/../c.json", "\\escape"] {
            XCTAssertThrowsError(try catalog.url(forRelativePath: unsafe)) { error in
                guard case ResourceCatalogError.unsafePath = error else {
                    return XCTFail("Expected unsafePath for \(unsafe), got \(error)")
                }
            }
        }
        XCTAssertThrowsError(try ResourceCatalog(rootURL: root.appendingPathComponent("Npcs.json")))
    }

    func testStartingZoneLoadPlanUsesVerifiedHeaderAndSelectorOrder() {
        let manifest = """
        #LOAD_ORDER^ASSET_LIST^CALLBACK^IS_BACKGROUND_LOAD^
        100^FilteredCommonAssets.txt^^1^
        1^UiAssets.txt^^0^
        20^MinigameAssets.txt^^1^
        10^HighRoadAssets.txt^HUD.StartingZoneLoaded^0^
        broken^row^only^three^
        """

        let plan = StartingZoneLoadPlan.parse(manifest)
        XCTAssertEqual(plan.map(\.assetList), [
            "UiAssets.txt",
            "HighRoadAssets.txt",
            "MinigameAssets.txt",
            "FilteredCommonAssets.txt"
        ])
        XCTAssertEqual(plan.map(\.loadOrder), [1, 10, 20, 100])
        XCTAssertEqual(StartingZoneLoadPlan.foregroundRows(in: plan).map(\.assetList), [
            "UiAssets.txt",
            "HighRoadAssets.txt"
        ])
        XCTAssertEqual(StartingZoneLoadPlan.backgroundRows(in: plan).map(\.assetList), [
            "MinigameAssets.txt",
            "FilteredCommonAssets.txt"
        ])
        XCTAssertEqual(plan[1].callback, .hudStartingZoneLoaded)
        XCTAssertEqual(plan[1].callback?.scriptPath, "HUD.StartingZoneLoaded")
        XCTAssertNil(plan[0].callback)
        XCTAssertFalse(plan[0].isBackgroundLoad)
        XCTAssertTrue(plan[2].isBackgroundLoad)
    }

    func testStartingZoneLoadPlanSkipsUnusableRowsWithoutInventingValues() {
        let manifest = """
        # comment
        2^Good.txt^Custom.Path^0^
        nope^BadOrder.txt^^0^
        3^^^0^
        4^MissingFlag.txt^^
        5^BadFlag.txt^^2^
        6^Tie.txt^^0^
        1^EarlierTie.txt^^0^
        """

        let plan = StartingZoneLoadPlan.parse(manifest)
        XCTAssertEqual(plan.map(\.assetList), ["EarlierTie.txt", "Good.txt", "Tie.txt"])
        XCTAssertEqual(plan[1].callback, .other("Custom.Path"))
        XCTAssertEqual(plan[1].callback?.scriptPath, "Custom.Path")
    }

    private static let npcsJSON = """
    [
      {
        "Id": 2045,
        "NameId": 185,
        "Name": "Therin",
        "ModelId": 46,
        "ModelFileName": "dwarf_m_therin.adr",
        "Scale": 1.25,
        "Disposition": 1,
        "Animation": 1,
        "VerticalOffset": 0.5,
        "Scripts": ["welcomer"],
        "InteractionList": {
          "Unknown": true,
          "Interactions": [
            { "Id": 9244, "IconId": 0, "ButtonText": 0, "Type": 33,
              "Param1": 0, "Param2": 0, "TooltipId": 0 }
          ],
          "Name": "",
          "Unknown2": true
        },
        "MerchantList": {
          "Unknown": 468,
          "Unknown4": 90184,
          "Entries": [
            { "ItemDefinitionId": 13231, "Unknown8": 1000, "IconId": 3906,
              "TintId": 0, "NameId": 995, "DescriptionId": 996,
              "PurchasableQty": -1, "MembersOnly": false,
              "AvailableTintGroupId": 0, "CanBuy": true }
          ]
        },
        "Notifications": [
          { "IsCompact": false, "NotificationType": 1, "IconId": 1,
            "IconState": 12, "Unknown": 0, "NameId": 7581, "ReferenceId": 36,
            "Unknown3": false, "Unknown2": 0, "Enabled": true }
        ]
      }
    ]
    """

    private static let questsJSON = """
    [
      {
        "Name": "Introduce Yourself",
        "QuestId": 2563,
        "TitleId": 94247,
        "DescriptionId": 94360,
        "GiverDialogueId": 94246,
        "ObjectiveDescriptionId": 94248,
        "IconId": 43278,
        "GiverNpcId": 2045,
        "TargetNpcId": 2049,
        "RewardCoins": 5,
        "RewardExperience": 60,
        "RewardItems": [],
        "NextQuestId": 1801,
        "NotificationAvailable": 2,
        "NotificationActive": 6,
        "ExcludesQuestIds": [2564],
        "Goals": [
          { "Type": 0, "NameId": 94359, "DescriptionId": 94248,
            "DialogueId": 94388, "Targets": [{ "NpcId": 2049 }] }
        ]
      }
    ]
    """

    private static let itemsJSON = """
    [
      {
        "Comment": "Elitist's Beater",
        "Id": 1432,
        "Type": 1,
        "NameId": 4255,
        "DescriptionId": 408288,
        "Icon": { "Id": 3235, "TintId": 255 },
        "Cost": 20,
        "Class": 38,
        "MaxStackSize": -1,
        "NoTrade": true,
        "TintAlias": "dyetint",
        "TextureAlias": "cook-steel-L2",
        "MemberDiscount": 10,
        "Slot": 7,
        "ModelName": "tool_ar_ag_weapon_eggbeater.adr",
        "CategoryId": 107,
        "PowerRating": 3,
        "ResellValue": 2,
        "Stats": {
          "27": { "Id": 27, "Type": 0, "Value": 1119485952, "Unknown": false }
        },
        "Abilities": [{ "Slot": 0, "Id": 4936, "Unknown": 0, "IconId": 14105 }]
      }
    ]
    """

    private static let coinStoreJSON = """
    [
      { "Id": 2, "CategoryId": 101, "TintGroupId": 1 },
      { "Id": 8, "CategoryId": 7 }
    ]
    """

    private static let collectionCoinsJSON = """
    [
      { "NpcDefinitionId": 1946, "CollectionId": 267, "EntryId": 1937 }
    ]
    """

    private static let zoneJSON = """
    {
      "$type": "World",
      "Id": 1,
      "Name": "FabledRealms",
      "Type": "World",
      "TileSize": 64,
      "StartLatitude": -48,
      "StartLongitude": -32,
      "EndLatitude": 80,
      "EndLongitude": 96,
      "SpawnPosition": [-1904.883, -39.7098, 412.6024],
      "SpawnRotation": [0.5531712, 0.8330676],
      "Scripts": ["FabledRealms", "BruceConcert"],
      "EnabledClientAreaIds": [4173],
      "SeasonalClientAreas": [
        { "Name": "Halloween", "StartMonth": 9, "StartDay": 20,
          "EndMonth": 11, "EndDay": 11, "AreaIds": [3992, 3993] }
      ],
      "AreaDefinitions": [
        { "Comment": "Blackspore", "Id": 2, "NameId": 3500, "AreaId": 0,
          "ChatAreaNameId": 3500, "EnvironmentIds": [10, 70],
          "Tiles": [[-1, -23], [-1, -22]] }
      ]
    }
    """

    private static let environmentJSON = """
    {
      "Environments": { "-1": "OutOfBounds", "10": "Blackspore" },
      "StartLongitude": 0,
      "StartLatitude": 0,
      "Rows": [[-1, 10], [10, -1]]
    }
    """

    private static let hairMappings = """
    #ID^FILENAME^
    0^<race>_m_hair_eyebrows_bald.adr^
    1^<race>_m_hair_afro_<hairtype>.adr^
    """
}
