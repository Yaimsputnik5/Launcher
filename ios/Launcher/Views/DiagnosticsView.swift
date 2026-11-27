import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var state: AppState
    @State private var clientReadiness = ClientAssetStore.shared.availability()
    @State private var sanctuaryReadiness = SanctuaryResourceStore.shared.readiness()

    var body: some View {
        NavigationStack {
            Form {
                Section("Bundles") {
                    LabeledContent("Client manifest") {
                        Text(clientReadiness.hasClientManifest ? "Present" : "Missing")
                    }
                    LabeledContent("Client files") {
                        Text("\(clientReadiness.bundledClientFileCount) · \(clientReadiness.clientBytesDescription)")
                    }
                    LabeledContent("Sanctuary manifest") {
                        Text(sanctuaryReadiness.hasSanctuaryManifest ? "Present" : "Missing")
                    }
                    LabeledContent("Sanctuary files") {
                        Text("\(sanctuaryReadiness.sanctuaryFileCount) · \(sanctuaryReadiness.sanctuaryBytesDescription)")
                    }
                }

                Section("Security") {
                    Label("Manifest paths are contained to the app sandbox.", systemImage: "lock.shield")
                    Label("Downloads are hashed before replace.", systemImage: "checkmark.seal")
                    Label("No Windows executable or process launch is used.", systemImage: "nosign")
                }

                Section("Runtime") {
                    LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "unknown")
                    LabeledContent("OS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                    LabeledContent("Servers", value: "\(state.runtimes.count)")
                }

                Section("Log") {
                    if let log = LaunchLog.shared.read(), !log.isEmpty {
                        ScrollView {
                            Text(log)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 200)
                    } else {
                        Text("No log entries yet.")
                            .foregroundStyle(.secondary)
                    }
                    ShareLink("Share Logs", items: LaunchLog.shared.exportURLs())
                        .disabled(LaunchLog.shared.exportURLs().isEmpty)
                }
            }
            .navigationTitle("Diagnostics")
            .task {
                clientReadiness = ClientAssetStore.shared.availability()
                sanctuaryReadiness = SanctuaryResourceStore.shared.readiness()
            }
        }
    }
}
