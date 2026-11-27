import Foundation

// MARK: - Errors

enum ResourceCatalogError: LocalizedError, Equatable {
    case invalidRoot(String)
    case unsafePath(String)
    case unreadableFile(String)
    case malformedJSON(String, detail: String)
    case invalidData(String, detail: String)
    case duplicateID(String, Int)
    case unsupportedZoneType(String)

    var errorDescription: String? {
        switch self {
        case .invalidRoot(let path): return "Not a Sanctuary resource directory: \(path)"
        case .unsafePath(let path): return "Unsafe resource path: \(path)"
        case .unreadableFile(let path): return "Could not read resource file: \(path)"
        case .malformedJSON(let file, let detail): return "Malformed JSON in \(file): \(detail)"
        case .invalidData(let file, let detail): return "Invalid data in \(file): \(detail)"
        case .duplicateID(let file, let id): return "Duplicate id \(id) in \(file)"
        case .unsupportedZoneType(let type): return "Unsupported zone type: \(type)"
        }
    }
}

// MARK: - Shared vector decoding

/// Sanctuary writes vectors as JSON arrays. The server's converters accept two
/// components (X/Z), three (X/Y/Z), or four (X/Y/Z/W), so keep all four here.
struct ZoneVector: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let z: Double
    let w: Double

    static let zero = ZoneVector(x: 0, y: 0, z: 0, w: 0)

    init(x: Double, y: Double, z: Double, w: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.singleValueContainer().decode([Double].self)
        switch values.count {
        case 2:
            self.init(x: values[0], y: 0, z: values[1], w: 0)
        case 3:
            self.init(x: values[0], y: values[1], z: values[2], w: 0)
        case 4:
            self.init(x: values[0], y: values[1], z: values[2], w: values[3])
        default:
            throw ResourceCatalogError.invalidData("vector", detail: "Expected 2–4 components, got \(values.count)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(w == 0 ? [x, y, z] : [x, y, z, w])
    }
}

private extension KeyedDecodingContainer {
    func osfrInt(_ key: Key) throws -> Int {
        try decodeIfPresent(Int.self, forKey: key) ?? 0
    }

    func osfrDouble(_ key: Key) throws -> Double {
        try decodeIfPresent(Double.self, forKey: key) ?? 0
    }

    func osfrBool(_ key: Key) throws -> Bool {
        try decodeIfPresent(Bool.self, forKey: key) ?? false
    }

    func osfrString(_ key: Key) throws -> String {
        try decodeIfPresent(String.self, forKey: key) ?? ""
    }

    func osfrInts(_ key: Key) throws -> [Int] {
        try decodeIfPresent([Int].self, forKey: key) ?? []
    }

    func osfrStrings(_ key: Key) throws -> [String] {
        try decodeIfPresent([String].self, forKey: key) ?? []
    }
}

// MARK: - Zones

enum ZoneKind: String, Codable, CaseIterable {
    case world = "World"
    case dungeon = "Dungeon"
    case housing = "Housing"
}

struct ZoneTile: Codable, Equatable {
    let longitude: Int
    let latitude: Int

    init(longitude: Int, latitude: Int) {
        self.longitude = longitude
        self.latitude = latitude
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.singleValueContainer().decode([Int].self)
        guard values.count == 2 else {
            throw ResourceCatalogError.invalidData("zone tile", detail: "Expected [longitude, latitude]")
        }
        self.init(longitude: values[0], latitude: values[1])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode([longitude, latitude])
    }
}

struct ZoneAreaDefinition: Codable, Equatable {
    let id: Int
    let nameID: Int
    let areaID: Int
    let chatAreaNameID: Int
    let environmentIDs: [Int]
    let environmentMinX: Double?
    let environmentMaxX: Double?
    let tiles: [ZoneTile]

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case nameID = "NameId"
        case areaID = "AreaId"
        case chatAreaNameID = "ChatAreaNameId"
        case environmentIDs = "EnvironmentIds"
        case environmentMinX = "EnvironmentMinX"
        case environmentMaxX = "EnvironmentMaxX"
        case tiles = "Tiles"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.osfrInt(.id)
        nameID = try c.osfrInt(.nameID)
        areaID = try c.osfrInt(.areaID)
        chatAreaNameID = try c.osfrInt(.chatAreaNameID)
        environmentIDs = try c.osfrInts(.environmentIDs)
        environmentMinX = try c.decodeIfPresent(Double.self, forKey: .environmentMinX)
        environmentMaxX = try c.decodeIfPresent(Double.self, forKey: .environmentMaxX)
        tiles = try c.decodeIfPresent([ZoneTile].self, forKey: .tiles) ?? []
    }
}

struct SeasonalClientArea: Codable, Equatable {
    let name: String
    let startMonth: Int
    let startDay: Int
    let endMonth: Int
    let endDay: Int
    let areaIDs: [Int]

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case startMonth = "StartMonth"
        case startDay = "StartDay"
        case endMonth = "EndMonth"
        case endDay = "EndDay"
        case areaIDs = "AreaIds"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.osfrString(.name)
        startMonth = try c.osfrInt(.startMonth)
        startDay = try c.osfrInt(.startDay)
        endMonth = try c.osfrInt(.endMonth)
        endDay = try c.osfrInt(.endDay)
        areaIDs = try c.osfrInts(.areaIDs)
    }
}

struct ZoneDefinition: Codable, Equatable {
    let kind: ZoneKind
    let id: Int
    let name: String
    let tileSize: Double
    let startLongitude: Int
    let endLongitude: Int
    let startLatitude: Int
    let endLatitude: Int
    let spawnPosition: ZoneVector
    let spawnRotation: ZoneVector
    let scripts: [String]
    let enabledClientAreaIDs: [Int]
    let seasonalClientAreas: [SeasonalClientArea]
    let areaDefinitions: [ZoneAreaDefinition]

