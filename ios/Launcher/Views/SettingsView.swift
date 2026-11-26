import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var clientReadiness = ClientAssetStore.shared.availability()
    @State private var sanctuaryReadiness = SanctuaryResourceStore.shared.readiness()

    private var maxThreads: Int { max(2, ProcessInfo.processInfo.activeProcessorCount) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Downloads") {
                    Picker("Download threads", selection: Binding(
                        get: { state.settings.downloadThreads },
                        set: { state.setDownloadThreads($0) }
                    )) {
                        ForEach(2...maxThreads, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                }

                Section("Game") {
                    Picker("Game language", selection: Binding(
                        get: { state.settings.locale },
                        set: { state.setLocale($0) }
                    )) {
                        ForEach(GameLocale.allCases) { locale in
                            Text(locale.displayName).tag(locale)
                        }
                    }
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
                    Text("Native iOS OSFR app. Server management, downloads, and account access are available while the all-in-one world engine is being ported.")
                    Text("Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .task {
                clientReadiness = ClientAssetStore.shared.availability()
                sanctuaryReadiness = SanctuaryResourceStore.shared.readiness()
            }
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }
}
