import Foundation

// MARK: - Errors

enum WorldSimulationError: LocalizedError, Equatable {
    case missingZone(String)
    case missingEnvironment(String)
    case unsafePath(String)
    case malformedJSON(String, detail: String)
    case invalidData(String, detail: String)

    var errorDescription: String? {
        switch self {
        case .missingZone(let name): return "Zone definition not found: \(name)"
        case .missingEnvironment(let name): return "Environment grid not found: \(name)"
        case .unsafePath(let path): return "Unsafe resource path: \(path)"
        case .malformedJSON(let file, let detail): return "Malformed JSON in \(file): \(detail)"
        case .invalidData(let file, let detail): return "Invalid data in \(file): \(detail)"
        }
    }
}

// MARK: - Public view models

enum WorldEntityKind: String, Codable, Equatable {
    case npc
    case collection
}

/// A renderable entity. NPC positions are explicitly marked as inferred because
/// `Resources/Npcs.json` contains definitions but no world spawn coordinates.
struct WorldEntity: Codable, Equatable, Identifiable {
    let id: UInt64
    let kind: WorldEntityKind
    let definitionID: Int
    let name: String
    let modelFileName: String
    let modelID: Int
    var position: ZoneVector
    let heading: Double
    let positionSource: String
    let interactRange: Int

    var isInferredPosition: Bool { kind == .npc }
}

struct QuestProgressSnapshot: Equatable {
    let questID: Int
    let name: String
    let progress: LocalQuestProgress
    let completedGoalCount: Int
    let totalGoalCount: Int
}

struct CollectionNodeSnapshot: Equatable, Identifiable {
    let id: Int
    let poolKey: String
    let nodeTypeKey: String
    let name: String
    let modelID: Int
    let position: ZoneVector
    let heading: Double
    let available: Bool
    let respawnTicksRemaining: Int
    let interactRange: Int
    let collectionID: Int
    let collectionEntryID: Int
    let collectedCount: Int
}

/// Host flags surfaced by the engine HUD. `unlockAllTiles` also changes
/// `WorldSimulation.isWalkable`; the other two gate the offered profile/title
/// lists derived from Sanctuary's static JSON.
struct WorldPlayOptions: Equatable {
    let unlockAllProfiles: Bool
    let unlockAllTitles: Bool
    let unlockAllTiles: Bool
}

/// Immutable frame handed to SwiftUI. `movementTicks`/`secondTicks` expose the
/// fixed-step cadence so a UI timer can drive `update(deltaTime:)` deterministically.
struct WorldSnapshot: Equatable {
    let zoneID: Int
    let zoneName: String
    let player: LocalWorldPosition
    let playerName: String
    let profileName: String
    let locale: GameLocale
    let coins: Int64
    let stationCash: Int64
    let options: WorldPlayOptions
    let availableProfileIDs: [Int]
    let availableTitleIDs: [Int]
    let movementTicks: Int
    let secondTicks: Int
    let visibleEntities: [WorldEntity]
    let nearbyPOIs: [WorldPointOfInterest]
    let quests: [QuestProgressSnapshot]
    let collectionNodes: [CollectionNodeSnapshot]
}

// MARK: - Internal state

private struct NpcMovementState {
    let anchor: ZoneVector
    let target: ZoneVector
    var phase: Int
    let speed: Double
}

private struct CollectionNodeState {
    let spawn: LoadedCollectionSpawn
    let entityID: UInt64
    var available: Bool
    var respawnTick: Int
    var collectedCount: Int
}

/// Data-driven offline world simulation.
///
/// Source-backed behavior (Sanctuary C#):
/// - `BaseZone.cs`: `FrameRate = 10`, `TickRate = 100ms`, separate 1 Hz timer,
///   `VisibleTileRadius = 2`, tile lookup via `floor(X/TileSize)` and
///   `floor(Z/TileSize)`, and out-of-bounds checks against environment id `-1`.
/// - `Player.cs` / `Npc.cs`: on-foot speed (8 units/s), `UpdateEveryTick` movement
///   stepping with `Speed * TickDeltaSeconds`, and `UpdateEverySecond` hooks.
/// - `CollectionNode.cs` / `BaseZone.cs`: one-shot reservation, completion that
///   enqueues a refill after `RespawnSeconds`, and refills processed every tick.
/// - `CollectionNodePoolDefinition.cs`: `MaxActiveNodes == 0` enables every hard
///   point; otherwise activation is capped at `min(cap, hardPointCount)`.
/// - `QuestManager.cs` / `CollectGoal.cs`: node-gathered events advance open
///   collect goals and persisted quest progress; all goals done completes quest.
///
/// Simplified (not a claim of server parity): NPC coordinates are inferred from
/// zone area environments or walkable tiles, drop rolls use the first drop-table
/// entry instead of `Random.Shared`, and NPC wandering uses deterministic
/// tile-to-tile oscillation; only offline player clicks use the shipped
/// Recast navmesh path.
final class WorldSimulation {
    static let movableTicksPerSecond = 10
    static let movableTickInterval = 0.1
    static let secondTickInterval = 1.0
    static let maxUpdateDelta = 1.0
    static let visibleTileRadius = 2
    static let poiTileRadius = 6
    static let onFootMovementSpeed = 8.0
    static let maxNPCEntities = 256
    static let maxCollectionEntities = 1_024
    static let maxTotalEntities = 2_048
    static let maxPOIFileBytes: Int64 = 4 * 1024 * 1024