    enum CodingKeys: String, CodingKey {
        case kind = "$type"
        case id = "Id"
        case name = "Name"
        case tileSize = "TileSize"
        case startLongitude = "StartLongitude"
        case endLongitude = "EndLongitude"
        case startLatitude = "StartLatitude"
        case endLatitude = "EndLatitude"
        case spawnPosition = "SpawnPosition"
        case spawnRotation = "SpawnRotation"
        case scripts = "Scripts"
        case enabledClientAreaIDs = "EnabledClientAreaIds"
        case seasonalClientAreas = "SeasonalClientAreas"
        case areaDefinitions = "AreaDefinitions"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = try c.osfrString(.kind)
        guard let kind = ZoneKind(rawValue: rawKind) else {
            throw ResourceCatalogError.unsupportedZoneType(rawKind)
        }
        self.kind = kind
        id = try c.osfrInt(.id)
        name = try c.osfrString(.name)
        tileSize = try c.osfrDouble(.tileSize)
        startLongitude = try c.osfrInt(.startLongitude)
        endLongitude = try c.osfrInt(.endLongitude)
        startLatitude = try c.osfrInt(.startLatitude)
        endLatitude = try c.osfrInt(.endLatitude)
        spawnPosition = try c.decodeIfPresent(ZoneVector.self, forKey: .spawnPosition) ?? .zero
        spawnRotation = try c.decodeIfPresent(ZoneVector.self, forKey: .spawnRotation) ?? .zero
        scripts = try c.osfrStrings(.scripts)
        enabledClientAreaIDs = try c.osfrInts(.enabledClientAreaIDs)
        seasonalClientAreas = try c.decodeIfPresent([SeasonalClientArea].self, forKey: .seasonalClientAreas) ?? []
        areaDefinitions = try c.decodeIfPresent([ZoneAreaDefinition].self, forKey: .areaDefinitions) ?? []
    }
}

/// `Zones/Environments/<zone>.json`: a start corner plus rows of environment ids.
struct ZoneEnvironmentGrid: Codable, Equatable {
    let environmentNames: [Int: String]
    let startLongitude: Int
    let startLatitude: Int
    let rows: [[Int]]

    enum CodingKeys: String, CodingKey {
        case environmentNames = "Environments"
        case startLongitude = "StartLongitude"
        case startLatitude = "StartLatitude"
        case rows = "Rows"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawNames = try c.decodeIfPresent([String: String].self, forKey: .environmentNames) ?? [:]
        var names: [Int: String] = [:]
        for (key, value) in rawNames {
            guard let environmentID = Int(key), !value.isEmpty else {
                throw ResourceCatalogError.invalidData("zone environment", detail: "Invalid environment key \(key)")
            }
            names[environmentID] = value
        }
        environmentNames = names
        startLongitude = try c.osfrInt(.startLongitude)
        startLatitude = try c.osfrInt(.startLatitude)
        rows = try c.decodeIfPresent([[Int]].self, forKey: .rows) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let rawNames = Dictionary(uniqueKeysWithValues: environmentNames.map { (String($0.key), $0.value) })
        try c.encode(rawNames, forKey: .environmentNames)
        try c.encode(startLongitude, forKey: .startLongitude)
        try c.encode(startLatitude, forKey: .startLatitude)
        try c.encode(rows, forKey: .rows)
    }

    /// Mirrors Sanctuary's `GetEnvironmentId`; -1 means outside the grid.
    func environmentID(longitude: Int, latitude: Int) -> Int {
        let column = longitude - startLongitude
        guard column >= 0, column < rows.count else { return -1 }
        let row = rows[column]
        let offset = latitude - startLatitude
        guard offset >= 0, offset < row.count else { return -1 }
        return row[offset]
    }
}

// MARK: - NPCs

struct NpcInteraction: Codable, Equatable {
    let id: Int
    let iconID: Int
    let buttonTextID: Int
    let type: Int
    let param1: Int
    let param2: Int
    let tooltipID: Int

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case iconID = "IconId"
        case buttonTextID = "ButtonText"
        case type = "Type"
        case param1 = "Param1"
        case param2 = "Param2"
        case tooltipID = "TooltipId"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.osfrInt(.id)
        iconID = try c.osfrInt(.iconID)
        buttonTextID = try c.osfrInt(.buttonTextID)
        type = try c.osfrInt(.type)
        param1 = try c.osfrInt(.param1)
        param2 = try c.osfrInt(.param2)
        tooltipID = try c.osfrInt(.tooltipID)
    }
}

struct NpcMerchantEntry: Codable, Equatable {
    let itemDefinitionID: Int
    let quantity: Int
    let iconID: Int
    let tintID: Int
    let nameID: Int
    let descriptionID: Int
    let membersOnly: Bool
    let canBuy: Bool

    enum CodingKeys: String, CodingKey {
        case itemDefinitionID = "ItemDefinitionId"
        case quantity = "PurchasableQty"
        case iconID = "IconId"
        case tintID = "TintId"
        case nameID = "NameId"
        case descriptionID = "DescriptionId"
        case membersOnly = "MembersOnly"
        case canBuy = "CanBuy"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        itemDefinitionID = try c.osfrInt(.itemDefinitionID)
        quantity = try c.osfrInt(.quantity)
        iconID = try c.osfrInt(.iconID)
        tintID = try c.osfrInt(.tintID)
        nameID = try c.osfrInt(.nameID)
        descriptionID = try c.osfrInt(.descriptionID)
        membersOnly = try c.osfrBool(.membersOnly)
        canBuy = try c.osfrBool(.canBuy)
    }
}

struct NpcNotification: Codable, Equatable {
    let notificationType: Int
    let iconID: Int
    let nameID: Int

    enum CodingKeys: String, CodingKey {
        case notificationType = "NotificationType"
        case iconID = "IconId"
        case nameID = "NameId"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notificationType = try c.osfrInt(.notificationType)
        iconID = try c.osfrInt(.iconID)
        nameID = try c.osfrInt(.nameID)
    }
}

private struct NpcInteractionList: Codable {
    let interactions: [NpcInteraction]

    enum CodingKeys: String, CodingKey {
        case interactions = "Interactions"
    }
}

private struct NpcMerchantList: Codable {
    let entries: [NpcMerchantEntry]

    enum CodingKeys: String, CodingKey {
        case entries = "Entries"
    }
}

