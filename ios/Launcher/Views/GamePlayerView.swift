import SwiftUI

/// A native, in-process world player. It renders the bundled Sanctuary zone
/// grid and destinations, and drives a persisted offline character around the
/// world. No desktop executable or external process is involved.
struct GamePlayerView: View {
    @EnvironmentObject private var state: AppState
    @State private var map: WorldMap?
    @State private var session: LocalSession?
    @State private var character: LocalCharacter?
    @State private var player: (x: Double, y: Double) = (0.5, 0.5)
    @State private var destination: (x: Double, y: Double)?
    @State private var selectedDestination: WorldPointOfInterest?
    @State private var errorMessage: String?
    @State private var zoom: Double = 1
    @State private var showingQuests = false
    @State private var showingDestinations = false

    private let mapSide: CGFloat = 1024

    var body: some View {
        NavigationStack {
            Group {
                if let map {
                    GeometryReader { geometry in
                        ZStack(alignment: .topLeading) {
                            worldCanvas(map: map)
                            hud(map: map)
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
            .task {
                load()
            }
            .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
                advance()
            }
        }
    }

    // MARK: - World rendering

    private func worldCanvas(map: WorldMap) -> some View {
        ScrollView([.horizontal, .vertical]) {
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

                let gridWidth = size.width
                let gridHeight = size.height
                for point in map.pointsOfInterest {
                    guard let unit = map.unitPosition(for: point.position) else { continue }
                    let center = CGPoint(x: unit.x * gridWidth, y: unit.y * gridHeight)
                    let marker = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
                    context.fill(Path(ellipseIn: marker), with: .color(.yellow))
                    context.stroke(Path(ellipseIn: marker), with: .color(.black), lineWidth: 1)
                    if zoom > 1.25 {
                        context.draw(
                            Text(point.name).font(.caption2).foregroundStyle(.white),
                            at: CGPoint(x: center.x + 7, y: center.y - 7),
                            anchor: .bottomLeading
                        )
                    }
                }

                let playerCenter = CGPoint(x: player.x * gridWidth, y: player.y * gridHeight)
                let halo = CGRect(x: playerCenter.x - 12, y: playerCenter.y - 12, width: 24, height: 24)
                context.fill(Path(ellipseIn: halo), with: .color(.white.opacity(0.25)))
                let body = CGRect(x: playerCenter.x - 6, y: playerCenter.y - 6, width: 12, height: 12)
                context.fill(Path(ellipseIn: body), with: .color(.blue))
                context.stroke(Path(ellipseIn: body), with: .color(.white), lineWidth: 1.5)
            }
            .frame(width: mapSide * zoom, height: mapSide * zoom)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard let map else { return }
                        let unitX = Double(value.location.x / (mapSide * zoom))
                        let unitY = Double(value.location.y / (mapSide * zoom))
                        if let walkable = map.walkableUnit(near: unitX, unitY: unitY) {
                            destination = walkable
                            selectedDestination = nil
                        }
                    }
            )
        }
        .background(Color.black.opacity(0.75))
    }

