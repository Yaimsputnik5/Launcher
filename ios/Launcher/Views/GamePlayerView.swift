import Foundation
import SwiftUI

/// UI-side owner of the native engine. It does not create sessions or fabricate
/// characters: it can only attach to the `ActiveWorldSession` stored by AppState.
@MainActor
final class GameEngineController: ObservableObject {
    @Published private(set) var simulation: WorldSimulation?
    @Published private(set) var snapshot: WorldSnapshot?
    @Published private(set) var frame: EngineFrame?
    @Published private(set) var errorMessage: String?

    private var engine: OSFREngine?
    private var remoteZoneName: String?

    var isLoaded: Bool { engine != nil }

    func attach(session: LocalSession, configuration: LocalHostConfiguration) {
        guard !isLoaded else { return }
        guard let root = AppPaths.bundledSanctuaryResources else {
            errorMessage = "Sanctuary resources are not bundled in this build."
            return
        }
        do {
            let simulation = try WorldSimulation(
                rootURL: root,
                zoneID: configuration.startingZoneID,
                character: session.selectedCharacter,
                session: session,
                hostConfiguration: configuration
            )
            let objectCatalog = ClientChunkCatalog.loadFabledRealms()
            let engine = OSFREngine(
                simulation: simulation,
                clientObjectCatalog: objectCatalog
            )
            self.simulation = simulation
            self.snapshot = simulation.snapshot
            self.frame = engine.frame
            self.engine = engine
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Attaches a packet-driven remote presentation. The underlying simulation
    /// is used only for the real Sanctuary zone grid; its local player, NPCs and
    /// collection nodes are never published in remote mode. The zone comes from
    /// the decoded `PacketSendZoneDetails`; no zone is chosen locally when the
    /// server has supplied one.
    func attachRemote(session: ActiveWorldSession, observation: GatewayWorldObservation) {
        guard !isLoaded else { return }
        guard let root = AppPaths.bundledSanctuaryResources else {
            errorMessage = "Sanctuary resources are not bundled in this build."
            return
        }
        do {
            let catalog = try ResourceCatalog(rootURL: root)
            guard let serverZone = observation.zoneName,
                  let resolvedZone = catalog.zoneName(matching: serverZone)
            else {
                errorMessage = "Awaiting a server zone packet."
                return
            }
            let simulation = try WorldSimulation(rootURL: root, zoneName: resolvedZone)
            let engine = OSFREngine(
                simulation: simulation,
                presentationMode: .remote,
                selfGUID: session.configuration.gatewayGUID
            )
            self.simulation = nil
            self.snapshot = nil
            self.frame = engine.frame
            self.engine = engine
            remoteZoneName = resolvedZone
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Rebuilds the packet map if a later zone packet changes the server zone.
    func syncRemoteZone(session: ActiveWorldSession, observation: GatewayWorldObservation) {
        guard let serverZone = observation.zoneName else { return }
        guard let root = AppPaths.bundledSanctuaryResources else { return }
        let resolved = (try? ResourceCatalog(rootURL: root))?.zoneName(matching: serverZone)
        guard let resolved, resolved != remoteZoneName else { return }
        reset()
        attachRemote(session: session, observation: observation)
        if let engine {
            engine.applyRemoteObservation(observation)
            publish(engine)
        }
    }

    func applyRemoteObservation(_ observation: GatewayWorldObservation) {
        guard let engine else { return }
        engine.applyRemoteObservation(observation)
        publish(engine)
    }

    func reset() {
        engine = nil
        simulation = nil
        snapshot = nil
        frame = nil
        remoteZoneName = nil
        errorMessage = nil
    }

    func advance() {
        guard let engine else { return }
        engine.advance()
        publish(engine)
    }

    func send(_ event: EngineInputEvent) {
        guard let engine else { return }
        engine.handle(event)
        publish(engine)
    }

    private func publish(_ engine: OSFREngine) {
        frame = engine.frame
        snapshot = engine.presentationMode == .remote ? nil : engine.simulation.snapshot
    }
}

/// Native in-process world player backed by Sanctuary data and the OSFR engine.
/// It never bootstraps a private offline session; World is only reachable after
/// AppState has an actual offline or remote session.
struct GamePlayerView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var controller = GameEngineController()
    @State private var selectedEntityID: UInt64?
    @State private var selectedNodeID: Int?
    @State private var selectedDestination: WorldPointOfInterest?
    @State private var showingQuests = false
    @State private var showingDestinations = false
    @State private var showingEntities = false
    @State private var loadedSessionID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if let session = state.activeSession, session.mode == .offline {
                    offlineWorld(session: session)
                } else if let session = state.activeSession, session.mode == .remote {
                    RemoteWorldView(session: session)
                } else {
                    ContentUnavailableView(
                        "No Active World",
                        systemImage: "map.fill",
                        description: Text("Start an Offline game or join a server first. World data is not preloaded.")
                    )
                }
            }
            .navigationTitle("World")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func offlineWorld(session: ActiveWorldSession) -> some View {
        Group {
            if let frame = controller.frame, let snapshot = controller.snapshot {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        MetalWorldView(frame: frame)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onEnded { value in
                                        controller.send(.moveTo(
                                            unitX: value.location.x / max(geometry.size.width, 1),
                                            unitY: value.location.y / max(geometry.size.height, 1)
                                        ))
                                        selectedDestination = nil
                                    }
                            )

                        hud(snapshot: snapshot)
                            .frame(maxWidth: 320, alignment: .topLeading)

                        if let errorMessage = controller.errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(8)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                .padding()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            if let zoneStatus = controller.frame?.zoneStatus {
                                Text(zoneStatus)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            }
                            if let objectStatus = controller.frame?.clientObjectStatus {
                                Text(objectStatus)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            }
                            if let textureStatus = controller.frame?.textureStatus {
                                Text(textureStatus)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }
            } else if let errorMessage = controller.errorMessage {
                ContentUnavailableView(
                    "World Unavailable",
                    systemImage: "map",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView("Loading world…")
            }
        }
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
                        controller.send(.zoom(1.25))
                    } label: {
                        Label("Zoom In", systemImage: "plus.magnifyingglass")
                    }
                    Button {
                        controller.send(.zoom(0.8))
                    } label: {
                        Label("Zoom Out", systemImage: "minus.magnifyingglass")
                    }
                    Button {
                        controller.send(.recenter())
                    } label: {
                        Label("Return to Spawn", systemImage: "scope")
                    }
                    Button(role: .destructive) {
                        state.leaveOfflineWorld()
                        controller.reset()
                    } label: {
                        Label("Leave World", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingQuests) { journalSheet }
        .sheet(isPresented: $showingDestinations) { destinationsSheet }
        .sheet(isPresented: $showingEntities) { entitiesSheet }
        .task {
            guard loadedSessionID != session.id,
                  let localSession = state.localSession,
                  let configuration = session.hostConfiguration
            else { return }
            controller.attach(session: localSession, configuration: configuration)
            loadedSessionID = session.id
        }
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
            controller.advance()
        }
    }

    // MARK: - HUD

    private func hud(snapshot: WorldSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.playerName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Profile: \(snapshot.profileName) · \(snapshot.locale.displayName)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                Text("\(snapshot.zoneName) · zone \(snapshot.zoneID)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                Text("\(snapshot.coins) coins · \(snapshot.stationCash) station cash · \(controller.simulation?.player.inventory.count ?? 0) items")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                Text("Profiles \(snapshot.availableProfileIDs.count) · Titles \(snapshot.availableTitleIDs.count) · Tiles \(snapshot.options.unlockAllTiles ? "unlocked" : "server grid")")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                Text("\(snapshot.movementTicks) movement ticks · \(snapshot.secondTicks)s · \(snapshot.options.unlockAllProfiles ? "all profiles" : "starter profile") · \(snapshot.options.unlockAllTitles ? "all titles" : "starter title")")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(10)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))

            if let node = snapshot.collectionNodes.first(where: { $0.id == selectedNodeID }) {
                interactionCard(
                    title: node.name.isEmpty ? node.poolKey : node.name,
                    subtitle: node.available
                        ? "Exact spawn · \(node.poolKey) · range \(node.interactRange)"
                        : "Respawning in \(node.respawnTicksRemaining) ticks",
                    buttonTitle: node.available ? "Gather" : nil
                ) {
                    controller.send(.interactCollection(id: node.id))
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
                    controller.send(.talkToNPC(definitionID: entity.definitionID))
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
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
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
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Sheets

    private var destinationsSheet: some View {
        NavigationStack {
            List {
                ForEach(controller.simulation?.worldMap.pointsOfInterest ?? []) { point in
                    Button {
                        travel(to: point)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(point.name).font(.headline)
                            Text(point.atlasName.isEmpty ? "Atlas destination" : "Atlas: \(point.atlasName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Destinations")
            .toolbar {
                Button("Done") { showingDestinations = false }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var entitiesSheet: some View {
        NavigationStack {
            List {
                if let snapshot = controller.snapshot {
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
                Button("Done") { showingEntities = false }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var journalSheet: some View {
        NavigationStack {
            List {
                if let snapshot = controller.snapshot {
                    Section("Active") {
                        ForEach(snapshot.quests.filter { !$0.progress.completed }, id: \.questID) { quest in
                            VStack(alignment: .leading) {
                                Text(quest.name).font(.headline)
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
                    Text("No quest data loaded.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Journal")
            .toolbar {
                Button("Done") { showingQuests = false }
            }
        }
        .presentationDetents([.medium])
    }

    private func travel(to point: WorldPointOfInterest) {
        controller.send(.travelToPOI(id: point.id))
        selectedDestination = point
        selectedEntityID = nil
        selectedNodeID = nil
        showingDestinations = false
    }
}

/// Remote worlds are real gateway connections, not local simulations. The map
/// grid comes from Sanctuary resources; every marker and chat row comes from a
/// decoded gateway world packet.
private struct RemoteWorldView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var controller = GameEngineController()
    @State private var loadedSessionID: UUID?
    @State private var chatText = ""
    @State private var chatChannel: GatewayChatMessage.Channel = .worldSay
    @State private var tellRecipient = ""
    @State private var areaNameID: Int32 = 0
    @State private var outboundError: String?
    let session: ActiveWorldSession

    private var observation: GatewayWorldObservation { state.worldObservation }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                packetMap
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Character", value: session.displayName)
                    LabeledContent("Server", value: session.configuration.host ?? "unknown")
                    LabeledContent("Gateway", value: session.configuration.gatewayAddress ?? "unknown")
                    LabeledContent("Status", value: state.gatewayStatus)
                    LabeledContent("Locale", value: session.configuration.locale.displayName)
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Gateway packet view")
                        .font(.headline)
                    Text(controller.frame?.worldStatus
                         ?? observation.lastEvent
                         ?? "Waiting for the first world packet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(observation.positionCount) position updates · \(observation.chatCount) chat messages")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if observation.chatMessages.isEmpty {
                        Text("No server chat received yet.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(observation.chatMessages.suffix(4)) { message in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(message.fromName)
                                    .font(.caption2.weight(.semibold))
                                Text(message.message)
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                Text("Markers appear only after position packets arrive; names only after spawn packets. Local simulation entities are deliberately hidden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Outbound Packets")
                        .font(.headline)
                    Picker("Channel", selection: $chatChannel) {
                        ForEach(GatewayChatMessage.Channel.allCases) { channel in
                            Text(channel.displayName).tag(channel)
                        }
                    }
                    if chatChannel == .tell {
                        TextField("Recipient", text: $tellRecipient)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if chatChannel == .worldArea {
                        Stepper("Area name ID: \(areaNameID)", value: $areaNameID, in: 0...Int32.max)
                    }
                    TextField("Message", text: $chatText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { sendChatPacket() }
                    HStack {
                        Button("Send Chat") { sendChatPacket() }
                        Button("Sync Time") { sendTimeSync() }
                    }
                    HStack {
                        Button("Move +X") { sendMove(dx: 1, dz: 0) }
                        Button("Move -X") { sendMove(dx: -1, dz: 0) }
                        Button("Move +Z") { sendMove(dx: 0, dz: 1) }
                        Button("Move -Z") { sendMove(dx: 0, dz: -1) }
                    }
                    Button("Jump") { sendJump() }
                    if let outboundError {
                        Text(outboundError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                Button("Leave World", role: .destructive) {
                    state.disconnectGateway()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .task {
            guard loadedSessionID != session.id else { return }
            controller.attachRemote(session: session, observation: observation)
            controller.applyRemoteObservation(observation)
            loadedSessionID = session.id
        }
        .onReceive(state.$worldObservation) { observation in
            controller.syncRemoteZone(session: session, observation: observation)
            controller.applyRemoteObservation(observation)
        }
    }

    @ViewBuilder
    private var packetMap: some View {
        if let frame = controller.frame {
            MetalWorldView(frame: frame)
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    if let error = controller.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
        } else if let error = controller.errorMessage {
            ContentUnavailableView(
                "Packet Map Unavailable",
                systemImage: "network.slash",
                description: Text(error)
            )
            .frame(height: 320)
        } else {
            ProgressView("Loading packet map…")
                .frame(height: 320)
        }
    }

    private var selfGUID: UInt64? {
        observation.playerGUID ?? session.configuration.gatewayGUID
    }

    private var selfPosition: GatewayVector4 {
        guard let selfGUID, let entry = observation.positions[selfGUID] else {
            return GatewayVector4(x: 0, y: 0, z: 0, w: 1)
        }
        return GatewayVector4(
            x: Float(entry.position.x),
            y: Float(entry.position.y),
            z: Float(entry.position.z),
            w: 1
        )
    }

    private var selfRotation: GatewayVector3 {
        guard let selfGUID, let entry = observation.positions[selfGUID] else {
            return GatewayVector3(x: 0, y: 0, z: 0)
        }
        return GatewayVector3(
            x: Float(entry.rotation.x),
            y: Float(entry.rotation.y),
            z: Float(entry.rotation.z)
        )
    }

    private func recipientName() -> GatewayName {
        let parts = tellRecipient.trimmingCharacters(in: .whitespaces)
            .split(maxSplits: 1, omittingEmptySubsequences: false) { $0.isWhitespace }
            .map(String.init)
        return GatewayName(
            firstNameID: 0,
            lastNamePrefixID: 0,
            lastNameSuffixID: 0,
            firstName: parts.first ?? "",
            lastName: parts.count > 1 ? parts[1] : ""
        )
    }

    private func sendChatPacket() {
        guard !chatText.isEmpty else { return }
        guard let gateway = state.gatewaySession else {
            outboundError = "The gateway is not connected."
            return
        }
        do {
            try gateway.sendChat(
                channel: chatChannel,
                message: chatText,
                toName: recipientName(),
                position: selfPosition,
                areaNameID: chatChannel == .worldArea ? areaNameID : nil
            )
            chatText = ""
            outboundError = nil
        } catch {
            outboundError = error.localizedDescription
        }
    }

    private func sendTimeSync() {
        guard let gateway = state.gatewaySession else {
            outboundError = "The gateway is not connected."
            return
        }
        let minutes = Int32(TimeZone.current.secondsFromGMT() / 60)
        let unixSeconds = Int64(Date().timeIntervalSince1970)
        let gameTime = 8 * (unixSeconds - 1_221_361_670) - Int64(minutes)
        do {
            try gateway.sendGameTimeSync(time: gameTime, serverRate: 8, useClientTime: false)
            outboundError = nil
        } catch {
            outboundError = error.localizedDescription
        }
    }

    private func sendMove(dx: Float, dz: Float) {
        guard let gateway = state.gatewaySession, let guid = selfGUID else {
            outboundError = "The gateway is not connected or no self packet has arrived."
            return
        }
        let position = GatewayVector3(
            x: selfPosition.x + dx,
            y: selfPosition.y,
            z: selfPosition.z + dz
        )
        do {
            let sequence = observation.ownTeleportSequence
                ?? observation.positions[guid]?.teleportSequence
                ?? 0
            try gateway.sendPositionUpdate(
                guid: guid,
                position: position,
                rotation: selfRotation,
                state: 1,
                teleportSequence: sequence
            )
            if sequence != 0 { state.consumeTeleportSequence() }
            try gateway.sendCameraUpdate(position: position, rotation: selfRotation)
            outboundError = nil
        } catch {
            outboundError = error.localizedDescription
        }
    }

    private func sendJump() {
        guard let gateway = state.gatewaySession, let guid = selfGUID else {
            outboundError = "The gateway is not connected or no self packet has arrived."
            return
        }
        do {
            let sequence = observation.ownTeleportSequence
                ?? observation.positions[guid]?.teleportSequence
                ?? 0
            try gateway.sendJumpUpdate(
                guid: guid,
                position: GatewayVector3(
                    x: selfPosition.x,
                    y: selfPosition.y,
                    z: selfPosition.z
                ),
                rotation: selfRotation,
                state: 0x02,
                teleportSequence: sequence,
                verticalVelocity: 6
            )
            if sequence != 0 { state.consumeTeleportSequence() }
            outboundError = nil
        } catch {
            outboundError = error.localizedDescription
        }
    }
}