    let catalog: ResourceCatalog
    let collectionCatalog: CollectionSpawnCatalog
    let worldMap: WorldMap
    let zone: ZoneDefinition

    private(set) var player: LocalCharacter
    private(set) var profileName: String
    private(set) var hostOptions: WorldPlayOptions
    private(set) var movementTicks = 0
    private(set) var secondTicks = 0
    private(set) var questProgress: [Int: LocalQuestProgress]

    private let session: LocalSession?
    private let npcs: [Int: NpcDefinition]
    private let quests: [Int: QuestDefinition]
    private var movableAccumulator = 0.0
    private var secondAccumulator = 0.0
    private var entities: [UInt64: WorldEntity] = [:]
    private var npcMovement: [UInt64: NpcMovementState] = [:]
    private var collectionNodes: [Int: CollectionNodeState] = [:]
    private var gatheredNodesByQuest: [Int: Set<Int>] = [:]
    private var collectedEntryIDs: Set<Int> = []
    private let navigationURL: URL?
    private var cachedNavMesh: NavMeshSet?
    private var didAttemptNavMesh = false

    init(
        rootURL: URL,
        zoneName: String? = nil,
        zoneID: Int? = nil,
        character: LocalCharacter? = nil,
        session: LocalSession? = nil,
        hostConfiguration: LocalHostConfiguration? = nil
    ) throws {
        // Bundled Sanctuary resources live under `SanctuaryResources/Resources`,
        // while lightweight fixtures may point directly at a resource folder.
        // Accept both without changing containment guarantees.
        let manager = FileManager.default
        let nestedResources = rootURL.appendingPathComponent("Resources", isDirectory: true)
        var nestedIsDirectory: ObjCBool = false
        let resourceRoot: URL
        if manager.fileExists(atPath: nestedResources.path, isDirectory: &nestedIsDirectory),
           nestedIsDirectory.boolValue {
            resourceRoot = nestedResources
        } else {
            resourceRoot = rootURL
        }

        let catalog = try ResourceCatalog(rootURL: resourceRoot)
        let zone: ZoneDefinition
        if let requestedName = zoneName {
            guard let match = catalog.zones.first(where: { $0.name == requestedName }) else {
                throw WorldSimulationError.missingZone(requestedName)
            }
            zone = match
        } else {
            // The persisted startingZoneID setting takes precedence over a
            // character's stale zone. Both resolve through the real catalog so
            // a fabricated zone cannot enter the engine.
            let requestedID = zoneID ?? hostConfiguration?.startingZoneID ?? character?.zoneID
            if let requestedID {
                guard let match = catalog.zone(id: requestedID) else {
                    throw WorldSimulationError.missingZone("zone ID \(requestedID)")
                }
                zone = match
            } else if let match = catalog.zones.first(where: { $0.name == "FabledRealms" }) ?? catalog.zones.first {
                zone = match
            } else {
                throw WorldSimulationError.missingZone("FabledRealms")
            }
        }
        guard let environment = catalog.zoneEnvironments[zone.name] else {
            throw WorldSimulationError.missingEnvironment(zone.name)
        }
        navigationURL = try? SafePath.bundledResourceURL(
            base: resourceRoot,
            components: ["NavMeshes", "\(zone.name).navmesh"]
        )

        let poiURL: URL
        do {
            poiURL = try SafePath.bundledResourceURL(
                base: resourceRoot,
                components: ["PointOfInterests.json"]
            )
        } catch {
            throw WorldSimulationError.unsafePath("PointOfInterests.json")
        }
        var pointsOfInterest: [WorldPointOfInterest] = []
        if FileManager.default.fileExists(atPath: poiURL.path) {
            let size = (try? FileManager.default.attributesOfItem(atPath: poiURL.path))?[.size] as? NSNumber
            if let size, size.int64Value > Self.maxPOIFileBytes {
                throw WorldSimulationError.invalidData(
                    "PointOfInterests.json",
                    detail: "File exceeds \(Self.maxPOIFileBytes) bytes"
                )
            }
            do {
                let data = try Data(contentsOf: poiURL, options: .mappedIfSafe)
                pointsOfInterest = try JSONDecoder().decode([WorldPointOfInterest].self, from: data)
            } catch {
                throw WorldSimulationError.malformedJSON(
                    "PointOfInterests.json",
                    detail: String(describing: error)
                )
            }
        }

        self.catalog = catalog
        self.zone = zone
        self.worldMap = WorldMap(
            zone: zone,
            environment: environment,
            pointsOfInterest: pointsOfInterest
        )
        self.collectionCatalog = try CollectionSpawnCatalog(rootURL: resourceRoot, zoneID: zone.id)
        self.npcs = catalog.npcs
        self.quests = catalog.quests
        self.session = session

        var resolvedCharacter = character ?? session?.selectedCharacter ?? LocalCharacter.makeDefault(
            id: 1,
            name: "Local",
            configuration: hostConfiguration ?? LocalHostConfiguration()
        )
        // A non-default starting zone loads its own grid, but a newly created
        // offline character still carries zone 1's persisted spawn. Reset it to
        // the *selected* zone's real spawn so the player does not appear inside
        // a different zone's coordinates (or outside its walkable grid).
        let hasExplicitStartZone = zoneID != nil
        if resolvedCharacter.zoneID != zone.id
            || (hasExplicitStartZone && zone.id != 1 && resolvedCharacter.position == .fabledRealmsSpawn) {
            resolvedCharacter.position = LocalWorldPosition(
                x: Float(zone.spawnPosition.x),
                y: Float(zone.spawnPosition.y),
                z: Float(zone.spawnPosition.z),
                rotationX: Float(zone.spawnRotation.x),
                rotationZ: Float(zone.spawnRotation.z)
            )
        }
        if let hostConfiguration {
            resolvedCharacter.name = hostConfiguration.characterName
            resolvedCharacter.zoneID = zone.id
            resolvedCharacter.coins = hostConfiguration.startingCoins
            resolvedCharacter.stationCash = hostConfiguration.startingStationCash
            resolvedCharacter.locale = hostConfiguration.locale
            resolvedCharacter.unlockAllProfiles = hostConfiguration.unlockAllProfiles
            resolvedCharacter.unlockAllTitles = hostConfiguration.unlockAllTitles
            resolvedCharacter.unlockAllTiles = hostConfiguration.unlockAllTiles
        } else {
            resolvedCharacter.zoneID = zone.id
        }
        self.player = resolvedCharacter
        self.profileName = hostConfiguration?.accountName
            ?? session?.activeAccount?.username
            ?? "local"
        self.hostOptions = WorldPlayOptions(
            unlockAllProfiles: resolvedCharacter.unlockAllProfiles,
            unlockAllTitles: resolvedCharacter.unlockAllTitles,
            unlockAllTiles: resolvedCharacter.unlockAllTiles
        )
        self.questProgress = Self.normalizedProgress(
            resolvedCharacter.quests,
            quests: catalog.quests
        )
        if let activeID = resolvedCharacter.activeQuestID,
           questProgress[activeID] == nil,
           let definition = catalog.quests[activeID] {
            let firstGoalID = definition.goals.first.map { Self.goalIdentifier($0, index: 0) } ?? 0
            questProgress[activeID] = LocalQuestProgress(
                questID: activeID,
                currentGoalID: firstGoalID,
                completed: false,
                goalProgress: []
            )
        }

        buildEntities()
        syncPlayerQuests()
    }

