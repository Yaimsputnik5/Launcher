import SwiftUI

/// Native in-process world player backed by Sanctuary data and simulation
/// rules. It draws the zone tile grid, exact collection spawns, inferred NPC
/// positions, destinations and the persisted local character. No desktop
/// executable, Wine layer or external process is involved.
struct GamePlayerView: View {
    @EnvironmentObject private var state: AppState
    @State private var simulation: WorldSimulation?
    @State private var snapshot: WorldSnapshot?
    @State private var destinationUnit: (x: Double, y: Double)?
    @State private var selectedEntityID: UInt64?
    @State private var selectedNodeID: Int?
    @State private var selectedDestination: WorldPointOfInterest?
    @State private var errorMessage: String?
    @State private var zoom: Double = 1
    @State private var showingQuests = false
    @State private var showingDestinations = false
    @State private var showingEntities = false
    @State private var lastTick = Date()

    private let mapSide: CGFloat = 1024

    var body: some View {
        NavigationStack {
            Group {
                if let simulation, let snapshot {
                    GeometryReader { _ in
                        ZStack(alignment: .topLeading) {
                            worldCanvas(simulation: simulation, snapshot: snapshot)
                            hud(simulation: simulation, snapshot: snapshot)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .padding(8)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                    .padding()
                            }
                        }
                    }
                } else if let errorMessage {
                    ContentUnavailableView(
                        "World Unavailable",
                        systemImage: "map",
                        description: Text(errorMessage)
                    )
                } else {
                    ProgressView("Loading world…")
                }
            }
            .navigationTitle("World")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingEntities = true
                        } label: {
                            Label("Entities", systemImage: "figure.walk")
                        }
                        Button {
                            showingDestinations = true
                        } label: {
                            Label("Destinations", systemImage: "mappin.and.ellipse")
                        }
                        Button {
                            showingQuests = true
                        } label: {
                            Label("Journal", systemImage: "book")
                        }
                        Button {
                            zoom = min(zoom + 0.25, 3)
                        } label: {
                            Label("Zoom In", systemImage: "plus.magnifyingglass")
                        }
                        Button {
                            zoom = max(zoom - 0.25, 0.5)
                        } label: {
                            Label("Zoom Out", systemImage: "minus.magnifyingglass")
                        }
                        Button {
                            recenter()
                        } label: {
                            Label("Return to Spawn", systemImage: "scope")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingQuests) {
                journalSheet
            }
            .sheet(isPresented: $showingDestinations) {
                destinationsSheet
            }
            .sheet(isPresented: $showingEntities) {
                entitiesSheet
            }
            .task {
                load()
            }
            .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
                advance()
            }
        }
    }

    // MARK: - World rendering

    private func worldCanvas(simulation: WorldSimulation, snapshot: WorldSnapshot) -> some View {
        let map = simulation.worldMap
        return ScrollView([.horizontal, .vertical]) {
            Canvas { context, size in
                let cellWidth = size.width / CGFloat(max(map.latitudeCount, 1))
                let cellHeight = size.height / CGFloat(max(map.longitudeCount, 1))

                for longitudeIndex in 0..<map.longitudeCount {
                    for latitudeIndex in 0..<map.latitudeCount {
                        let rectangle = CGRect(
                            x: CGFloat(latitudeIndex) * cellWidth,
                            y: CGFloat(longitudeIndex) * cellHeight,
                            width: cellWidth,
                            height: cellHeight
                        )
                        let path = Path(rectangle)
                        context.fill(path, with: .color(color(for: map.environmentID(longitude: longitudeIndex, latitude: latitudeIndex))))
                        context.stroke(path, with: .color(.black.opacity(0.18)), lineWidth: 0.5)
                    }
                }

                func point(_ position: ZoneVector) -> CGPoint? {
                    guard let unit = map.unitPosition(for: position) else { return nil }
                    return CGPoint(x: unit.x * size.width, y: unit.y * size.height)
                }

                for poi in map.pointsOfInterest {
                    guard let center = point(poi.position) else { continue }
                    let marker = CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)
                    context.fill(Path(ellipseIn: marker), with: .color(.yellow))
                    context.stroke(Path(ellipseIn: marker), with: .color(.black), lineWidth: 1)
                    if zoom > 1.25 {
                        context.draw(
                            Text(poi.name).font(.caption2).foregroundStyle(.white),
                            at: CGPoint(x: center.x + 8, y: center.y - 8),
                            anchor: .bottomLeading
                        )
                    }
                }

                for node in snapshot.collectionNodes {
                    guard let center = point(node.position) else { continue }
                    let radius: CGFloat = node.id == selectedNodeID ? 11 : 7
                    let marker = CGRect(x: center.x - radius, y: center.y - radius,
                                        width: radius * 2, height: radius * 2)
                    context.fill(
                        Path(ellipseIn: marker),
                        with: .color(node.available ? .green : .gray.opacity(0.55))
                    )
                    context.stroke(Path(ellipseIn: marker), with: .color(.white), lineWidth: 1)
                }

                for entity in snapshot.visibleEntities where entity.kind == .npc {
                    guard let center = point(entity.position) else { continue }
                    let radius: CGFloat = entity.id == selectedEntityID ? 12 : 8
                    let marker = CGRect(x: center.x - radius, y: center.y - radius,
                                        width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: marker), with: .color(.purple.opacity(0.85)))
                    // Dashed outline marks inferred NPC placement; collection
                    // spawns use exact server data and get a solid outline.
                    context.stroke(
                        Path(ellipseIn: marker),
                        with: .color(entity.isInferredPosition ? .yellow : .white),
                        style: StrokeStyle(lineWidth: 1.5, dash: entity.isInferredPosition ? [3, 2] : [])
                    )
                }

                if let playerPosition = point(ZoneVector(
                    x: Double(snapshot.player.x),
                    y: Double(snapshot.player.y),
                    z: Double(snapshot.player.z),
                    w: 0
                )) {
                    let halo = CGRect(x: playerPosition.x - 13, y: playerPosition.y - 13, width: 26, height: 26)
                    context.fill(Path(ellipseIn: halo), with: .color(.white.opacity(0.25)))
                    let body = CGRect(x: playerPosition.x - 6, y: playerPosition.y - 6, width: 12, height: 12)
                    context.fill(Path(ellipseIn: body), with: .color(.blue))
                    context.stroke(Path(ellipseIn: body), with: .color(.white), lineWidth: 1.5)
                }

                if let destinationUnit,
                   let target = point(map.worldPosition(unitX: destinationUnit.x, unitY: destinationUnit.y)) {
                    let ring = CGRect(x: target.x - 16, y: target.y - 16, width: 32, height: 32)
                    context.stroke(
                        Path(ellipseIn: ring),
                        with: .color(.cyan),
                        style: StrokeStyle(lineWidth: 2, dash: [4, 3])
                    )
                }
            }
            .frame(width: mapSide * CGFloat(zoom), height: mapSide * CGFloat(zoom))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let scaledSide = mapSide * CGFloat(zoom)
                        let unitX = Double(value.location.x / scaledSide)
                        let unitY = Double(value.location.y / scaledSide)
                        guard let walkable = map.walkableUnit(near: unitX, unitY: unitY) else {
                            errorMessage = "That tile is outside the walkable grid."
                            return
                        }
                        destinationUnit = walkable
                        selectedDestination = nil
                        errorMessage = nil
                    }
            )
        }
        .background(Color.black.opacity(0.75))
    }

    private func hud(simulation: WorldSimulation, snapshot: WorldSnapshot) -> some View {
        let map = simulation.worldMap
        let playerTile = map.tile(for: ZoneVector(
            x: Double(snapshot.player.x),
            y: Double(snapshot.player.y),
            z: Double(snapshot.player.z),
            w: 0
        ))
        let environment = map.environmentName(id: map.environmentID(
            longitude: playerTile.longitude,
            latitude: playerTile.latitude
        ))

        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.playerName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("\(snapshot.zoneName) · \(environment)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                Text("Tile (\(playerTile.longitude), \(playerTile.latitude)) · \(snapshot.movementTicks) ticks/s · \(snapshot.secondTicks)s")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                Text("\(simulation.player.coins) coins · \(simulation.player.inventory.count) items")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(10)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))

            if let node = snapshot.collectionNodes.first(where: { $0.id == selectedNodeID }) {
                interactionCard(
                    title: node.name.isEmpty ? node.poolKey : node.name,
                    subtitle: node.available
                        ? "Exact spawn · \(node.poolKey) · range \(node.interactRange)"
                        : "Respawning in \(node.respawnTicksRemaining) ticks",
                    buttonTitle: node.available ? "Gather" : nil
                ) {
                    simulation.interactWithCollectionNode(id: node.id)
                    refresh(simulation: simulation)
                }
            }

            if let entity = snapshot.visibleEntities.first(where: { $0.id == selectedEntityID }) {
                interactionCard(
                    title: entity.name,
                    subtitle: entity.isInferredPosition
                        ? "Inferred NPC position · \(entity.positionSource)"
                        : "Exact non-player spawn · model \(entity.modelID)",
                    buttonTitle: "Talk"
                ) {
                    simulation.talkToNPC(definitionID: entity.definitionID)
                    refresh(simulation: simulation)
                }
            }

            if let point = selectedDestination {
                interactionCard(
                    title: point.name,
                    subtitle: point.atlasName.isEmpty ? "Atlas destination" : "Atlas: \(point.atlasName)",
                    buttonTitle: "Travel Here"
                ) {
                    travel(to: point)
                }
            }

            if let active = snapshot.quests.first(where: { !$0.progress.completed }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quest: \(active.name)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    if active.totalGoalCount > 0 {
                        Text("\(active.completedGoalCount)/\(active.totalGoalCount) goals")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(8)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .frame(maxWidth: 300, alignment: .leading)
    }

    private func interactionCard(
        title: String,
        subtitle: String,
        buttonTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
            if let buttonTitle {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: 280, alignment: .leading)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
    }

    private var destinationsSheet: some View {
        NavigationStack {
            List {
                ForEach(simulation?.worldMap.pointsOfInterest ?? []) { point in
                    Button {
                        travel(to: point)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(point.name)
                                .font(.headline)
                            Text(point.atlasName.isEmpty ? "Atlas destination" : "Atlas: \(point.atlasName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Destinations")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingDestinations = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var entitiesSheet: some View {
        NavigationStack {
            List {
                if let snapshot {
                    Section("Visible NPCs") {
                        ForEach(snapshot.visibleEntities.filter { $0.kind == .npc }) { entity in
                            Button {
                                selectedEntityID = entity.id
                                selectedNodeID = nil
                                showingEntities = false
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entity.name)
                                    Text(entity.isInferredPosition
                                         ? "Inferred: \(entity.positionSource)"
                                         : "Exact spawn: \(entity.positionSource)")
                                        .font(.caption)
                                        .foregroundStyle(entity.isInferredPosition ? .orange : .secondary)
                                }
                            }
                        }
                    }
                    Section("Collection Nodes") {
                        ForEach(snapshot.collectionNodes) { node in
                            Button {
                                selectedNodeID = node.id
                                selectedEntityID = nil
                                showingEntities = false
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(node.name.isEmpty ? node.poolKey : node.name)
                                    Text(node.available
                                         ? "Available · \(node.position.x), \(node.position.z)"
                                         : "Respawning in \(node.respawnTicksRemaining) ticks")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Entities")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingEntities = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var journalSheet: some View {
        NavigationStack {
            List {
                if let snapshot {
                    Section("Active") {
                        ForEach(snapshot.quests.filter { !$0.progress.completed }, id: \.questID) { quest in
                            VStack(alignment: .leading) {
                                Text(quest.name)
                                    .font(.headline)
                                Text("\(quest.completedGoalCount)/\(quest.totalGoalCount) goals")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("Completed") {
                        ForEach(snapshot.quests.filter { $0.progress.completed }, id: \.questID) { quest in
                            Text(quest.name)
                        }
                    }
                } else {
                    Text("No quest data loaded.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Journal")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingQuests = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Game state

    private func load() {
        guard let root = AppPaths.bundledSanctuaryResources else {
            errorMessage = "Sanctuary resources are not bundled in this build."
            return
        }
        do {
            let loadedSession = try LocalSession(
                directory: AppPaths.root.appendingPathComponent("Offline", isDirectory: true)
            )
            var configuration = LocalHostConfiguration()
            configuration.locale = state.settings.locale
            let bootstrapped = try loadedSession.bootstrapOffline(
                configuration: configuration,
                password: "offline"
            )
            let inWorld = bootstrapped.isInWorld ? bootstrapped : try loadedSession.enterWorld()
            let loadedSimulation = try WorldSimulation(
                rootURL: root,
                zoneName: nil,
                character: inWorld,
                session: loadedSession
            )
            simulation = loadedSimulation
            snapshot = loadedSimulation.snapshot
            lastTick = Date()
            errorMessage = nil
            state.notify("Entered \(loadedSimulation.snapshot.zoneName) as \(inWorld.name).")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func advance() {
        guard let simulation else { return }
        let now = Date()
        let delta = min(max(now.timeIntervalSince(lastTick), 0), 1)
        lastTick = now

        if let destinationUnit {
            let target = simulation.worldMap.worldPosition(
                unitX: destinationUnit.x,
                unitY: destinationUnit.y
            )
            let player = ZoneVector(
                x: Double(simulation.snapshot.player.x),
                y: Double(simulation.snapshot.player.y),
                z: Double(simulation.snapshot.player.z),
                w: 0
            )
            let remaining = hypot(target.x - player.x, target.z - player.z)
            simulation.stepPlayer(toward: target, deltaTime: delta)
            if remaining <= 0.5 || remaining <= WorldSimulation.onFootMovementSpeed * delta {
                self.destinationUnit = nil
            }
        }

        simulation.update(deltaTime: delta)
        snapshot = simulation.snapshot
    }

    private func refresh(simulation: WorldSimulation) {
        snapshot = simulation.snapshot
    }

    private func travel(to point: WorldPointOfInterest) {
        guard let simulation else { return }
        let preferred = simulation.worldMap.unitPosition(for: point.spawnPosition)
            ?? simulation.worldMap.unitPosition(for: point.position)
        guard let preferred,
              let walkable = simulation.worldMap.walkableUnit(near: preferred.x, unitY: preferred.y)
        else {
            errorMessage = "\(point.name) is outside this zone's walkable grid."
            showingDestinations = false
            return
        }
        destinationUnit = walkable
        selectedDestination = point
        selectedEntityID = nil
        selectedNodeID = nil
        errorMessage = nil
        showingDestinations = false
    }

    private func recenter() {
        guard let simulation else { return }
        let spawn = simulation.worldMap.zone.spawnPosition
        guard let unit = simulation.worldMap.unitPosition(for: spawn) else { return }
        if simulation.movePlayer(to: spawn) {
            destinationUnit = nil
            selectedDestination = nil
            snapshot = simulation.snapshot
        } else if let walkable = simulation.worldMap.walkableUnit(near: unit.x, unitY: unit.y) {
            destinationUnit = walkable
            snapshot = simulation.snapshot
        }
    }

    private func color(for environmentID: Int) -> Color {
        if environmentID == -1 { return .black }
        let palette: [Color] = [
            .brown, .green, .blue, .purple, .orange, .teal,
            .mint, .indigo, .yellow, .pink, .cyan, .red
        ]
        return palette[abs(environmentID) % palette.count].opacity(0.55)
    }
}
