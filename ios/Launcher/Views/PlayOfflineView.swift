import SwiftUI

struct PlayOfflineView: View {
    @EnvironmentObject private var state: AppState
    @State private var configuration = LocalHostConfiguration()
    @State private var password = "offline"
    @State private var readiness = ClientAssetStore.shared.availability()
    @State private var sanctuaryReadiness = SanctuaryResourceStore.shared.readiness()
    @State private var session: LocalSession?
    @State private var sessionMessage = "No offline session started."
    @State private var sessionError: String?

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
                    TextField("Account", text: $configuration.accountName)
                    TextField("Character", text: $configuration.characterName)
                    SecureField("Offline password", text: $password)
                    Stepper("Starting zone: \(configuration.startingZoneID)", value: $configuration.startingZoneID, in: 1...999)
                    Toggle("Unlock all profiles", isOn: $configuration.unlockAllProfiles)
                    Toggle("Unlock all titles", isOn: $configuration.unlockAllTitles)
                    Text("The password is stored as a salted PBKDF2-SHA256 hash in the app sandbox.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Session") {
                    Button {
                        startOfflineSession()
                    } label: {
                        Label("Start Offline Session", systemImage: "play.fill")
                    }
                    .disabled(!canStart)

                    if let session {
                        LabeledContent("Account", value: session.activeAccount?.username ?? "none")
                        LabeledContent("Character", value: session.selectedCharacter?.name ?? "none")
                        LabeledContent("Zone", value: String(session.selectedCharacter?.zoneID ?? 0))
                        LabeledContent("Coins", value: String(session.selectedCharacter?.coins ?? 0))
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
                configuration.locale = state.settings.locale
            }
        }
    }

    private var canStart: Bool {
        readiness.hasClientManifest
            && sanctuaryReadiness.hasSanctuaryManifest
            && !configuration.accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !configuration.characterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    private func startOfflineSession() {
        do {
            let directory = AppPaths.root.appendingPathComponent("Offline", isDirectory: true)
            let session = try LocalSession(directory: directory)
            let character = try session.bootstrapOffline(configuration: configuration, password: password)
            self.session = session
            sessionError = nil
            sessionMessage = "Loaded \(character.name) in zone \(character.zoneID)."
            state.notify("Offline session ready for \(character.name).")
        } catch {
            sessionError = error.localizedDescription
            sessionMessage = "Could not start the offline session."
        }
    }
}
