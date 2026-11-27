import Foundation

// MARK: - Render-facing value types

/// Device-independent RGBA color. SwiftUI/Metal adapters convert this into their
/// own color types; the core engine stays Foundation-only for Linux tests.
struct EngineColor: Equatable, Sendable {
    let r: Double
    let g: Double
    let b: Double
    let a: Double

    static let clear = EngineColor(r: 0, g: 0, b: 0, a: 0)
}

struct EnginePoint: Equatable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(_ unit: (x: Double, y: Double)) {
        self.x = unit.x
        self.y = unit.y
    }
}

struct EngineRect: Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

enum EngineDrawableKind: String, Equatable, Sendable {
    case tile
    case clientTexture
    case pointOfInterest
    case collection
    case npc
    case player
    case destination
}

/// A projected, drawable primitive in normalized viewport coordinates.
struct EngineDrawable: Equatable, Identifiable, Sendable {
    let id: UInt64
    let kind: EngineDrawableKind
    let rect: EngineRect
    let color: EngineColor
    let outline: EngineColor?
    let label: String
    let layer: Int
    /// Key into `EngineFrame.textures`. Nil means the renderer uses flat color.
    let textureName: String?

    init(
        id: UInt64,
        kind: EngineDrawableKind,
        rect: EngineRect,
        color: EngineColor,
        outline: EngineColor?,
        label: String,
        layer: Int,
        textureName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.rect = rect
        self.color = color
        self.outline = outline
        self.label = label
        self.layer = layer
        self.textureName = textureName
    }
}

///正交 camera for the atlas-style zone view. Zoom is anchored at `center`.
struct EngineCamera: Equatable, Sendable {
    var center: EnginePoint
    var zoom: Double

    static let `default` = EngineCamera(center: EnginePoint(x: 0.5, y: 0.5), zoom: 1)

    func project(_ rect: EngineRect) -> EngineRect {
        EngineRect(
            x: (rect.x - center.x) * zoom + 0.5,
            y: (rect.y - center.y) * zoom + 0.5,
            width: rect.width * zoom,
            height: rect.height * zoom
        )
    }

    func unproject(_ point: EnginePoint) -> EnginePoint {
        EnginePoint(
            x: center.x + (point.x - 0.5) / zoom,
            y: center.y + (point.y - 0.5) / zoom
        )
    }
}

/// Immutable frame consumed by `MetalWorldView`.
struct EngineFrame: Equatable, Sendable {
    let zoneID: Int
    let zoneName: String
    let camera: EngineCamera
    let drawables: [EngineDrawable]
    let movementTick: Int
    let secondTick: Int
    /// Decoded RGBA8 images referenced by `EngineDrawable.textureName`.
    let textures: [String: DecodedImage]
    /// Human-readable status of the first client texture load, if attempted.
    let textureStatus: String?
    /// Human-readable status of the client zone-definition lookup.
    let zoneStatus: String?
    /// Packet-backed world status. Nil until a gateway packet is applied.
    let worldStatus: String?

    init(
        zoneID: Int,
        zoneName: String,
        camera: EngineCamera,
        drawables: [EngineDrawable],
        movementTick: Int,
        secondTick: Int,
        textures: [String: DecodedImage] = [:],
        textureStatus: String? = nil,
        zoneStatus: String? = nil,
        worldStatus: String? = nil
    ) {
        self.zoneID = zoneID
        self.zoneName = zoneName
        self.camera = camera
        self.drawables = drawables
        self.movementTick = movementTick
        self.secondTick = secondTick
        self.textures = textures
        self.textureStatus = textureStatus
        self.zoneStatus = zoneStatus
        self.worldStatus = worldStatus
    }

    var drawableCount: Int { drawables.count }
}

// MARK: - Input and entities

enum EngineInputKind: String, Equatable, Sendable {
    case moveTo
    case interactCollection
    case talkToNPC
    case travelToPOI
    case zoom
    case recenter
}

struct EngineInputEvent: Equatable, Sendable {
    let kind: EngineInputKind
    let unitX: Double
    let unitY: Double
    let definitionID: Int

