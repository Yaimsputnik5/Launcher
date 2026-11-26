import Foundation

// MARK: - Errors

/// Errors raised while loading Sanctuary's collection-node data.
///
/// Mirrors the validation style of Sanctuary's resource collections
/// (`CollectionNodePoolDefinitionCollection`, `CollectionNodeTypeDefinitionCollection`
/// and `CollectionNodeSpawnDefinitionCollection`): duplicate ids and invalid
/// definitions fail instead of being silently accepted.
enum CollectionSpawnError: LocalizedError, Equatable {
    case invalidRoot(String)
    case unsafePath(String)
    case unreadableFile(String)
    case malformedJSON(String, detail: String)
    case invalidData(String, detail: String)
    case duplicateID(String, Int)
    case tooManyEntries(String, Int)

    var errorDescription: String? {
        switch self {
        case .invalidRoot(let path): return "Not a Sanctuary resource directory: \(path)"
        case .unsafePath(let path): return "Unsafe resource path: \(path)"
        case .unreadableFile(let path): return "Could not read resource file: \(path)"
        case .malformedJSON(let file, let detail): return "Malformed JSON in \(file): \(detail)"
        case .invalidData(let file, let detail): return "Invalid data in \(file): \(detail)"
        case .duplicateID(let file, let id): return "Duplicate id \(id) in \(file)"
        case .tooManyEntries(let file, let limit): return "\(file) exceeds the \(limit)-entry safety cap"
        }
    }
}

// MARK: - Tolerant decoding

private extension KeyedDecodingContainer {
    func collectionInt(_ key: Key) throws -> Int {
        try decodeIfPresent(Int.self, forKey: key) ?? 0
    }

    func collectionDouble(_ key: Key) throws -> Double {
        try decodeIfPresent(Double.self, forKey: key) ?? 0
    }

    func collectionString(_ key: Key) throws -> String {
        try decodeIfPresent(String.self, forKey: key) ?? ""
    }

    func collectionBool(_ key: Key) throws -> Bool {
        try decodeIfPresent(Bool.self, forKey: key) ?? false
    }
}

// MARK: - Resource shapes

/// One weighted drop row from `CollectionNodePools.json`.
struct CollectionDropDefinition: Codable, Equatable {
    let itemDefinitionID: Int
    let weight: Int

    enum CodingKeys: String, CodingKey {
        case itemDefinitionID = "ItemDefinitionId"
        case weight = "Weight"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        itemDefinitionID = try c.collectionInt(.itemDefinitionID)
        weight = try c.collectionInt(.weight)
    }
}

/// Minimal shape of `Collections.json`; only the fields needed to correlate a
/// gathered node with the client's collection book are decoded.
struct CollectionDefinition: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let id: Int
        let nameID: Int
        let itemDefinitionID: Int

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case nameID = "NameId"
            case itemDefinitionID = "ItemDefinitionId"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.collectionInt(.id)
            nameID = try c.collectionInt(.nameID)
            itemDefinitionID = try c.collectionInt(.itemDefinitionID)
        }
    }

    let id: Int
    let nameID: Int
    let entries: [Entry]

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case nameID = "NameId"
        case entries = "Entries"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.collectionInt(.id)
        nameID = try c.collectionInt(.nameID)
        entries = try c.decodeIfPresent([Entry].self, forKey: .entries) ?? []
    }
}

/// Mirrors `CollectionNodeTypeDefinition.cs` (`CollectionNodeTypes.json`).
struct CollectionNodeTypeDefinition: Codable, Equatable {
    let key: String
    let name: String
    let modelID: Int
    let scale: Double
    let interactRange: Int
    let placementYOffset: Double
    let collectionID: Int
    let collectionEntryID: Int