    /// Applies persisted offline host settings to an already running local
    /// simulation. A changed starting zone is handled by rebuilding the
    /// simulation (its zone grid is immutable), but every other setting now
    /// takes effect in the live world instead of only on the next start.
    func applyHostConfiguration(_ configuration: LocalHostConfiguration) {
        guard !zone.name.isEmpty else { return }
        player.name = configuration.characterName
        player.coins = configuration.startingCoins
        player.stationCash = configuration.startingStationCash
        player.locale = configuration.locale
        player.unlockAllProfiles = configuration.unlockAllProfiles
        player.unlockAllTitles = configuration.unlockAllTitles
        player.unlockAllTiles = configuration.unlockAllTiles
        profileName = configuration.accountName
        hostOptions = WorldPlayOptions(
            unlockAllProfiles: configuration.unlockAllProfiles,
            unlockAllTitles: configuration.unlockAllTitles,
            unlockAllTiles: configuration.unlockAllTiles
        )
    }

    // MARK: - Snapshot

    var snapshot: WorldSnapshot {
        let playerTile = worldMap.tile(for: playerPosition)
        let visible = entities.values
            .filter { entity in
                if entity.kind == .collection,
                   let state = collectionNodes.first(where: { $0.value.entityID == entity.id })?.value,
                   !state.available {
                    return false
                }
                let tile = worldMap.tile(for: entity.position)
                return Self.tileDistance(tile, playerTile) <= Self.visibleTileRadius
            }
            .sorted { lhs, rhs in
                if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
                if lhs.definitionID != rhs.definitionID { return lhs.definitionID < rhs.definitionID }
                return lhs.id < rhs.id
            }

        let nearbyPOIs = worldMap.pointsOfInterest
            .filter { Self.tileDistance(worldMap.tile(for: $0.position), playerTile) <= Self.poiTileRadius }
            .sorted { $0.id < $1.id }

        let nodes = collectionNodes.values
            .sorted { $0.spawn.id < $1.spawn.id }
            .map { state in
                CollectionNodeSnapshot(
                    id: state.spawn.id,
                    poolKey: state.spawn.poolKey,
                    nodeTypeKey: state.spawn.nodeTypeKey,
                    name: state.spawn.name,
                    modelID: state.spawn.modelID,
                    position: state.spawn.position,
                    heading: state.spawn.heading,
                    available: state.available,
                    respawnTicksRemaining: max(0, state.respawnTick - movementTicks),
                    interactRange: state.spawn.interactRange,
                    collectionID: state.spawn.collectionID,
                    collectionEntryID: state.spawn.collectionEntryID,
                    collectedCount: state.collectedCount
                )
            }

        let questViews = questProgress.keys.sorted().compactMap { questID -> QuestProgressSnapshot? in
            guard let progress = questProgress[questID] else { return nil }
            let definition = quests[questID]
            let goals = definition?.goals ?? []
            let total = goals.count
            let done = goals.enumerated().filter { index, goal in
                let goalID = Self.goalIdentifier(goal, index: index)
                let required = max(1, goal.common.requiredCount)
                let gathered = progress.goalProgress
                    .filter { $0.goalID == goalID }
                    .reduce(0) { $0 + max(0, $1.count) }
                return gathered >= required
            }.count
            return QuestProgressSnapshot(
                questID: questID,
                name: definition?.name ?? "Quest \(questID)",
                progress: progress,
                completedGoalCount: progress.completed ? total : min(total, done),
                totalGoalCount: total
            )
        }

        let allProfiles = catalog.profiles.keys.sorted()
        let allTitles = catalog.playerTitles.keys.sorted()
        let offeredProfiles = player.unlockAllProfiles ? allProfiles : Array(allProfiles.prefix(1))
        let offeredTitles = player.unlockAllTitles ? allTitles : Array(allTitles.prefix(1))

        return WorldSnapshot(
            zoneID: zone.id,
            zoneName: zone.name,
            player: player.position,
            playerName: player.name,
            profileName: profileName,
            locale: player.locale,
            coins: player.coins,
            stationCash: player.stationCash,
            options: hostOptions,
            availableProfileIDs: offeredProfiles,
            availableTitleIDs: offeredTitles,
            movementTicks: movementTicks,
            secondTicks: secondTicks,
            visibleEntities: visible,
            nearbyPOIs: nearbyPOIs,
            quests: questViews,
            collectionNodes: nodes
        )
    }