    private init(kind: EngineInputKind, unitX: Double = 0, unitY: Double = 0, definitionID: Int = 0) {
        self.kind = kind
        self.unitX = unitX
        self.unitY = unitY
        self.definitionID = definitionID
    }

    static func moveTo(unitX: Double, unitY: Double) -> EngineInputEvent {
        EngineInputEvent(kind: .moveTo, unitX: unitX, unitY: unitY)
    }

    static func interactCollection(id: Int) -> EngineInputEvent {
        EngineInputEvent(kind: .interactCollection, definitionID: id)
    }

    static func talkToNPC(definitionID: Int) -> EngineInputEvent {
        EngineInputEvent(kind: .talkToNPC, definitionID: definitionID)
    }

    static func travelToPOI(id: Int) -> EngineInputEvent {
        EngineInputEvent(kind: .travelToPOI, definitionID: id)
    }

    static func zoom(_ factor: Double) -> EngineInputEvent {
        EngineInputEvent(kind: .zoom, unitX: factor)
    }

    static func recenter() -> EngineInputEvent {
        EngineInputEvent(kind: .recenter)
    }
}

struct EngineEntity: Equatable, Identifiable {
    let id: UInt64
    let kind: WorldEntityKind
    let definitionID: Int
    var position: ZoneVector
    let label: String
    let modelFileName: String
    let isInferredPosition: Bool

    init(_ entity: WorldEntity) {
        id = entity.id
        kind = entity.kind
        definitionID = entity.definitionID
        position = entity.position
        label = entity.name
        modelFileName = entity.modelFileName
        isInferredPosition = entity.isInferredPosition
    }
}

/// Mutable registry shared by simulation snapshots and the renderer.
final class EngineEntityRegistry {
    private(set) var entities: [UInt64: EngineEntity] = [:]

    @discardableResult
    func upsert(_ entity: EngineEntity) -> EngineEntity {
        entities[entity.id] = entity
        return entity
    }

    func upsert(_ newEntities: [EngineEntity]) {
        for entity in newEntities { upsert(entity) }
        let valid = Set(newEntities.map(\.id))
        entities = entities.filter { valid.contains($0.key) }
    }

    func entity(id: UInt64) -> EngineEntity? { entities[id] }

    func clear() { entities.removeAll() }
}

// MARK: - Scene graph and asset pipeline

enum EngineSceneNodeKind: String, Equatable {
    case root
    case terrain
    case entityLayer
    case overlay
}

struct EngineSceneNode: Equatable, Identifiable {
    let id: UInt64
    let kind: EngineSceneNodeKind
    let name: String
    var children: [EngineSceneNode] = []
    var drawable: EngineDrawable?

    static let rootID: UInt64 = 0
}

/// Minimal ordered scene graph. Terrain renders first, entities second, and
/// overlays (player, destination) last.
final class EngineSceneGraph {
    private(set) var root = EngineSceneNode(id: EngineSceneNode.rootID, kind: .root, name: "World")

    func rebuild(terrain: [EngineDrawable], entities: [EngineDrawable], overlays: [EngineDrawable]) {
        let terrainNode = EngineSceneNode(
            id: 1,
            kind: .terrain,
            name: "Terrain",
            children: terrain.map {
                EngineSceneNode(id: $0.id, kind: .terrain, name: $0.label, drawable: $0)
            }
        )
        let entityNode = EngineSceneNode(
            id: 2,
            kind: .entityLayer,
            name: "Entities",
            children: entities.map {
                EngineSceneNode(id: $0.id, kind: .entityLayer, name: $0.label, drawable: $0)
            }
        )
        let overlayNode = EngineSceneNode(
            id: 3,
            kind: .overlay,
            name: "Overlay",
            children: overlays.map {
                EngineSceneNode(id: $0.id, kind: .overlay, name: $0.label, drawable: $0)
            }
        )
        root = EngineSceneNode(
            id: EngineSceneNode.rootID,
            kind: .root,
            name: "World",
            children: [terrainNode, entityNode, overlayNode]
        )
    }