struct NpcDefinition: Codable, Equatable {
    let id: Int
    let nameID: Int
    let subTextNameID: Int
    let name: String
    let modelID: Int
    let modelFileName: String
    let terrainObjectID: Int
    let areaDefinitionID: Int
    let tintID: Int
    let scale: Double?
    let verticalOffset: Double
    let disposition: Int
    let animation: Int
    let compositeEffectID: Int
    let boomboxItemID: Int
    let isPlacedObject: Bool
    let replaceTerrainObject: Bool
    let hideNamePlate: Bool
    let opensAtlas: Bool
    let autoSelectSingleInteraction: Bool
    let hasCursor: Bool?
    let cursorID: Int
    let textureAlias: String
    let tintAlias: String
    let scripts: [String]
    let interactions: [NpcInteraction]
    let merchantItems: [NpcMerchantEntry]
    let notifications: [NpcNotification]

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case nameID = "NameId"
        case subTextNameID = "SubTextNameId"
        case name = "Name"
        case modelID = "ModelId"
        case modelFileName = "ModelFileName"
        case terrainObjectID = "TerrainObjectId"
        case areaDefinitionID = "AreaDefinitionId"
        case tintID = "TintId"
        case scale = "Scale"
        case verticalOffset = "VerticalOffset"
        case disposition = "Disposition"
        case animation = "Animation"
        case compositeEffectID = "CompositeEffectId"
        case boomboxItemID = "BoomboxItemId"
        case isPlacedObject = "IsPlacedObject"
        case replaceTerrainObject = "ReplaceTerrainObject"
        case hideNamePlate = "HideNamePlate"
        case opensAtlas = "OpensAtlas"
        case autoSelectSingleInteraction = "AutoSelectSingleInteraction"
        case hasCursor = "HasCursor"
        case cursorID = "CursorId"
        case textureAlias = "TextureAlias"
        case tintAlias = "TintAlias"
        case scripts = "Scripts"
        case interactionList = "InteractionList"
        case merchantList = "MerchantList"
        case notification = "Notification"
        case notifications = "Notifications"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.osfrInt(.id)
        nameID = try c.osfrInt(.nameID)
        subTextNameID = try c.osfrInt(.subTextNameID)
        name = try c.osfrString(.name)
        modelID = try c.osfrInt(.modelID)
        modelFileName = try c.osfrString(.modelFileName)
        terrainObjectID = try c.osfrInt(.terrainObjectID)
        areaDefinitionID = try c.osfrInt(.areaDefinitionID)
        tintID = try c.osfrInt(.tintID)
        scale = try c.decodeIfPresent(Double.self, forKey: .scale)
        verticalOffset = try c.osfrDouble(.verticalOffset)
        disposition = try c.decodeIfPresent(Int.self, forKey: .disposition) ?? 1
        animation = try c.decodeIfPresent(Int.self, forKey: .animation) ?? 1
        compositeEffectID = try c.osfrInt(.compositeEffectID)
        boomboxItemID = try c.osfrInt(.boomboxItemID)
        isPlacedObject = try c.osfrBool(.isPlacedObject)
        replaceTerrainObject = try c.osfrBool(.replaceTerrainObject)
        hideNamePlate = try c.osfrBool(.hideNamePlate)
        opensAtlas = try c.osfrBool(.opensAtlas)
        autoSelectSingleInteraction = try c.osfrBool(.autoSelectSingleInteraction)
        hasCursor = try c.decodeIfPresent(Bool.self, forKey: .hasCursor)
        cursorID = try c.osfrInt(.cursorID)
        textureAlias = try c.osfrString(.textureAlias)
        tintAlias = try c.osfrString(.tintAlias)
        scripts = try c.osfrStrings(.scripts)
        interactions = try c.decodeIfPresent(NpcInteractionList.self, forKey: .interactionList)?.interactions ?? []
        merchantItems = try c.decodeIfPresent(NpcMerchantList.self, forKey: .merchantList)?.entries ?? []
        let singleNotification = try c.decodeIfPresent(NpcNotification.self, forKey: .notification)
        let manyNotifications = try c.decodeIfPresent([NpcNotification].self, forKey: .notifications) ?? []
        notifications = [singleNotification].compactMap { $0 } + manyNotifications
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(nameID, forKey: .nameID)
        try c.encode(subTextNameID, forKey: .subTextNameID)
        try c.encode(name, forKey: .name)
        try c.encode(modelID, forKey: .modelID)
        try c.encode(modelFileName, forKey: .modelFileName)
        try c.encode(terrainObjectID, forKey: .terrainObjectID)
        try c.encode(areaDefinitionID, forKey: .areaDefinitionID)
        try c.encode(tintID, forKey: .tintID)
        try c.encodeIfPresent(scale, forKey: .scale)
        try c.encode(verticalOffset, forKey: .verticalOffset)
        try c.encode(disposition, forKey: .disposition)
        try c.encode(animation, forKey: .animation)
        try c.encode(compositeEffectID, forKey: .compositeEffectID)
        try c.encode(boomboxItemID, forKey: .boomboxItemID)
        try c.encode(isPlacedObject, forKey: .isPlacedObject)
        try c.encode(replaceTerrainObject, forKey: .replaceTerrainObject)
        try c.encode(hideNamePlate, forKey: .hideNamePlate)
        try c.encode(opensAtlas, forKey: .opensAtlas)
        try c.encode(autoSelectSingleInteraction, forKey: .autoSelectSingleInteraction)
        try c.encodeIfPresent(hasCursor, forKey: .hasCursor)
        try c.encode(cursorID, forKey: .cursorID)
        try c.encode(textureAlias, forKey: .textureAlias)
        try c.encode(tintAlias, forKey: .tintAlias)
        try c.encode(scripts, forKey: .scripts)
        try c.encode(NpcInteractionList(interactions: interactions), forKey: .interactionList)
        try c.encode(NpcMerchantList(entries: merchantItems), forKey: .merchantList)
        try c.encode(notifications, forKey: .notifications)
    }
}

// MARK: - Quests

enum QuestGoalType: Int, Decodable {
    case talkToNPC = 0
    case reachLocation = 1
    case collect = 2
}

struct QuestDialogueChoice: Codable, Equatable {
    let responseTextID: Int
    let retry: Bool
    let then: [QuestDialogueLine]

    enum CodingKeys: String, CodingKey {
        case responseTextID = "ResponseTextId"
        case retry = "Retry"
        case then = "Then"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        responseTextID = try c.osfrInt(.responseTextID)
        retry = try c.osfrBool(.retry)
        then = try c.decodeIfPresent([QuestDialogueLine].self, forKey: .then) ?? []
    }
}