    enum CodingKeys: String, CodingKey {
        case key = "Key"
        case name = "Name"
        case modelID = "ModelId"
        case scale = "Scale"
        case interactRange = "InteractRange"
        case placementYOffset = "PlacementYOffset"
        case collectionID = "CollectionId"
        case collectionEntryID = "CollectionEntryId"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.collectionString(.key)
        name = try c.collectionString(.name)
        modelID = try c.collectionInt(.modelID)
        scale = try c.collectionDouble(.scale)
        interactRange = try c.collectionInt(.interactRange)
        placementYOffset = try c.collectionDouble(.placementYOffset)
        collectionID = try c.collectionInt(.collectionID)
        collectionEntryID = try c.collectionInt(.collectionEntryID)
    }
}

/// Mirrors `CollectionNodePoolDefinition.cs` (`CollectionNodePools.json`).
/// Drop order is preserved because this offline simulation selects a
/// deterministic first entry instead of Sanctuary's `Random.Shared` roll.
struct CollectionNodePoolDefinition: Decodable, Equatable {
    let key: String
    let zoneDefinitionID: Int
    let nodeType: String
    let maxActiveNodes: Int
    let respawnSeconds: Int
    let playerSpecific: Bool
    let dropItemDefinitionIDs: [Int]

    enum CodingKeys: String, CodingKey {
        case key = "Key"
        case zoneDefinitionID = "ZoneDefinitionId"
        case nodeType = "NodeType"
        case maxActiveNodes = "MaxActiveNodes"
        case respawnSeconds = "RespawnSeconds"
        case playerSpecific = "PlayerSpecific"
        case dropTable = "DropTable"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.collectionString(.key)
        zoneDefinitionID = try c.collectionInt(.zoneDefinitionID)
        nodeType = try c.collectionString(.nodeType)
        maxActiveNodes = try c.collectionInt(.maxActiveNodes)
        respawnSeconds = try c.collectionInt(.respawnSeconds)
        playerSpecific = try c.collectionBool(.playerSpecific)
        let drops = try c.decodeIfPresent([CollectionDropDefinition].self, forKey: .dropTable) ?? []
        dropItemDefinitionIDs = drops.map(\.itemDefinitionID).filter { $0 > 0 }
    }

    /// `CollectionNodePoolDefinition.GetTargetActiveCount` from the C# source:
    /// a zero cap enables every hard point, otherwise the cap is min(cap, points).
    func targetActiveCount(hardPointCount: Int) -> Int {
        guard hardPointCount > 0 else { return 0 }
        return maxActiveNodes == 0 ? hardPointCount : min(maxActiveNodes, hardPointCount)
    }
}

/// Mirrors `CollectionNodeSpawnDefinition.cs`: `Id`, `Position [x,y,z]` and
/// `Heading`. `Pool` is optional here because Sanctuary marks it `[JsonIgnore]`
/// and derives it from the containing file name; a JSON hint is accepted for
/// hand-authored fixtures.
struct CollectionSpawnDefinition: Codable, Equatable {
    let id: Int
    let position: ZoneVector
    let heading: Double
    let poolHint: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case position = "Position"
        case heading = "Heading"
        case poolHint = "Pool"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.collectionInt(.id)
        heading = try c.collectionDouble(.heading)
        poolHint = try c.collectionString(.poolHint)

        let values = try c.decodeIfPresent([Double].self, forKey: .position) ?? []
        guard (2...4).contains(values.count), values.allSatisfy(\.isFinite) else {
            throw CollectionSpawnError.invalidData(
                "CollectionNodeSpawnDefinition",
                detail: "Expected 2–4 finite position components, got \(values.count)"
            )
        }
        if values.count == 2 {
            position = ZoneVector(x: values[0], y: 0, z: values[1], w: 0)
        } else {
            position = ZoneVector(x: values[0], y: values[1], z: values[2], w: 0)
        }
    }
}

/// A spawn joined with its pool/type definitions and the file-derived pool key.
struct LoadedCollectionSpawn: Equatable {
    let id: Int
    let poolKey: String
    let nodeTypeKey: String
    let position: ZoneVector
    let heading: Double
    let type: CollectionNodeTypeDefinition?
    let pool: CollectionNodePoolDefinition?