    var flattenedDrawables: [EngineDrawable] {
        root.children.flatMap(\.children).compactMap(\.drawable)
    }
}

/// Resolves TGA/DDS/PNG bytes through the existing embedded `.pack`/`.rcc`
/// pipeline. Decoded textures are cached by manifest-relative path.
final class EngineAssetPipeline {
    private let loader: TextureLoader
    private var cache: [String: DecodedImage] = [:]

    init(loader: TextureLoader = TextureLoader()) {
        self.loader = loader
    }

    @discardableResult
    func image(relativePath: String) throws -> DecodedImage {
        if let cached = cache[relativePath] { return cached }
        let decoded = try loader.load(relativePath: relativePath)
        cache[relativePath] = decoded
        return decoded
    }

    func cachedImage(relativePath: String) -> DecodedImage? { cache[relativePath] }

    func clearCache() { cache.removeAll() }

    var cachedCount: Int { cache.count }
    var cachedImages: [String: DecodedImage] { cache }
}

// MARK: - Engine

enum OSFREnginePresentationMode: Equatable, Sendable {
    case offline
    /// Renders only gateway packet data over the real Sanctuary zone grid.
    case remote
}

/// Owns fixed-step advancement, input, the entity registry, the camera, and the
/// scene graph. SwiftUI/Metal only supply wall-clock time and draw `EngineFrame`.
final class OSFREngine {
    let simulation: WorldSimulation
    let entityRegistry = EngineEntityRegistry()
    let sceneGraph = EngineSceneGraph()
    let assetPipeline: EngineAssetPipeline
    let terrainPalette: ClientTerrainPalette
    let presentationMode: OSFREnginePresentationMode

    private(set) var remoteObservation: GatewayWorldObservation
    private let selfGUID: UInt64?

    private(set) var camera: EngineCamera
    private(set) var frame: EngineFrame
    private let terrainTexturePath: String?
    private var terrainTextureStatus: String?
    private var destination: ZoneVector?
    private var lastAdvance: Date?
    private var accumulator: TimeInterval = 0

    init(
        simulation: WorldSimulation,
        assetPipeline: EngineAssetPipeline? = nil,
        terrainTexturePath: String? = nil,
        zoneManifest: ClientZoneManifest? = nil,
        presentationMode: OSFREnginePresentationMode = .offline,
        selfGUID: UInt64? = nil,
        remoteObservation: GatewayWorldObservation = .empty
    ) {
        self.simulation = simulation
        self.assetPipeline = assetPipeline ?? EngineAssetPipeline()
        self.presentationMode = presentationMode
        self.selfGUID = selfGUID
        self.remoteObservation = remoteObservation
        let snapshot = simulation.snapshot
        let resolvedZone = zoneManifest
            ?? (try? ClientAssetDataLoader().zoneManifest(forZoneName: snapshot.zoneName))
        self.terrainPalette = ClientTerrainPalette(
            zone: resolvedZone,
            worldMap: simulation.worldMap,
            assetPipeline: self.assetPipeline
        )
        let unit = simulation.worldMap.unitPosition(for: Self.vector(snapshot.player)).map(EnginePoint.init)
            ?? EnginePoint(x: 0.5, y: 0.5)
        self.camera = EngineCamera(center: unit, zoom: 1)
        self.terrainTexturePath = terrainTexturePath
            ?? ClientTextureCatalog.texturePath(forZoneName: snapshot.zoneName)
        self.frame = EngineFrame(
            zoneID: snapshot.zoneID,
            zoneName: snapshot.zoneName,
            camera: camera,
            drawables: [],
            movementTick: snapshot.movementTicks,
            secondTick: snapshot.secondTicks
        )
        loadTerrainTextureIfAvailable()
        rebuildScene()
    }