    // MARK: - Movement (BaseZone.GetTileFromPosition / Player.UpdateZoneTile)

    /// Tile-space X/Z lookup matches `BaseZone.GetTileFromPosition`:
    /// latitude comes from X, longitude from Z, both floored by `TileSize`.
    func isWalkable(_ position: ZoneVector) -> Bool {
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite else { return false }
        let tile = worldMap.tile(for: position)
        let absoluteLongitude = zone.startLongitude + tile.longitude
        let absoluteLatitude = zone.startLatitude + tile.latitude
        guard absoluteLongitude >= zone.startLongitude,
              absoluteLongitude < zone.endLongitude,
              absoluteLatitude >= zone.startLatitude,
              absoluteLatitude < zone.endLatitude
        else { return false }
        // Offline host option: reveal the whole loaded zone, including tiles
        // whose server environment id is -1 (normally outside the playable map).
        if hostOptions.unlockAllTiles { return true }
        return worldMap.environmentID(longitude: tile.longitude, latitude: tile.latitude) != -1
    }

    @discardableResult
    func movePlayer(to position: ZoneVector) -> Bool {
        guard isWalkable(position) else { return false }
        var updated = player.position
        updated.x = Float(position.x)
        updated.y = Float(position.y)
        updated.z = Float(position.z)
        guard updated.isValid else { return false }
        if let session {
            do {
                try session.movePlayer(to: updated)
            } catch {
                return false
            }
        }
        player.position = updated
        return true
    }

    @discardableResult
    func movePlayer(to position: LocalWorldPosition) -> Bool {
        movePlayer(to: ZoneVector(
            x: Double(position.x),
            y: Double(position.y),
            z: Double(position.z),
            w: 0
        ))
    }