    var name: String { type?.name ?? nodeTypeKey }
    var modelID: Int { type?.modelID ?? 0 }
    var interactRange: Int { type?.interactRange ?? 12 }
    var collectionID: Int { type?.collectionID ?? 0 }
    var collectionEntryID: Int { type?.collectionEntryID ?? 0 }
    var placementYOffset: Double { type?.placementYOffset ?? 0 }
    var respawnSeconds: Int { pool?.respawnSeconds ?? 30 }
    var dropItemDefinitionIDs: [Int] { pool?.dropItemDefinitionIDs ?? [] }
    var isPlayerSpecific: Bool { pool?.playerSpecific ?? false }

    /// `CollectionNodePoolDefinition.GetTargetActiveCount`, with one hard point.
    var initialTargetActiveCount: Int { pool?.targetActiveCount(hardPointCount: 1) ?? 1 }
}

/// Reads collection spawns and their correlated definitions from a resource root.
struct CollectionSpawnCatalog: Equatable {
    static let maxFileBytes: Int64 = 8 * 1024 * 1024
    static let maxTypes = 512
    static let maxPools = 512
    static let maxCollections = 4_096
    static let maxSpawnFiles = 256
    static let maxSpawns = 20_000

    let rootURL: URL
    let zoneID: Int
    let nodeTypes: [String: CollectionNodeTypeDefinition]
    let pools: [String: CollectionNodePoolDefinition]
    let collections: [Int: CollectionDefinition]
    let spawns: [LoadedCollectionSpawn]
    let loadedFiles: [String]
    let missingFiles: [String]

    init(rootURL: URL, zoneID: Int) throws {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CollectionSpawnError.invalidRoot(rootURL.path)
        }

        var loaded: [String] = []
        var missing: [String] = []

        func contained(_ relativePath: String) throws -> URL {
            let components = relativePath
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            guard !components.isEmpty else { throw CollectionSpawnError.unsafePath(relativePath) }
            do {
                return try SafePath.contained(base: rootURL, components: components)
            } catch {
                throw CollectionSpawnError.unsafePath(relativePath)
            }
        }