    private func loadTerrainTextureIfAvailable() {
        guard let terrainTexturePath else { return }
        do {
            let image = try assetPipeline.image(relativePath: terrainTexturePath)
            terrainTextureStatus = "Embedded client DDS \(image.width)x\(image.height): \(terrainTexturePath)"
        } catch {
            terrainTextureStatus = "Client texture unavailable: \(error.localizedDescription)"
        }
    }

    // MARK: Input

    func handle(_ input: EngineInputEvent) {
        guard presentationMode == .offline
                || input.kind == .zoom
                || input.kind == .recenter
        else { return }
        switch input.kind {
        case .moveTo:
            let target = simulation.worldMap.worldPosition(unitX: input.unitX, unitY: input.unitY)
            if simulation.isWalkable(target) {
                destination = target
            } else if let walkable = simulation.worldMap.walkableUnit(
                near: input.unitX,
                unitY: input.unitY
            ) {
                destination = simulation.worldMap.worldPosition(
                    unitX: walkable.x,
                    unitY: walkable.y
                )
            } else if simulation.hostOptions.unlockAllTiles {
                // The host option intentionally reveals out-of-grid tiles.
                destination = target
            }
        case .interactCollection:
            simulation.interactWithCollectionNode(id: input.definitionID)
        case .talkToNPC:
            simulation.talkToNPC(definitionID: input.definitionID)
        case .travelToPOI:
            guard let poi = simulation.worldMap.pointsOfInterest.first(where: { $0.id == input.definitionID })
            else { return }
            let preferred = simulation.worldMap.unitPosition(for: poi.spawnPosition)
                ?? simulation.worldMap.unitPosition(for: poi.position)
            let unit = preferred.map(EnginePoint.init) ?? EnginePoint(x: 0.5, y: 0.5)
            handle(.moveTo(unitX: unit.x, unitY: unit.y))
        case .zoom:
            let factor = min(max(input.unitX, 0.5), 3)
            let proposed = min(max(camera.zoom * factor, 0.5), 3)
            camera.zoom = proposed
        case .recenter:
            if presentationMode == .remote {
                let target = selfGUID
                    .flatMap { remoteObservation.positions[$0]?.position }
                    ?? simulation.worldMap.zone.spawnPosition
                if let unit = simulation.worldMap.unitPosition(for: target) {
                    camera.center = EnginePoint(unit)
                }
            } else {
                let spawn = simulation.worldMap.zone.spawnPosition
                if simulation.movePlayer(to: spawn) {
                    if let unit = simulation.worldMap.unitPosition(for: spawn) {
                        camera.center = EnginePoint(unit)
                    }
                    destination = nil
                }
            }
        }
        rebuildScene()
    }

    func moveTo(unitX: Double, unitY: Double) {
        handle(.moveTo(unitX: unitX, unitY: unitY))
    }

    /// Applies decoded gateway packets. Remote presentation never mutates the
    /// local simulation, so a packet is the only source of remote entity data.
    func applyRemoteObservation(_ observation: GatewayWorldObservation) {
        guard presentationMode == .remote else { return }
        remoteObservation = observation
        rebuildScene()
    }

    // MARK: Tick ownership

    /// Supplied by the UI display timer, but all fixed-step accumulation lives
    /// here. Passing the same elapsed time twice is idempotent within a frame.
    @discardableResult
    func advance(now: Date = Date()) -> EngineFrame {
        guard presentationMode == .offline else {
            lastAdvance = now
            rebuildScene()
            return frame
        }
        let delta: TimeInterval
        if let lastAdvance {
            delta = min(max(now.timeIntervalSince(lastAdvance), 0), WorldSimulation.maxUpdateDelta)
        } else {
            delta = 0
        }
        lastAdvance = now
        accumulator += delta

        if let destination {
            let player = Self.vector(simulation.snapshot.player)
            let dx = destination.x - player.x
            let dz = destination.z - player.z
            let distance = (dx * dx + dz * dz).squareRoot()
            let step = WorldSimulation.onFootMovementSpeed * delta
            if distance <= step + 0.5 {
                simulation.stepPlayer(toward: destination, deltaTime: delta)
                self.destination = nil
            } else {
                simulation.stepPlayer(toward: destination, deltaTime: delta)
            }
        }
        simulation.update(deltaTime: accumulator)
        accumulator = 0
        rebuildScene()
        return frame
    }

