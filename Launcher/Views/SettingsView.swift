import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

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

                Section("About") {
                    Text("Native iOS port of the OSFR Launcher. Server management, downloads, and account access are supported; launching the desktop game is not possible on iOS.")
                    Text("Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }
}