        func read<T: Decodable>(_ relativePath: String, _ type: T.Type) throws -> T? {
            let url = try contained(relativePath)
            guard manager.fileExists(atPath: url.path) else {
                missing.append(relativePath)
                return nil
            }
            let size = (try? manager.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
            if let size, size.int64Value > Self.maxFileBytes {
                throw CollectionSpawnError.invalidData(relativePath, detail: "File exceeds \(Self.maxFileBytes) bytes")
            }
            let data: Data
            do {
                data = try Data(contentsOf: url, options: .mappedIfSafe)
            } catch {
                throw CollectionSpawnError.unreadableFile(relativePath)
            }
            do {
                let value = try JSONDecoder().decode(type, from: data)
                loaded.append(relativePath)
                return value
            } catch {
                throw CollectionSpawnError.malformedJSON(relativePath, detail: String(describing: error))
            }
        }

        let rawTypes = try read("CollectionNodeTypes.json", [CollectionNodeTypeDefinition].self) ?? []
        guard rawTypes.count <= Self.maxTypes else {
            throw CollectionSpawnError.tooManyEntries("CollectionNodeTypes.json", Self.maxTypes)
        }
        var typeIndex: [String: CollectionNodeTypeDefinition] = [:]
        for type in rawTypes {
            let key = type.key.lowercased()
            guard !key.isEmpty else {
                throw CollectionSpawnError.invalidData("CollectionNodeTypes.json", detail: "Empty type key")
            }
            guard typeIndex[key] == nil else {
                throw CollectionSpawnError.duplicateID("CollectionNodeTypes.json", type.modelID)
            }
            typeIndex[key] = type
        }
        nodeTypes = typeIndex

        let rawPools = try read("CollectionNodePools.json", [CollectionNodePoolDefinition].self) ?? []
        guard rawPools.count <= Self.maxPools else {
            throw CollectionSpawnError.tooManyEntries("CollectionNodePools.json", Self.maxPools)
        }
        var poolIndex: [String: CollectionNodePoolDefinition] = [:]
        for pool in rawPools {
            let key = pool.key.lowercased()
            guard !key.isEmpty else {
                throw CollectionSpawnError.invalidData("CollectionNodePools.json", detail: "Empty pool key")
            }
            guard pool.respawnSeconds >= 0, pool.maxActiveNodes >= 0 else {
                throw CollectionSpawnError.invalidData(
                    "CollectionNodePools.json",
                    detail: "Negative respawn/cap for pool \(key)"
                )
            }
            guard poolIndex[key] == nil else {
                throw CollectionSpawnError.duplicateID("CollectionNodePools.json", pool.zoneDefinitionID)
            }
            poolIndex[key] = pool
        }
        pools = poolIndex

        let rawCollections = try read("Collections.json", [CollectionDefinition].self) ?? []
        guard rawCollections.count <= Self.maxCollections else {
            throw CollectionSpawnError.tooManyEntries("Collections.json", Self.maxCollections)
        }
        var collectionIndex: [Int: CollectionDefinition] = [:]
        for definition in rawCollections {
            guard collectionIndex[definition.id] == nil else {
                throw CollectionSpawnError.duplicateID("Collections.json", definition.id)
            }
            collectionIndex[definition.id] = definition
        }
        collections = collectionIndex

        let spawnDirectory = "CollectionNodeSpawns/\(zoneID)"
        let directoryURL = try contained(spawnDirectory)
        var files: [String] = []
        if manager.fileExists(atPath: directoryURL.path) {
            let subpaths: [String]
            do {
                subpaths = try manager.subpathsOfDirectory(atPath: directoryURL.path)
            } catch {
                throw CollectionSpawnError.unreadableFile(spawnDirectory)
            }
            files = subpaths
                .filter { $0.hasSuffix(".json") }
                .sorted()
        } else {
            missing.append(spawnDirectory)
        }
        guard files.count <= Self.maxSpawnFiles else {
            throw CollectionSpawnError.tooManyEntries(spawnDirectory, Self.maxSpawnFiles)
        }

        var result: [LoadedCollectionSpawn] = []
        var seenSpawnIDs: Set<Int> = []
        for path in files {
            // Files are flat in Sanctuary; nested paths are rejected rather than
            // being joined into another resource directory.
            guard !path.contains("/"), !path.contains("\\") else {
                throw CollectionSpawnError.unsafePath(spawnDirectory + "/" + path)
            }
            _ = try SafePath.validatedLeaf(path)
            let relativePath = spawnDirectory + "/" + path
            let entries = try read(relativePath, [CollectionSpawnDefinition].self) ?? []
            guard entries.count <= Self.maxSpawns else {
                throw CollectionSpawnError.tooManyEntries(relativePath, Self.maxSpawns)
            }
            let filePoolKey = (path as NSString).deletingPathExtension.lowercased()
            for entry in entries {
                guard entry.id > 0, seenSpawnIDs.insert(entry.id).inserted else {
                    throw CollectionSpawnError.duplicateID(relativePath, entry.id)
                }
                let resolvedPoolKey = entry.poolHint.isEmpty ? filePoolKey : entry.poolHint.lowercased()
                let pool = poolIndex[resolvedPoolKey]
                let nodeTypeKey = (pool?.nodeType ?? resolvedPoolKey).lowercased()
                // Sanctuary applies PlacementYOffset when creating the node
                // (`BaseZone.TryCreateCollectionNode`/`TryPlaceCollectionNodeSpawn`).
                let original = entry.position
                let position = ZoneVector(
                    x: original.x,
                    y: original.y + (typeIndex[nodeTypeKey]?.placementYOffset ?? 0),
                    z: original.z,
                    w: original.w
                )
                result.append(LoadedCollectionSpawn(
                    id: entry.id,
                    poolKey: resolvedPoolKey,
                    nodeTypeKey: nodeTypeKey,
                    position: position,
                    heading: entry.heading,
                    type: typeIndex[nodeTypeKey],
                    pool: pool
                ))
            }
        }

        self.rootURL = rootURL
        self.zoneID = zoneID
        spawns = result.sorted { $0.id < $1.id }
        loadedFiles = loaded
        missingFiles = missing
    }

    func collection(id: Int) -> CollectionDefinition? { collections[id] }
}