struct QuestDialogueLine: Codable, Equatable {
    let textID: Int
    let responseTextID: Int
    let closable: Bool
    let choices: [QuestDialogueChoice]

    enum CodingKeys: String, CodingKey {
        case textID = "TextId"
        case responseTextID = "ResponseTextId"
        case closable = "Closable"
        case choices = "Choices"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        textID = try c.osfrInt(.textID)
        responseTextID = try c.osfrInt(.responseTextID)
        closable = try c.decodeIfPresent(Bool.self, forKey: .closable) ?? true
        choices = try c.decodeIfPresent([QuestDialogueChoice].self, forKey: .choices) ?? []
    }
}

struct QuestTalkTarget: Codable, Equatable {
    let npcID: Int
    let dialogueID: Int
    let responseID: Int

    enum CodingKeys: String, CodingKey {
        case npcID = "NpcId"
        case dialogueID = "DialogueId"
        case responseID = "ResponseId"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        npcID = try c.osfrInt(.npcID)
        dialogueID = try c.osfrInt(.dialogueID)
        responseID = try c.osfrInt(.responseID)
    }
}

struct QuestNpcEffect: Codable, Equatable {
    let npcID: Int
    let effectID: Int

    enum CodingKeys: String, CodingKey {
        case npcID = "NpcId"
        case effectID = "EffectId"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        npcID = try c.osfrInt(.npcID)
        effectID = try c.osfrInt(.effectID)
    }
}

/// Fields shared by all quest goals in Sanctuary's polymorphic `Goals` array.
struct QuestGoalCommon: Codable, Equatable {
    let nameID: Int
    let descriptionID: Int
    let dialogueID: Int
    let dialogue: [QuestDialogueLine]
    let cursorID: Int
    let interactRange: Int
    let requiredCount: Int
    let withPrevious: Bool
    let hideNpcIDsWhenDone: [Int]
    let hideEffectID: Int
    let hideDelayMs: Int
    let npcEffectsUntilDone: [QuestNpcEffect]

    enum CodingKeys: String, CodingKey {
        case nameID = "NameId"
        case descriptionID = "DescriptionId"
        case dialogueID = "DialogueId"
        case dialogue = "Dialogue"
        case cursorID = "CursorId"
        case interactRange = "InteractRange"
        case requiredCount = "RequiredCount"
        case withPrevious = "WithPrevious"
        case hideNpcIDsWhenDone = "HideNpcIdsWhenDone"
        case hideEffectID = "HideEffectId"
        case hideDelayMs = "HideDelayMs"
        case npcEffectsUntilDone = "NpcEffectsUntilDone"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nameID = try c.osfrInt(.nameID)
        descriptionID = try c.osfrInt(.descriptionID)
        dialogueID = try c.osfrInt(.dialogueID)
        dialogue = try c.decodeIfPresent([QuestDialogueLine].self, forKey: .dialogue) ?? []
        cursorID = try c.decodeIfPresent(Int.self, forKey: .cursorID) ?? 17
        interactRange = try c.decodeIfPresent(Int.self, forKey: .interactRange) ?? 12
        requiredCount = try c.osfrInt(.requiredCount)
        withPrevious = try c.osfrBool(.withPrevious)
        hideNpcIDsWhenDone = try c.osfrInts(.hideNpcIDsWhenDone)
        hideEffectID = try c.osfrInt(.hideEffectID)
        hideDelayMs = try c.osfrInt(.hideDelayMs)
        npcEffectsUntilDone = try c.decodeIfPresent([QuestNpcEffect].self, forKey: .npcEffectsUntilDone) ?? []
    }
}

struct QuestTalkGoal: Decodable, Equatable {
    let common: QuestGoalCommon
    let targets: [QuestTalkTarget]
    let completeAfterDialogue: Bool

    enum CodingKeys: String, CodingKey {
        case targets = "Targets"
        case completeAfterDialogue = "CompleteAfterDialogue"
    }

    init(from decoder: Decoder) throws {
        common = try QuestGoalCommon(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        targets = try c.decodeIfPresent([QuestTalkTarget].self, forKey: .targets) ?? []
        completeAfterDialogue = try c.osfrBool(.completeAfterDialogue)
    }
}

struct QuestReachGoal: Decodable, Equatable {
    let common: QuestGoalCommon
    let position: ZoneVector
    let radius: Double
    let zoneDefinitionID: Int

    enum CodingKeys: String, CodingKey {
        case position = "ReachPosition"
        case radius = "ReachRadius"
        case zoneDefinitionID = "ZoneDefinitionId"
    }

    init(from decoder: Decoder) throws {
        common = try QuestGoalCommon(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        position = try c.decodeIfPresent(ZoneVector.self, forKey: .position) ?? .zero
        radius = try c.decodeIfPresent(Double.self, forKey: .radius) ?? 12
        zoneDefinitionID = try c.decodeIfPresent(Int.self, forKey: .zoneDefinitionID) ?? 1
    }
}

struct QuestCollectGoal: Decodable, Equatable {
    let common: QuestGoalCommon
    let nodeType: String

    enum CodingKeys: String, CodingKey {
        case nodeType = "CollectNodeType"
    }

    init(from decoder: Decoder) throws {
        common = try QuestGoalCommon(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nodeType = try c.osfrString(.nodeType)
    }
}

enum QuestGoal: Codable, Equatable {
    case talkToNPC(QuestTalkGoal)
    case reachLocation(QuestReachGoal)
    case collect(QuestCollectGoal)

