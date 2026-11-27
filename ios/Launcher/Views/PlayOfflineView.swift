import SwiftUI

struct PlayOfflineView: View {
    @EnvironmentObject private var state: AppState
    @State private var password = ""
    @State private var readiness = ClientAssetStore.shared.availability()
    @State private var sanctuaryReadiness = SanctuaryResourceStore.shared.readiness()
    @State private var sessionMessage = "No offline session started."
    @State private var sessionError: String?
    @State private var zoneIDs: [Int] = []

    /// The global game language is part of the effective offline configuration;
    /// host fields must not silently overwrite it.
    private var configuration: LocalHostConfiguration { state.effectiveHostConfiguration() }
    private var zoneChoices: [Int] {
        Set(zoneIDs).union([configuration.startingZoneID]).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Embedded Client") {
                    LabeledContent("Payload") {
                        if readiness.hasClientManifest {
                            Text("\(readiness.bundledClientFileCount) files · \(readiness.clientBytesDescription)")
                        } else {
                            Text("Not embedded")
                        }
                    }
                    LabeledContent("Sanctuary data") {
                        if sanctuaryReadiness.hasSanctuaryManifest {
                            Text("\(sanctuaryReadiness.sanctuaryFileCount) files · \(sanctuaryReadiness.sanctuaryBytesDescription)")
                        } else {
                            Text("Not embedded")
                        }
                    }
                    Text("Offline play runs Sanctuary-compatible game logic in-process. No Windows executable is launched.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Local Profile") {
                    TextField("Profile name", text: state.hostBinding(\.profileName))
                    TextField("Player name", text: state.hostBinding(\.playerName))
                    SecureField("Choose an offline password", text: $password)
                    Picker("Starting zone", selection: state.hostBinding(\.startingZoneID)) {
                        ForEach(zoneChoices, id: \.self) { zoneID in
                            Text(String(zoneID)).tag(zoneID)
                        }
                    }
                    Toggle("Unlock all profiles", isOn: state.hostBinding(\.unlockAllProfiles))
                    Toggle("Unlock all titles", isOn: state.hostBinding(\.unlockAllTitles))
                    Toggle("Unlock all map tiles", isOn: state.hostBinding(\.unlockAllTiles))
                    Text("These values are persisted in AppSettings and applied to the offline character and engine.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Session") {
                    if let active = state.activeSession, active.mode == .offline {
                        LabeledContent("Status", value: "In world")
                        LabeledContent("Profile", value: active.configuration.profileName ?? active.configuration.username)
                        LabeledContent("Character", value: active.displayName)
                        LabeledContent("Zone", value: String((active.hostConfiguration ?? configuration).startingZoneID))
                        LabeledContent("Coins", value: String((active.hostConfiguration ?? configuration).startingCoins))
                        Button("Leave World", role: .destructive) {
                            state.leaveOfflineWorld()
                            sessionMessage = "Left the offline world."
                        }
                    } else {
                        Button {
                            startOfflineSession()
                        } label: {
                            Label("Start Offline Game", systemImage: "play.fill")
                        }
                        .disabled(!canStart)
                    }
                    Text(sessionMessage)
                        .font(.caption)
                        .foregroundStyle(sessionError == nil ? Color.secondary : Color.red)
                }
            }
            .navigationTitle("Play Offline")
            .task {
                readiness = ClientAssetStore.shared.availability()
                sanctuaryReadiness = SanctuaryResourceStore.shared.readiness()
                zoneIDs = (try? ResourceCatalog.bundled())?.zones.map(\.id).sorted() ?? []
            }
        }
    }

    private var canStart: Bool {
        readiness.hasClientManifest
            && sanctuaryReadiness.hasSanctuaryManifest
            && !configuration.profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !configuration.playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && zoneIDs.contains(configuration.startingZoneID)
    }

    private func startOfflineSession() {
        do {
            let directory = AppPaths.root.appendingPathComponent("Offline", isDirectory: true)
            let session = try LocalSession(directory: directory)
            let bootstrapped = try session.bootstrapOffline(configuration: configuration, password: password)
            let character = bootstrapped.isInWorld ? bootstrapped : try session.enterWorld()
            state.startOfflineWorld(
                session: session,
                configuration: configuration,
                character: character
            )
            sessionError = nil
            sessionMessage = "Entered \(character.name) in zone \(character.zoneID). World is now available."
            state.notify("Offline game started for \(character.name).")
        } catch {
            sessionError = error.localizedDescription
            sessionMessage = "Could not start the offline game."
        }
    }
}