    // MARK: Scene construction

    private func rebuildScene() {
        let snapshot = simulation.snapshot
        if presentationMode == .offline {
            entityRegistry.upsert(snapshot.visibleEntities.map(EngineEntity.init))
        } else {
            entityRegistry.clear()
        }

        let map = simulation.worldMap
        var terrain: [EngineDrawable] = []
        let maxTiles = 4_096
        var tileID: UInt64 = 10_000
        outer: for longitude in 0..<map.longitudeCount {
            for latitude in 0..<map.latitudeCount {
                guard terrain.count < maxTiles else { break outer }
                guard let unit = map.unitPosition(for: map.tilePosition(longitude: longitude, latitude: latitude))
                else { continue }
                let width = 1.0 / Double(max(map.latitudeCount, 1))
                let height = 1.0 / Double(max(map.longitudeCount, 1))
                let environment = map.environmentID(longitude: longitude, latitude: latitude)
                terrain.append(EngineDrawable(
                    id: tileID,
                    kind: .tile,
                    rect: EngineRect(
                        x: unit.x - width / 2,
                        y: unit.y - height / 2,
                        width: width,
                        height: height
                    ),
                    color: terrainPalette.color(environmentID: environment),
                    outline: EngineColor(r: 0, g: 0, b: 0, a: 0.16),
                    label: terrainPalette.label(environmentID: environment, worldMap: map),
                    layer: 0
                ))
                tileID += 1
            }
        }

        var entities: [EngineDrawable] = []
        if presentationMode == .remote {
            // Every remote marker requires a decoded position packet. Nothing
            // from the local offline simulation is drawn in this mode.
            for position in remoteObservation.positions.values.sorted(by: { $0.guid < $1.guid }) {
                guard let unit = map.unitPosition(for: position.position) else { continue }
                let isSelf = position.guid == selfGUID
                entities.append(Self.marker(
                    id: position.guid,
                    kind: .player,
                    unit: EnginePoint(unit),
                    radius: isSelf ? 0.009 : 0.006,
                    color: isSelf
                        ? EngineColor(r: 0.24, g: 0.54, b: 1, a: 1)
                        : EngineColor(r: 0.94, g: 0.45, b: 0.32, a: 0.95),
                    outline: EngineColor(r: 1, g: 1, b: 1, a: 1),
                    label: isSelf ? "Packet you · \(position.guid)" : "Packet \(position.guid)",
                    layer: 3
                ))
            }
        } else {
            for poi in snapshot.nearbyPOIs {
                guard let unit = map.unitPosition(for: poi.position) else { continue }
                entities.append(Self.marker(
                    id: UInt64(1_000 + poi.id),
                    kind: .pointOfInterest,
                    unit: EnginePoint(unit),
                    radius: 0.006,
                    color: EngineColor(r: 0.98, g: 0.82, b: 0.22, a: 1),
                    label: poi.name,
                    layer: 1
                ))
            }
            for node in snapshot.collectionNodes where node.available {
                guard let unit = map.unitPosition(for: node.position) else { continue }
                entities.append(Self.marker(
                    id: UInt64(100_000 + node.id),
                    kind: .collection,
                    unit: EnginePoint(unit),
                    radius: 0.005,
                    color: EngineColor(r: 0.20, g: 0.78, b: 0.38, a: 1),
                    label: node.name.isEmpty ? node.poolKey : node.name,
                    layer: 2
                ))
            }
            for entity in snapshot.visibleEntities where entity.kind == .npc {
                guard let unit = map.unitPosition(for: entity.position) else { continue }
                entities.append(Self.marker(
                    id: entity.id,
                    kind: .npc,
                    unit: EnginePoint(unit),
                    radius: 0.006,
                    color: EngineColor(r: 0.62, g: 0.40, b: 0.82, a: 0.92),
                    outline: entity.isInferredPosition
                        ? EngineColor(r: 0.98, g: 0.86, b: 0.28, a: 1)
                        : EngineColor(r: 1, g: 1, b: 1, a: 1),
                    label: entity.name,
                    layer: 3
                ))
            }
        }

        var overlays: [EngineDrawable] = []
        if presentationMode == .offline {
            if let playerUnit = map.unitPosition(for: Self.vector(snapshot.player)) {
                overlays.append(Self.marker(
                    id: UInt64.max,
                    kind: .player,
                    unit: EnginePoint(playerUnit),
                    radius: 0.009,
                    color: EngineColor(r: 0.24, g: 0.54, b: 1, a: 1),
                    outline: EngineColor(r: 1, g: 1, b: 1, a: 1),
                    label: snapshot.playerName,
                    layer: 4
                ))
            }
            if let destination,
               let unit = map.unitPosition(for: destination) {
                overlays.append(Self.marker(
                    id: UInt64.max - 1,
                    kind: .destination,
                    unit: EnginePoint(unit),
                    radius: 0.012,
                    color: EngineColor.clear,
                    outline: EngineColor(r: 0.20, g: 0.92, b: 0.96, a: 1),
                    label: "Destination",
                    layer: 5
                ))
            }
        }
        if let terrainTexturePath,
           assetPipeline.cachedImage(relativePath: terrainTexturePath) != nil {
            // A real, decoded client minimap tile. It is inserted as a HUD-size
            // panel rather than pretending to be the whole reconstructed zone.
            overlays.append(EngineDrawable(
                id: UInt64.max - 2,
                kind: .clientTexture,
                rect: EngineRect(x: 0.72, y: 0.03, width: 0.25, height: 0.25),
                color: EngineColor(r: 1, g: 1, b: 1, a: 1),
                outline: EngineColor(r: 0.85, g: 0.85, b: 0.9, a: 1),
                label: "Client texture: \(terrainTexturePath)",
                layer: 6,
                textureName: terrainTexturePath
            ))
        }

        sceneGraph.rebuild(terrain: terrain, entities: entities, overlays: overlays)
        let projected = sceneGraph.flattenedDrawables.map { drawable in
            EngineDrawable(
                id: drawable.id,
                kind: drawable.kind,
                rect: camera.project(drawable.rect),
                color: drawable.color,
                outline: drawable.outline,
                label: drawable.label,
                layer: drawable.layer,
                textureName: drawable.textureName
            )
        }
        frame = EngineFrame(
            zoneID: snapshot.zoneID,
            zoneName: snapshot.zoneName,
            camera: camera,
            drawables: projected,
            movementTick: snapshot.movementTicks,
            secondTick: snapshot.secondTicks,
            textures: assetPipeline.cachedImages,
            textureStatus: terrainTextureStatus,
            zoneStatus: terrainPalette.status,
            worldStatus: currentWorldStatus
        )
    }

    private var currentWorldStatus: String? {
        guard presentationMode == .remote else { return nil }
        let event = remoteObservation.lastEvent ?? "Awaiting gateway world packets"
        return "\(event) · \(remoteObservation.positionCount) positions · \(remoteObservation.chatCount) chat"
    }

    private static func marker(
        id: UInt64,
        kind: EngineDrawableKind,
        unit: EnginePoint,
        radius: Double,
        color: EngineColor,
        outline: EngineColor? = nil,
        label: String,
        layer: Int
    ) -> EngineDrawable {
        EngineDrawable(
            id: id,
            kind: kind,
            rect: EngineRect(
                x: unit.x - radius,
                y: unit.y - radius,
                width: radius * 2,
                height: radius * 2
            ),
            color: color,
            outline: outline,
            label: label,
            layer: layer
        )
    }

    private static func vector(_ position: LocalWorldPosition) -> ZoneVector {
        ZoneVector(
            x: Double(position.x),
            y: Double(position.y),
            z: Double(position.z),
            w: 0
        )
    }
}