    private enum CodingKeys: String, CodingKey {
        case type = "Type"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try c.osfrInt(.type)
        guard let type = QuestGoalType(rawValue: rawType) else {
            throw ResourceCatalogError.invalidData("quest goal", detail: "Unknown goal type \(rawType)")
        }
        switch type {
        case .talkToNPC: self = .talkToNPC(try QuestTalkGoal(from: decoder))
        case .reachLocation: self = .reachLocation(try QuestReachGoal(from: decoder))
        case .collect: self = .collect(try QuestCollectGoal(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        func encodeCommon(_ common: QuestGoalCommon) throws {
            var c = encoder.container(keyedBy: QuestGoalCommon.CodingKeys.self)
            try c.encode(common.nameID, forKey: .nameID)
            try c.encode(common.descriptionID, forKey: .descriptionID)
            try c.encode(common.dialogueID, forKey: .dialogueID)
            try c.encode(common.dialogue, forKey: .dialogue)
            try c.encode(common.cursorID, forKey: .cursorID)
            try c.encode(common.interactRange, forKey: .interactRange)
            try c.encode(common.requiredCount, forKey: .requiredCount)
            try c.encode(common.withPrevious, forKey: .withPrevious)
            try c.encode(common.hideNpcIDsWhenDone, forKey: .hideNpcIDsWhenDone)
            try c.encode(common.hideEffectID, forKey: .hideEffectID)
            try c.encode(common.hideDelayMs, forKey: .hideDelayMs)
            try c.encode(common.npcEffectsUntilDone, forKey: .npcEffectsUntilDone)
        }

        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .talkToNPC(let goal):
            try c.encode(QuestGoalType.talkToNPC.rawValue, forKey: .type)
            try encodeCommon(goal.common)
            var specific = encoder.container(keyedBy: QuestTalkGoal.CodingKeys.self)
            try specific.encode(goal.targets, forKey: .targets)
            try specific.encode(goal.completeAfterDialogue, forKey: .completeAfterDialogue)
        case .reachLocation(let goal):
            try c.encode(QuestGoalType.reachLocation.rawValue, forKey: .type)
            try encodeCommon(goal.common)
            var specific = encoder.container(keyedBy: QuestReachGoal.CodingKeys.self)
            try specific.encode(goal.position, forKey: .position)
            try specific.encode(goal.radius, forKey: .radius)
            try specific.encode(goal.zoneDefinitionID, forKey: .zoneDefinitionID)
        case .collect(let goal):
            try c.encode(QuestGoalType.collect.rawValue, forKey: .type)
            try encodeCommon(goal.common)
            var specific = encoder.container(keyedBy: QuestCollectGoal.CodingKeys.self)
            try specific.encode(goal.nodeType, forKey: .nodeType)
        }
    }

    var common: QuestGoalCommon {
        switch self {
        case .talkToNPC(let goal): return goal.common
        case .reachLocation(let goal): return goal.common
        case .collect(let goal): return goal.common
        }
    }
}

struct QuestSceneActor: Codable, Equatable {
    let npcID: Int
    let position: ZoneVector
    let heading: Double

    enum CodingKeys: String, CodingKey {
        case npcID = "NpcId"
        case position = "Position"
        case heading = "Heading"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        npcID = try c.osfrInt(.npcID)
        position = try c.decodeIfPresent(ZoneVector.self, forKey: .position) ?? .zero
        heading = try c.osfrDouble(.heading)
    }
}

struct QuestSceneLine: Codable, Equatable {
    let npcID: Int
    let textID: Int

    enum CodingKeys: String, CodingKey {
        case npcID = "NpcId"
        case textID = "TextId"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        npcID = try c.osfrInt(.npcID)
        textID = try c.osfrInt(.textID)
    }
}

struct QuestScene: Codable, Equatable {
    let lineDelayMs: Int
    let actors: [QuestSceneActor]
    let lines: [QuestSceneLine]

    enum CodingKeys: String, CodingKey {
        case lineDelayMs = "LineDelayMs"
        case actors = "Actors"
        case lines = "Lines"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lineDelayMs = try c.osfrInt(.lineDelayMs)
        actors = try c.decodeIfPresent([QuestSceneActor].self, forKey: .actors) ?? []
        lines = try c.decodeIfPresent([QuestSceneLine].self, forKey: .lines) ?? []
    }
}

struct QuestDefinition: Codable, Equatable {
    let id: Int
    let name: String
    let titleID: Int
    let descriptionID: Int
    let giverDialogueID: Int
    let objectiveDescriptionID: Int
    let iconID: Int
    let giverNpcID: Int
    let targetNpcID: Int
    let rewardCoins: Int
    let rewardExperience: Int
    let rewardItems: [Int]
    let rewardCollectionID: Int
    let prerequisiteQuestID: Int?
    let nextQuestID: Int?
    let excludesQuestIDs: [Int]
    let hideObjectiveTarget: Bool
    let notificationAvailable: Int
    let notificationActive: Int
    let goals: [QuestGoal]
    let completionScene: QuestScene?

    enum CodingKeys: String, CodingKey {
        case id = "QuestId"
        case name = "Name"
        case titleID = "TitleId"
        case descriptionID = "DescriptionId"
        case giverDialogueID = "GiverDialogueId"
        case objectiveDescriptionID = "ObjectiveDescriptionId"
        case iconID = "IconId"
        case giverNpcID = "GiverNpcId"
        case targetNpcID = "TargetNpcId"
        case rewardCoins = "RewardCoins"
        case rewardExperience = "RewardExperience"
        case rewardItems = "RewardItems"
        case rewardCollectionID = "RewardCollectionId"
        case prerequisiteQuestID = "PrerequisiteQuestId"
        case nextQuestID = "NextQuestId"
        case excludesQuestIDs = "ExcludesQuestIds"
        case hideObjectiveTarget = "HideObjectiveTarget"
        case notificationAvailable = "NotificationAvailable"
        case notificationActive = "NotificationActive"
        case goals = "Goals"
        case completionScene = "CompletionScene"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.osfrInt(.id)
        name = try c.osfrString(.name)
        titleID = try c.osfrInt(.titleID)
        descriptionID = try c.osfrInt(.descriptionID)
        giverDialogueID = try c.osfrInt(.giverDialogueID)
        objectiveDescriptionID = try c.osfrInt(.objectiveDescriptionID)
        iconID = try c.osfrInt(.iconID)
        giverNpcID = try c.osfrInt(.giverNpcID)
        targetNpcID = try c.osfrInt(.targetNpcID)
        rewardCoins = try c.osfrInt(.rewardCoins)
        rewardExperience = try c.osfrInt(.rewardExperience)
        rewardItems = try c.osfrInts(.rewardItems)
        rewardCollectionID = try c.osfrInt(.rewardCollectionID)
        prerequisiteQuestID = try c.decodeIfPresent(Int.self, forKey: .prerequisiteQuestID)
        nextQuestID = try c.decodeIfPresent(Int.self, forKey: .nextQuestID)
        excludesQuestIDs = try c.osfrInts(.excludesQuestIDs)
        hideObjectiveTarget = try c.osfrBool(.hideObjectiveTarget)
        notificationAvailable = try c.decodeIfPresent(Int.self, forKey: .notificationAvailable) ?? 2
        notificationActive = try c.decodeIfPresent(Int.self, forKey: .notificationActive) ?? 6
        goals = try c.decodeIfPresent([QuestGoal].self, forKey: .goals) ?? []
        completionScene = try c.decodeIfPresent(QuestScene.self, forKey: .completionScene)
    }
}

// MARK: - Items and stores

struct ClientItemIcon: Codable, Equatable {
    let id: Int
    let tintID: Int

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case tintID = "TintId"
    }