    /// Real-waypoint route from the shipped Sanctuary SNAV mesh. Returns nil
    /// when the zone has no navmesh or no polygon graph connects the points;
    /// callers then keep the existing tile-grid direct movement. This never
    /// fabricates coordinates from server state.
    func navigationWaypoints(from start: ZoneVector, to goal: ZoneVector) -> [ZoneVector]? {
        guard start.x.isFinite, start.y.isFinite, start.z.isFinite,
              goal.x.isFinite, goal.y.isFinite, goal.z.isFinite
        else { return nil }

        if !didAttemptNavMesh {
            didAttemptNavMesh = true
            if let navigationURL,
               FileManager.default.fileExists(atPath: navigationURL.path),
               let data = try? Data(contentsOf: navigationURL, options: .mappedIfSafe) {
                cachedNavMesh = try? NavMeshSet(data: data)
            }
        }
        guard let mesh = cachedNavMesh else { return nil }
        let path = try? mesh.findPath(
            from: NavMeshSet.Point(x: Float(start.x), y: Float(start.y), z: Float(start.z)),
            to: NavMeshSet.Point(x: Float(goal.x), y: Float(goal.y), z: Float(goal.z))
        )
        return path?.map {
            ZoneVector(x: Double($0.x), y: Double($0.y), z: Double($0.z), w: 0)
        }
    }

    /// Moves at Sanctuary's on-foot speed (8 units/s) and slides along a blocked
    /// tile edge by resolving X and Z separately. Never enters a `-1` tile.
    @discardableResult
    func stepPlayer(toward target: ZoneVector, deltaTime: TimeInterval) -> Bool {
        let delta = min(max(deltaTime, 0), Self.maxUpdateDelta)
        guard delta > 0, target.x.isFinite, target.z.isFinite else { return false }
        let current = playerPosition
        let dx = target.x - current.x
        let dz = target.z - current.z
        let distance = (dx * dx + dz * dz).squareRoot()
        guard distance > 0.000_001 else { return true }

        let ratio = min(1, (Self.onFootMovementSpeed * delta) / distance)
        let desired = ZoneVector(
            x: current.x + dx * ratio,
            y: current.y,
            z: current.z + dz * ratio,
            w: 0
        )
        if isWalkable(desired), movePlayer(to: desired) { return true }

        var moved = false
        let xOnly = ZoneVector(x: desired.x, y: current.y, z: current.z, w: 0)
        if isWalkable(xOnly), movePlayer(to: xOnly) { moved = true }
        let afterX = playerPosition
        let zOnly = ZoneVector(x: afterX.x, y: afterX.y, z: desired.z, w: 0)
        if isWalkable(zOnly), movePlayer(to: zOnly) { moved = true }
        return moved
    }

    // MARK: - Fixed-step update (BaseZone update timers)

    /// Advances the simulation by real elapsed time. Both loops use fixed steps:
    /// 10 Hz for entities/collection refills and 1 Hz for zone/quest sweeps.
    func update(deltaTime: TimeInterval) {
        let delta = min(max(deltaTime, 0), Self.maxUpdateDelta)
        movableAccumulator += delta
        secondAccumulator += delta

        while movableAccumulator + 1e-9 >= Self.movableTickInterval {
            movableAccumulator -= Self.movableTickInterval
            if movableAccumulator < 0 { movableAccumulator = 0 }
            tickMovable()
        }
        while secondAccumulator + 1e-9 >= Self.secondTickInterval {
            secondAccumulator -= Self.secondTickInterval
            if secondAccumulator < 0 { secondAccumulator = 0 }
            tickSecond()
        }
    }

    private func tickMovable() {
        movementTicks += 1

        // BaseZone.ProcessCollectionNodeRefills runs on every 10 Hz tick.
        for id in collectionNodes.keys.sorted() {
            guard var node = collectionNodes[id], !node.available else { continue }
            guard node.respawnTick <= movementTicks else { continue }
            node.available = true
            collectionNodes[id] = node
        }

        // Npc.StepPathFollower advances Speed * TickDeltaSeconds. No navmesh is
        // available offline, so each NPC oscillates between two walkable tiles.
        for id in npcMovement.keys.sorted() {
            guard var motion = npcMovement[id], var entity = entities[id] else { continue }
            let destination = motion.phase == 0 ? motion.target : motion.anchor
            let dx = destination.x - entity.position.x
            let dz = destination.z - entity.position.z
            let distance = (dx * dx + dz * dz).squareRoot()
            if distance <= motion.speed / Double(Self.movableTicksPerSecond) {
                if isWalkable(destination) {
                    entity.position = destination
                    entities[id] = entity
                }
                motion.phase = 1 - motion.phase
                npcMovement[id] = motion
                continue
            }
            let ratio = min(1, (motion.speed / Double(Self.movableTicksPerSecond)) / distance)
            let next = ZoneVector(
                x: entity.position.x + dx * ratio,
                y: entity.position.y,
                z: entity.position.z + dz * ratio,
                w: 0
            )
            if isWalkable(next) {
                entity.position = next
                entities[id] = entity
            } else {
                motion.phase = 1 - motion.phase
                npcMovement[id] = motion
            }
        }
    }