    private func hud(map: WorldMap) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(character?.name ?? "Adventurer")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("\(map.zone.name) · \(currentEnvironmentName(map: map))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                if let character {
                    Text("\(character.coins) coins · \(character.inventory.count) items")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(10)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))

            if let point = selectedDestination {
                VStack(alignment: .leading, spacing: 6) {
                    Text(point.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(point.atlasName.isEmpty ? "Atlas destination" : "Atlas: \(point.atlasName)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.75))
                    Button("Travel Here") {
                        travel(to: point)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(10)
                .frame(maxWidth: 240, alignment: .leading)
                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            }

        }
        .padding(12)
        .frame(maxWidth: 280, alignment: .leading)
    }

    private var destinationsSheet: some View {
        NavigationStack {
            List {
                ForEach(map?.pointsOfInterest ?? []) { point in
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

    private var journalSheet: some View {
        NavigationStack {
            List {
                if let character {
                    Section("Active Quest") {
                        ForEach(character.quests.filter { !$0.completed }) { quest in
                            VStack(alignment: .leading) {
                                Text("Quest \(quest.questID)")
                                    .font(.headline)
                                Text("Goal \(quest.currentGoalID)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("Completed") {
                        ForEach(character.quests.filter(\.completed)) { quest in
                            Text("Quest \(quest.questID)")
                        }
                    }
                } else {
                    Text("No character loaded.")
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
            let loadedMap = try WorldMapLoader.load(rootURL: root)
            map = loadedMap

            let loadedSession = try LocalSession(
                directory: AppPaths.root.appendingPathComponent("Offline", isDirectory: true)
            )
            let configuration = LocalHostConfiguration()
            let bootstrapped = try loadedSession.bootstrapOffline(
                configuration: configuration,
                password: "offline"
            )
            let inWorld = bootstrapped.isInWorld ? bootstrapped : try loadedSession.enterWorld()
            session = loadedSession
            character = inWorld

            let position = ZoneVector(
                x: Double(inWorld.position.x),
                y: Double(inWorld.position.y),
                z: Double(inWorld.position.z),
                w: 0
            )
            player = loadedMap.unitPosition(for: position)
                ?? loadedMap.unitPosition(for: loadedMap.zone.spawnPosition)
                ?? (0.5, 0.5)
            errorMessage = nil
            state.notify("Entered \(loadedMap.zone.name) as \(inWorld.name).")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func advance() {
        guard let map, let session, let destination else { return }
        let deltaX = destination.x - player.x
        let deltaY = destination.y - player.y
        let distance = hypot(deltaX, deltaY)
        guard distance > 0.002 else {
            player = destination
            let world = map.worldPosition(unitX: destination.x, unitY: destination.y)
            let position = LocalWorldPosition(
                x: Float(world.x),
                y: Float(world.y),
                z: Float(world.z),
                rotationX: character?.position.rotationX ?? 0,
                rotationZ: character?.position.rotationZ ?? 0
            )
            do {
                try session.movePlayer(to: position)
                character?.position = position
            } catch {
                errorMessage = error.localizedDescription
            }
            self.destination = nil
            return
        }
        let step = min(0.008, distance * 0.08)
        player = (
            player.x + deltaX / distance * step,
            player.y + deltaY / distance * step
        )
    }

    private func travel(to point: WorldPointOfInterest) {
        selectedDestination = point
        showingDestinations = false
        guard let map else { return }
        let preferred = map.unitPosition(for: point.spawnPosition)
            ?? map.unitPosition(for: point.position)
        if let preferred, let walkable = map.walkableUnit(near: preferred.x, unitY: preferred.y) {
            destination = walkable
            errorMessage = nil
        } else {
            errorMessage = "\(point.name) is outside this zone's walkable grid."
        }
    }

    private func recenter() {
        guard let map,
              let unit = map.unitPosition(for: ZoneVector(
                x: map.zone.spawnPosition.x,
                y: map.zone.spawnPosition.y,
                z: map.zone.spawnPosition.z,
                w: map.zone.spawnPosition.w
              ))
        else { return }
        destination = unit
        selectedDestination = nil
    }

    private func currentEnvironmentName(map: WorldMap) -> String {
        let longitude = Int(player.y * Double(max(map.longitudeCount, 1)))
        let latitude = Int(player.x * Double(max(map.latitudeCount, 1)))
        return map.environmentName(id: map.environmentID(longitude: longitude, latitude: latitude))
    }

    private func color(for environmentID: Int) -> Color {
        switch environmentID {
        case -1: return Color(red: 0.08, green: 0.10, blue: 0.14)
        case 0: return .gray.opacity(0.45)
        case 1: return Color(red: 0.62, green: 0.80, blue: 0.92)
        case 2: return Color(red: 0.36, green: 0.64, blue: 0.35)
        case 3, 58: return Color(red: 0.78, green: 0.68, blue: 0.38)
        case 6, 11: return Color(red: 0.32, green: 0.72, blue: 0.76)
        case 10, 70: return Color(red: 0.52, green: 0.36, blue: 0.58)
        case 12: return Color(red: 0.84, green: 0.50, blue: 0.42)
        case 56, 82: return Color(red: 0.45, green: 0.42, blue: 0.68)
        case 71: return Color(red: 0.80, green: 0.55, blue: 0.78)
        case 83: return Color(red: 0.90, green: 0.78, blue: 0.50)
        default:
            return Color(
                hue: Double(abs(environmentID) % 17) / 17,
                saturation: 0.48,
                brightness: 0.72
            )
        }
    }
}