    init(id: Int, tintID: Int) {
        self.id = id
        self.tintID = tintID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.osfrInt(.id)
        tintID = try c.osfrInt(.tintID)
    }
}

struct ClientItemStat: Codable, Equatable {
    let id: Int
    let type: Int
    let value: Double
    let hidden: Bool

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case type = "Type"
        case value = "Value"
        case hidden = "Unknown"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.osfrInt(.id)
        type = try c.osfrInt(.type)
        value = try c.osfrDouble(.value)
        hidden = try c.osfrBool(.hidden)
    }
}

struct ClientItemAbility: Codable, Equatable {
    let slot: Int
    let id: Int
    let iconID: Int

    enum CodingKeys: String, CodingKey {
        case slot = "Slot"
        case id = "Id"
        case iconID = "IconId"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slot = try c.osfrInt(.slot)
        id = try c.osfrInt(.id)
        iconID = try c.osfrInt(.iconID)
    }
}

struct ClientItemDefinition: Codable, Equatable {
    let id: Int
    let type: Int
    let nameID: Int
    let descriptionID: Int
    let iconID: Int
    let iconTintID: Int
    let cost: Int
    let classID: Int
    let maxStackSize: Int
    let slot: Int
    let categoryID: Int
    let modelName: String
    let textureAlias: String
    let tintAlias: String
    let powerRating: Int
    let memberDiscount: Int
    let resellValue: Int
    let noTrade: Bool
    let noSale: Bool
    let membersOnly: Bool
    let singleUse: Bool
    let isTintable: Bool
    let stats: [Int: ClientItemStat]
    let abilities: [ClientItemAbility]

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case type = "Type"
        case nameID = "NameId"
        case descriptionID = "DescriptionId"
        case icon = "Icon"
        case cost = "Cost"
        case classID = "Class"
        case maxStackSize = "MaxStackSize"
        case slot = "Slot"
        case categoryID = "CategoryId"
        case modelName = "ModelName"
        case textureAlias = "TextureAlias"
        case tintAlias = "TintAlias"
        case powerRating = "PowerRating"
        case memberDiscount = "MemberDiscount"
        case resellValue = "ResellValue"
        case noTrade = "NoTrade"
        case noSale = "NoSale"
        case membersOnly = "MembersOnly"
        case singleUse = "SingleUse"
        case isTintable = "IsTintable"
        case stats = "Stats"
        case abilities = "Abilities"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.osfrInt(.id)
        type = try c.osfrInt(.type)
        nameID = try c.osfrInt(.nameID)
        descriptionID = try c.osfrInt(.descriptionID)
        let icon = try c.decodeIfPresent(ClientItemIcon.self, forKey: .icon)
        iconID = icon?.id ?? 0
        iconTintID = icon?.tintID ?? 0
        cost = try c.osfrInt(.cost)
        classID = try c.osfrInt(.classID)
        maxStackSize = try c.osfrInt(.maxStackSize)
        slot = try c.osfrInt(.slot)
        categoryID = try c.osfrInt(.categoryID)
        modelName = try c.osfrString(.modelName)
        textureAlias = try c.osfrString(.textureAlias)
        tintAlias = try c.osfrString(.tintAlias)
        powerRating = try c.osfrInt(.powerRating)
        memberDiscount = try c.osfrInt(.memberDiscount)
        resellValue = try c.osfrInt(.resellValue)
        noTrade = try c.osfrBool(.noTrade)
        noSale = try c.osfrBool(.noSale)
        membersOnly = try c.osfrBool(.membersOnly)
        singleUse = try c.osfrBool(.singleUse)
        isTintable = try c.osfrBool(.isTintable)

        let rawStats = try c.decodeIfPresent([String: ClientItemStat].self, forKey: .stats) ?? [:]
        var decodedStats: [Int: ClientItemStat] = [:]
        for (key, value) in rawStats {
            guard let statID = Int(key) else {
                throw ResourceCatalogError.invalidData("ClientItemDefinitions.json", detail: "Invalid stat key \(key)")
            }
            decodedStats[statID] = value
        }
        stats = decodedStats
        abilities = try c.decodeIfPresent([ClientItemAbility].self, forKey: .abilities) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encode(nameID, forKey: .nameID)
        try c.encode(descriptionID, forKey: .descriptionID)
        let icon = ClientItemIcon(id: iconID, tintID: iconTintID)
        try c.encode(icon, forKey: .icon)
        try c.encode(cost, forKey: .cost)
        try c.encode(classID, forKey: .classID)
        try c.encode(maxStackSize, forKey: .maxStackSize)
        try c.encode(slot, forKey: .slot)
        try c.encode(categoryID, forKey: .categoryID)
        try c.encode(modelName, forKey: .modelName)
        try c.encode(textureAlias, forKey: .textureAlias)
        try c.encode(tintAlias, forKey: .tintAlias)
        try c.encode(powerRating, forKey: .powerRating)
        try c.encode(memberDiscount, forKey: .memberDiscount)
        try c.encode(resellValue, forKey: .resellValue)
        try c.encode(noTrade, forKey: .noTrade)
        try c.encode(noSale, forKey: .noSale)
        try c.encode(membersOnly, forKey: .membersOnly)
        try c.encode(singleUse, forKey: .singleUse)
        try c.encode(isTintable, forKey: .isTintable)
        try c.encode(Dictionary(uniqueKeysWithValues: stats.map { (String($0.key), $0.value) }), forKey: .stats)
        try c.encode(abilities, forKey: .abilities)
    }
}

struct CoinStoreItem: Codable, Equatable {
    let id: Int
    let categoryID: Int
    let tintGroupID: Int

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case categoryID = "CategoryId"
        case tintGroupID = "TintGroupId"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.osfrInt(.id)
        categoryID = try c.osfrInt(.categoryID)
        tintGroupID = try c.osfrInt(.tintGroupID)
    }
}

struct CollectionCoin: Codable, Equatable {
    let npcDefinitionID: Int
    let collectionID: Int
    let entryID: Int