    private func tickSecond() {
        secondTicks += 1
        // BaseZone.UpdateEverySecond fires the zone's "second" script event.
        // Here it also resolves ReachLocation goals without needing an interact.
        for questID in questProgress.keys.sorted() {
            guard let definition = quests[questID],
                  let progress = questProgress[questID],
                  !progress.completed,
                  let goalIndex = currentGoalIndex(progress: progress, quest: definition),
                  case .reachLocation(let goal) = definition.goals[goalIndex]
            else { continue }
            let dx = playerPosition.x - goal.position.x
            let dz = playerPosition.z - goal.position.z
            let distanceSquared = dx * dx + dz * dz
            let radiusSquared = max(0, goal.radius) * max(0, goal.radius)
            guard distanceSquared <= radiusSquared else { continue }
            advanceGoal(
                questID: questID,
                goalIndex: goalIndex,
                targetID: UInt64(max(0, goal.zoneDefinitionID))
            )
        }
    }

    // MARK: - Interactions and quest progress

    /// Mirrors `CommandPacketInteractRequestHandler.HandleCollectionNode`:
    /// range check, one-shot reserve, quest `NodeGatheredEvent`, then the node is
    /// completed and a refill is scheduled from `RespawnSeconds`.
    @discardableResult
    func interactWithCollectionNode(id: Int) -> Bool {
        guard var node = collectionNodes[id], node.available else { return false }
        let range = Double(max(0, node.spawn.interactRange))
        guard isWithinRange(node.spawn.position, range: range) else { return false }

        node.available = false
        let respawnTicks = max(1, node.spawn.respawnSeconds * Self.movableTicksPerSecond)
        node.respawnTick = min(movementTicks + respawnTicks, Int.max / 2)
        node.collectedCount += 1
        collectionNodes[id] = node

        if node.spawn.collectionEntryID > 0 {
            collectedEntryIDs.insert(node.spawn.collectionEntryID)
        }
        // RewardManager uses a weighted random roll. Offline determinism picks
        // the first positive drop-table entry from the pool instead.
        if let itemDefinitionID = node.spawn.dropItemDefinitionIDs.first {
            _ = try? session?.grantItem(definitionID: itemDefinitionID, count: 1, tint: 0)
        }

        for questID in questProgress.keys.sorted() {
            guard let definition = quests[questID],
                  let progress = questProgress[questID],
                  !progress.completed,
                  let goalIndex = currentGoalIndex(progress: progress, quest: definition),
                  case .collect(let goal) = definition.goals[goalIndex],
                  goal.nodeType.lowercased() == node.spawn.nodeTypeKey.lowercased()
            else { continue }
            var gathered = gatheredNodesByQuest[questID] ?? []
            guard gathered.insert(id).inserted else { continue }
            gatheredNodesByQuest[questID] = gathered
            advanceGoal(
                questID: questID,
                goalIndex: goalIndex,
                targetID: UInt64(max(0, id))
            )
            // QuestManager.OnEvent stops once a quest event is credited.
            break
        }
        return true
    }

    /// Mirrors `QuestManager.AdvanceAtNpc`: a talk goal advances when the open
    /// goal targets this NPC definition id.
    @discardableResult
    func talkToNPC(definitionID: Int) -> Bool {
        guard definitionID > 0,
              let npc = entities.values.first(where: {
                  $0.kind == .npc && $0.definitionID == definitionID
              }),
              isWithinRange(npc.position, range: Double(max(0, npc.interactRange)))
        else { return false }
        var advanced = false
        for questID in questProgress.keys.sorted() {
            guard let definition = quests[questID],
                  let progress = questProgress[questID],
                  !progress.completed,
                  let goalIndex = currentGoalIndex(progress: progress, quest: definition),
                  case .talkToNPC(let goal) = definition.goals[goalIndex],
                  goal.targets.contains(where: { $0.npcID == definitionID })
            else { continue }
            advanceGoal(
                questID: questID,
                goalIndex: goalIndex,
                targetID: UInt64(definitionID)
            )
            advanced = true
            break
        }
        return advanced
    }

