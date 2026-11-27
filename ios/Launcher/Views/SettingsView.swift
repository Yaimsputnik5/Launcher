import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var clientReadiness = ClientAssetStore.shared.availability()
    @State private var sanctuaryReadiness = SanctuaryResourceStore.shared.readiness()
    @State private var zoneIDs: [Int] = []

    private var maxThreads: Int { max(2, ProcessInfo.processInfo.activeProcessorCount) }
    private var zoneChoices: [Int] {
        Set(zoneIDs).union([state.settings.hostConfiguration.startingZoneID]).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Downloads") {
                    Toggle("Parallel downloads", isOn: Binding(
                        get: { state.settings.parallelDownloads },
                        set: { state.setParallelDownloads($0) }
                    ))
                    Picker("Download threads", selection: Binding(
                        get: { state.settings.downloadThreads },
                        set: { state.setDownloadThreads($0) }
                    )) {
                        ForEach(2...maxThreads, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                }

                Section("Servers") {
                    Button("Restore Public OSFR Server") {
                        Task {
                            do {
                                try await state.restoreDefaultServer()
                            } catch {
                                state.notify("Could not restore the public server: \(error.localizedDescription)", isError: true)
                            }
                        }
                    }
                    Text("The launcher ships with https://opensourcefreerealms.com and loads its name and endpoints from servermanifest.xml.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Game") {
                    Picker("Game language", selection: Binding(
                        get: { state.settings.locale },
                        set: { state.setLocale($0) }
                    )) {
                        ForEach(GameLocale.selectable) { locale in
                            Text(locale.displayName).tag(locale)
                        }
                    }
                }

                Section("Offline Host") {
                    TextField("Profile name", text: state.hostBinding(\.profileName))
                    TextField("Player name", text: state.hostBinding(\.playerName))
                    Picker("Starting zone", selection: state.hostBinding(\.startingZoneID)) {
                        ForEach(zoneChoices, id: \.self) { zoneID in
                            Text(String(zoneID)).tag(zoneID)
                        }
                    }
                    Toggle("Unlock all profiles", isOn: state.hostBinding(\.unlockAllProfiles))
                    Toggle("Unlock all titles", isOn: state.hostBinding(\.unlockAllTitles))
                    Toggle("Unlock all map tiles", isOn: state.hostBinding(\.unlockAllTiles))
                    Stepper(
                        "Starting coins: \(state.settings.hostConfiguration.startingCoins)",
                        value: state.hostBinding(\.startingCoins),
                        in: 0...Int64.max
                    )
                    Stepper(
                        "Starting station cash: \(state.settings.hostConfiguration.startingStationCash)",
                        value: state.hostBinding(\.startingStationCash),
                        in: 0...Int64.max
                    )
                    Text("Applied to the next Offline game and to the selected offline character.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Embedded Content") {
                    LabeledContent("Client payload") {
                        if clientReadiness.hasClientManifest {
                            Text("\(clientReadiness.bundledClientFileCount) files · \(clientReadiness.clientBytesDescription)")
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
                    Text("The native world engine consumes these bundles; no Windows executable is run on iOS.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    Text("Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let url = URL(string: "https://github.com/YaimSputnik5/Launcher/releases/tag/ios-ipa") {
                        Link("Release Notes & IPA", destination: url)
                    }
                    Text("Native iOS OSFR app with embedded client data, offline host/play, and Sanctuary-compatible server joining.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .task {
                clientReadiness = ClientAssetStore.shared.availability()
                sanctuaryReadiness = SanctuaryResourceStore.shared.readiness()
                zoneIDs = (try? ResourceCatalog.bundled())?.zones.map(\.id).sorted() ?? []
            }
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }
}