    enum CodingKeys: String, CodingKey {
        case npcDefinitionID = "NpcDefinitionId"
        case collectionID = "CollectionId"
        case entryID = "EntryId"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        npcDefinitionID = try c.osfrInt(.npcDefinitionID)
        collectionID = try c.osfrInt(.collectionID)
        entryID = try c.osfrInt(.entryID)
    }
}

// MARK: - Character create mappings

enum CharacterCreateMappingKind: String, CaseIterable {
    case hair = "HairMappings.txt"
    case head = "HeadMappings.txt"
    case skinTone = "SkinToneMappings.txt"
    case facePaint = "FacePaintMappings.txt"
    case modelCustomization = "ModelCustomizationMappings.txt"

    var relativePath: String { "CharacterCreate/" + rawValue }
}

struct CharacterCreateMappings: Equatable {
    var hair: [Int: String] = [:]
    var head: [Int: String] = [:]
    var skinTone: [Int: String] = [:]
    var facePaint: [Int: String] = [:]
    var modelCustomization: [Int: String] = [:]

    subscript(kind: CharacterCreateMappingKind) -> [Int: String] {
        get {
            switch kind {
            case .hair: return hair
            case .head: return head
            case .skinTone: return skinTone
            case .facePaint: return facePaint
            case .modelCustomization: return modelCustomization
            }
        }
        set {
            switch kind {
            case .hair: hair = newValue
            case .head: head = newValue
            case .skinTone: skinTone = newValue
            case .facePaint: facePaint = newValue
            case .modelCustomization: modelCustomization = newValue
            }
        }
    }
}

// MARK: - Profiles and titles

/// Minimal view of `Resources/Profiles.json`. The offline host's
/// `unlockAllProfiles` flag controls how many of these are offered by the engine.
struct ProfileSummary: Codable, Equatable, Identifiable {
    let id: Int
    let nameID: Int
    let comment: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case nameID = "NameId"
        case comment = "Comment"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.osfrInt(.id)
        nameID = try c.osfrInt(.nameID)
        comment = try c.decodeIfPresent(String.self, forKey: .comment) ?? ""
    }
}

/// Minimal view of `Resources/PlayerTitles.json` for the corresponding title
/// unlock flag.
struct PlayerTitleSummary: Codable, Equatable, Identifiable {
    let id: Int
    let type: Int
    let nameID: Int

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case type = "Type"
        case nameID = "NameId"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.osfrInt(.id)
        type = try c.osfrInt(.type)
        nameID = try c.osfrInt(.nameID)
    }
}

// MARK: - Catalog

/// Reads Sanctuary's static game data from an explicit root directory.
///
/// Every dataset is optional: a partial bundle still produces a usable catalog
/// with empty collections. Present files must parse cleanly; unsafe paths and
/// duplicated ids are rejected rather than silently accepted.
struct ResourceCatalog: Equatable {
    static let maxFileBytes: Int64 = 256 * 1024 * 1024

    let rootURL: URL
    let zones: [ZoneDefinition]
    let zoneEnvironments: [String: ZoneEnvironmentGrid]
    let npcs: [Int: NpcDefinition]
    let quests: [Int: QuestDefinition]
    let itemDefinitions: [Int: ClientItemDefinition]
    let coinStoreItems: [Int: CoinStoreItem]
    let collectionCoins: [CollectionCoin]
    let characterCreate: CharacterCreateMappings
    let profiles: [Int: ProfileSummary]
    let playerTitles: [Int: PlayerTitleSummary]
    let loadedFiles: [String]
    let missingFiles: [String]

    /// Uses the folder staged by `ios/sync_sanctuary_resources.sh`.
    static func bundled() throws -> ResourceCatalog {
        guard let root = AppPaths.bundledSanctuaryResources else {
            throw ResourceCatalogError.invalidRoot("SanctuaryResources is not bundled")
        }
        return try ResourceCatalog(rootURL: root)
    }