    private func advanceGoal(questID: Int, goalIndex: Int, targetID: UInt64) {
        guard let definition = quests[questID],
              definition.goals.indices.contains(goalIndex),
              var progress = questProgress[questID],
              !progress.completed
        else { return }

        let goal = definition.goals[goalIndex]
        let goalID = Self.goalIdentifier(goal, index: goalIndex)
        let required = max(1, goal.common.requiredCount)
        if progress.currentGoalID != goalID { progress.currentGoalID = goalID }

        if let rowIndex = progress.goalProgress.firstIndex(where: {
            $0.goalID == goalID && $0.targetID == targetID
        }) {
            progress.goalProgress[rowIndex].count = min(
                required,
                progress.goalProgress[rowIndex].count + 1
            )
        } else {
            progress.goalProgress.append(LocalQuestGoalProgress(
                goalID: goalID,
                targetID: targetID,
                count: 1
            ))
        }

        let gathered = progress.goalProgress
            .filter { $0.goalID == goalID }
            .reduce(0) { $0 + max(0, $1.count) }
        guard gathered >= required else {
            questProgress[questID] = progress
            syncPlayerQuests()
            return
        }

        let nextIndex = goalIndex + 1
        if nextIndex < definition.goals.count {
            progress.currentGoalID = Self.goalIdentifier(definition.goals[nextIndex], index: nextIndex)
        } else {
            progress.currentGoalID = 0
            progress.completed = true
        }
        questProgress[questID] = progress
        syncPlayerQuests()

        if progress.completed {
            // LocalSession is the persisted store; it has no per-goal setter, so
            // the completed quest row is written through its public command.
            _ = try? session?.completeQuest(questID: questID)
        }
    }

    private func syncPlayerQuests() {
        player.quests = questProgress.keys.sorted().compactMap { questProgress[$0] }
        player.activeQuestID = questProgress.first(where: { !$0.value.completed })?.key
        // Sanctuary stores goal counters per character, so persist every active
        // row as soon as a goal advances. Completion is committed separately
        // through completeQuest, which also clears the active quest pointer.
        for progress in player.quests where !progress.completed {
            _ = try? session?.updateQuestProgress(progress)
        }
    }

    private static func normalizedProgress(
        _ rows: [LocalQuestProgress],
        quests: [Int: QuestDefinition]
    ) -> [Int: LocalQuestProgress] {
        var result: [Int: LocalQuestProgress] = [:]
        for original in rows {
            var progress = original
            if let quest = quests[original.questID], let first = quest.goals.first {
                let firstID = goalIdentifier(first, index: 0)
                progress.goalProgress = progress.goalProgress.map { row in
                    var adjusted = row
                    if adjusted.goalID == 0 { adjusted.goalID = firstID }
                    return adjusted
                }
                if progress.currentGoalID == 0 { progress.currentGoalID = firstID }
            }
            result[progress.questID] = progress
        }
        return result
    }

    private static func goalIdentifier(_ goal: QuestGoal, index: Int) -> Int {
        goal.common.nameID != 0 ? goal.common.nameID : index
    }

    private func currentGoalIndex(progress: LocalQuestProgress, quest: QuestDefinition) -> Int? {
        guard !progress.completed else { return nil }
        return quest.goals.indices.first {
            Self.goalIdentifier(quest.goals[$0], index: $0) == progress.currentGoalID
        }
    }

    // MARK: - Entity construction

    private func buildEntities() {
        let questReferencedNPCs = Set(quests.values.flatMap { quest -> [Int] in
            var ids = [quest.giverNpcID, quest.targetNpcID]
            for goal in quest.goals {
                if case .talkToNPC(let talkGoal) = goal {
                    ids.append(contentsOf: talkGoal.targets.map(\.npcID))
                }
            }
            return ids.filter { $0 > 0 }
        })

        let sortedNPCs = npcs.values.sorted { lhs, rhs in
            let lhsPriority = npcPriority(lhs, referenced: questReferencedNPCs)
            let rhsPriority = npcPriority(rhs, referenced: questReferencedNPCs)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            return lhs.id < rhs.id
        }
        let npcLimit = min(Self.maxNPCEntities, Self.maxTotalEntities)

        for npc in sortedNPCs.prefix(npcLimit) {
            let (position, source) = inferredPosition(for: npc)
            let id = UInt64(100_000 + max(0, npc.id))
            let entity = WorldEntity(
                id: id,
                kind: .npc,
                definitionID: npc.id,
                name: npc.name.isEmpty ? "NPC \(npc.id)" : npc.name,
                modelFileName: npc.modelFileName,
                modelID: npc.modelID,
                position: position,
                heading: 0,
                positionSource: source,
                interactRange: 100
            )
            entities[id] = entity
            if let motion = wanderState(for: entity, npcID: npc.id) {
                npcMovement[id] = motion
            }
        }

        let groups = Dictionary(grouping: collectionCatalog.spawns, by: \.poolKey)
        for poolKey in groups.keys.sorted() {
            let spawns = (groups[poolKey] ?? []).sorted { $0.id < $1.id }
            let pool = collectionCatalog.pools[poolKey]
            let target = pool?.targetActiveCount(hardPointCount: spawns.count) ?? min(1, spawns.count)
            for spawn in spawns.prefix(target) {
                guard entities.count < Self.maxTotalEntities,
                      collectionNodes.count < Self.maxCollectionEntities
                else { break }
                let id = UInt64(200_000 + max(0, spawn.id))
                let entity = WorldEntity(
                    id: id,
                    kind: .collection,
                    definitionID: spawn.id,
                    name: spawn.name,
                    modelFileName: "",
                    modelID: spawn.modelID,
                    position: spawn.position,
                    heading: spawn.heading,
                    positionSource: "exact spawn from CollectionNodeSpawns/\(zone.id)",
                    interactRange: spawn.interactRange
                )
                entities[id] = entity
                collectionNodes[spawn.id] = CollectionNodeState(
                    spawn: spawn,
                    entityID: id,
                    available: true,
                    respawnTick: 0,
                    collectedCount: 0
                )
            }
        }
    }