    init(rootURL: URL) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ResourceCatalogError.invalidRoot(rootURL.path)
        }

        var loadedFiles: [String] = []
        var missingFiles: [String] = []

        func loadJSON<T: Decodable>(_ relativePath: String, _ type: T.Type) throws -> T? {
            let url = try Self.containedURL(relativePath, in: rootURL)
            guard fileManager.fileExists(atPath: url.path) else {
                missingFiles.append(relativePath)
                return nil
            }
            let data = try Self.readData(at: url, relativePath: relativePath)
            let value = try Self.decode(type, from: data, file: relativePath)
            loadedFiles.append(relativePath)
            return value
        }

        func jsonFiles(in directory: String) throws -> [String] {
            let url = try Self.containedURL(directory, in: rootURL)
            guard fileManager.fileExists(atPath: url.path) else {
                missingFiles.append(directory)
                return []
            }
            let subpaths: [String]
            do {
                subpaths = try fileManager.subpathsOfDirectory(atPath: url.path)
            } catch {
                throw ResourceCatalogError.unreadableFile(directory)
            }
            return subpaths
                .filter { $0.hasSuffix(".json") }
                .sorted()
        }

        let npcEntries = try loadJSON("Npcs.json", [NpcDefinition].self) ?? []
        let questEntries = try loadJSON("Quests.json", [QuestDefinition].self) ?? []
        let itemEntries = try loadJSON("ClientItemDefinitions.json", [ClientItemDefinition].self) ?? []
        let coinStoreEntries = try loadJSON("CoinStoreItems.json", [CoinStoreItem].self) ?? []
        let coinEntries = try loadJSON("CollectionCoins.json", [CollectionCoin].self) ?? []
        let profileEntries = try loadJSON("Profiles.json", [ProfileSummary].self) ?? []
        let titleEntries = try loadJSON("PlayerTitles.json", [PlayerTitleSummary].self) ?? []

        var zones: [ZoneDefinition] = []
        var seenZoneIDs: Set<Int> = []
        for path in try jsonFiles(in: "Zones") {
            let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard components.count == 1 else { continue }
            let relativePath = "Zones/" + path
            let url = try Self.containedURL(relativePath, in: rootURL)
            let data = try Self.readData(at: url, relativePath: relativePath)
            let zone = try Self.decode(ZoneDefinition.self, from: data, file: relativePath)
            guard seenZoneIDs.insert(zone.id).inserted else {
                throw ResourceCatalogError.duplicateID(relativePath, zone.id)
            }
            zones.append(zone)
            loadedFiles.append(relativePath)
        }
        zones.sort { $0.id < $1.id }

        var zoneEnvironments: [String: ZoneEnvironmentGrid] = [:]
        for path in try jsonFiles(in: "Zones/Environments") {
            let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard components.count == 1 else { continue }
            let relativePath = "Zones/Environments/" + path
            let url = try Self.containedURL(relativePath, in: rootURL)
            let data = try Self.readData(at: url, relativePath: relativePath)
            zoneEnvironments[(path as NSString).deletingPathExtension] =
                try Self.decode(ZoneEnvironmentGrid.self, from: data, file: relativePath)
            loadedFiles.append(relativePath)
        }

        var characterCreate = CharacterCreateMappings()
        for kind in CharacterCreateMappingKind.allCases {
            let relativePath = kind.relativePath
            let url = try Self.containedURL(relativePath, in: rootURL)
            guard fileManager.fileExists(atPath: url.path) else {
                missingFiles.append(relativePath)
                continue
            }
            let data = try Self.readData(at: url, relativePath: relativePath)
            characterCreate[kind] = try Self.parseCharacterMappings(data, file: relativePath)
            loadedFiles.append(relativePath)
        }

        self.rootURL = rootURL
        self.zones = zones
        self.zoneEnvironments = zoneEnvironments
        self.npcs = try Self.index(npcEntries, by: \.id, file: "Npcs.json")
        self.quests = try Self.index(questEntries, by: \.id, file: "Quests.json")
        self.itemDefinitions = try Self.index(itemEntries, by: \.id, file: "ClientItemDefinitions.json")
        self.coinStoreItems = try Self.index(coinStoreEntries, by: \.id, file: "CoinStoreItems.json")
        self.collectionCoins = coinEntries
        self.characterCreate = characterCreate
        self.profiles = try Self.index(profileEntries, by: \.id, file: "Profiles.json")
        self.playerTitles = try Self.index(titleEntries, by: \.id, file: "PlayerTitles.json")
        self.loadedFiles = loadedFiles
        self.missingFiles = missingFiles
    }

    /// Resolves a server-provided zone name to the exact resource name used by
    /// the bundle. Sanctuary sends display names such as "Fabled Realms" while
    /// the resources are named "FabledRealms", so matching must ignore casing
    /// and punctuation without accepting an unrelated zone.
    func zoneName(matching candidate: String) -> String? {
        let key = Self.zoneMatchKey(candidate)
        guard !key.isEmpty else { return nil }
        if let exact = zones.first(where: { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }) {
            return exact.name
        }
        if let normalized = zones.first(where: { Self.zoneMatchKey($0.name) == key }) {
            return normalized.name
        }
        return zoneEnvironments.keys.first { Self.zoneMatchKey($0) == key }
    }

    private static func zoneMatchKey(_ value: String) -> String {
        String(value.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
            .lowercased()
    }

    /// Resolves a bundle-relative path through `SafePath` containment checks.
    func url(forRelativePath relativePath: String) throws -> URL {
        try Self.containedURL(relativePath, in: rootURL)
    }

    func npc(id: Int) -> NpcDefinition? { npcs[id] }
    func quest(id: Int) -> QuestDefinition? { quests[id] }
    func item(id: Int) -> ClientItemDefinition? { itemDefinitions[id] }
    func coinStoreItem(id: Int) -> CoinStoreItem? { coinStoreItems[id] }

    func zone(id: Int) -> ZoneDefinition? { zones.first { $0.id == id } }

    private static func containedURL(_ relativePath: String, in root: URL) throws -> URL {
        let components = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty else { throw ResourceCatalogError.unsafePath(relativePath) }
        do {
            return try SafePath.contained(
                base: root,
                components: components,
                resolveSymlinks: false
            )
        } catch LauncherError.unsafePath(let value) {
            throw ResourceCatalogError.unsafePath(value)
        } catch {
            throw ResourceCatalogError.unsafePath(relativePath)
        }
    }

    private static func readData(at url: URL, relativePath: String) throws -> Data {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
        if let size = fileSize?.int64Value, size > maxFileBytes {
            throw ResourceCatalogError.invalidData(relativePath, detail: "File exceeds \(maxFileBytes) bytes")
        }
        do {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw ResourceCatalogError.unreadableFile(relativePath)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data, file: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ResourceCatalogError.malformedJSON(file, detail: String(describing: error))
        }
    }

    private static func index<T>(_ entries: [T], by keyPath: KeyPath<T, Int>, file: String) throws -> [Int: T] {
        var result: [Int: T] = [:]
        for entry in entries {
            let id = entry[keyPath: keyPath]
            guard result[id] == nil else { throw ResourceCatalogError.duplicateID(file, id) }
            result[id] = entry
        }
        return result
    }

    /// Sanctuary's `IdToStringLookup` files are caret-delimited `id^value^`
    /// rows. Headers and unparsable rows are skipped, like the C# loader.
    private static func parseCharacterMappings(_ data: Data, file: String) throws -> [Int: String] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ResourceCatalogError.invalidData(file, detail: "File is not UTF-8")
        }
        var result: [Int: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let columns = line.components(separatedBy: "^")
            guard columns.count >= 2 else { continue }
            let rawID = columns[0].trimmingCharacters(in: .whitespaces)
            let value = columns[1].trimmingCharacters(in: .whitespaces)
            guard let id = Int(rawID), !value.isEmpty else { continue }
            guard value.count <= 256,
                  !value.contains("/"),
                  !value.contains("\\"),
                  value.rangeOfCharacter(from: .controlCharacters) == nil
            else {
                throw ResourceCatalogError.invalidData(file, detail: "Unsafe value for id \(id)")
            }
            if result[id] == nil { result[id] = value }
        }
        return result
    }
}