    private func npcPriority(_ npc: NpcDefinition, referenced: Set<Int>) -> Int {
        if referenced.contains(npc.id) { return 0 }
        if npc.areaDefinitionID != 0 { return 1 }
        if !npc.modelFileName.isEmpty { return 2 }
        return 3
    }

    /// NPC positions are not present in the bundled resources. Pick a walkable
    /// tile deterministically from the NPC's area definition (or the whole zone)
    /// and label the result as inferred in the public entity.
    private func inferredPosition(for npc: NpcDefinition) -> (ZoneVector, String) {
        let area = zone.areaDefinitions.first { $0.id == npc.areaDefinitionID }
        let allowedEnvironments = Set(area?.environmentIDs.filter { $0 >= 0 } ?? [])
        var candidates: [(longitude: Int, latitude: Int, environment: Int)] = []
        let scanLimit = 20_000
        guard zone.startLongitude < zone.endLongitude,
              zone.startLatitude < zone.endLatitude
        else {
            return (zone.spawnPosition, "inferred from zone spawn (empty zone grid)")
        }

        outer: for absoluteLongitude in zone.startLongitude..<zone.endLongitude {
            for absoluteLatitude in zone.startLatitude..<zone.endLatitude {
                let environment = worldMap.environmentID(
                    longitude: absoluteLongitude - zone.startLongitude,
                    latitude: absoluteLatitude - zone.startLatitude
                )
                guard environment != -1 else { continue }
                if !allowedEnvironments.isEmpty, !allowedEnvironments.contains(environment) { continue }
                candidates.append((absoluteLongitude, absoluteLatitude, environment))
                if candidates.count >= scanLimit { break outer }
            }
        }

        guard !candidates.isEmpty else {
            return (zone.spawnPosition, "inferred from zone spawn (no walkable tile found)")
        }
        let index = max(0, npc.id) % candidates.count
        let selected = candidates[index]
        let tilePosition = worldMap.tilePosition(
            longitude: selected.longitude - zone.startLongitude,
            latitude: selected.latitude - zone.startLatitude
        )
        let offset = min(max(npc.verticalOffset, -100), 100)
        let position = ZoneVector(
            x: tilePosition.x,
            y: zone.spawnPosition.y + offset,
            z: tilePosition.z,
            w: tilePosition.w
        )
        let source: String
        if let area {
            source = "inferred from area definition \(area.id), environment \(selected.environment), tile (\(selected.longitude), \(selected.latitude))"
        } else {
            source = "inferred from walkable tile (\(selected.longitude), \(selected.latitude))"
        }
        return (position, source)
    }

    private func wanderState(for entity: WorldEntity, npcID: Int) -> NpcMovementState? {
        let origin = worldMap.tile(for: entity.position)
        let directions = [(0, 1), (1, 0), (0, -1), (-1, 0)]
        let direction = directions[max(0, npcID) % directions.count]
        let targetTile = (
            longitude: origin.longitude + direction.0,
            latitude: origin.latitude + direction.1
        )
        guard worldMap.environmentID(
            longitude: targetTile.longitude,
            latitude: targetTile.latitude
        ) != -1 else { return nil }
        let tilePosition = worldMap.tilePosition(
            longitude: targetTile.longitude,
            latitude: targetTile.latitude
        )
        let target = ZoneVector(
            x: tilePosition.x,
            y: entity.position.y,
            z: tilePosition.z,
            w: tilePosition.w
        )
        return NpcMovementState(
            anchor: entity.position,
            target: target,
            phase: 0,
            speed: Self.onFootMovementSpeed * 0.25
        )
    }

    // MARK: - Helpers

    private var playerPosition: ZoneVector {
        ZoneVector(
            x: Double(player.position.x),
            y: Double(player.position.y),
            z: Double(player.position.z),
            w: 0
        )
    }

    private func isWithinRange(_ position: ZoneVector, range: Double) -> Bool {
        let current = playerPosition
        let dx = position.x - current.x
        let dz = position.z - current.z
        return dx * dx + dz * dz <= range * range
    }

    private static func tileDistance(
        _ lhs: (longitude: Int, latitude: Int),
        _ rhs: (longitude: Int, latitude: Int)
    ) -> Int {
        max(abs(lhs.longitude - rhs.longitude), abs(lhs.latitude - rhs.latitude))
    }
}
