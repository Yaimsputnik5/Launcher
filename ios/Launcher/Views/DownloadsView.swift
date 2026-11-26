import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var state: AppState
    @State private var readiness = ClientAssetStore.shared.availability()
    @State private var report = AssetVerificationReport()
    @State private var isVerifying = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Embedded Payload") {
                    LabeledContent("Status") {
                        if readiness.hasClientManifest {
                            Text("\(readiness.bundledClientFileCount) files · \(readiness.clientBytesDescription)")
                        } else {
                            Text("No embedded index")
                        }
                    }
                    Button {
                        Task { await verifyAssets() }
                    } label: {
                        Label("Verify XXH64 hashes", systemImage: "checkmark.shield")
                    }
                    .disabled(!readiness.hasClientManifest || isVerifying)

                    if isVerifying {
                        ProgressView("Verifying \(readiness.bundledClientFileCount) files…")
                    } else if report.checked > 0 {
                        LabeledContent("Verified", value: "\(report.verified)/\(report.checked)")
                        if !report.isFullyVerified {
                            Text("Missing: \(report.missing.count) · Mismatched: \(report.mismatched.count)")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("Server Downloads") {
                    ForEach(state.runtimes) { runtime in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(runtime.info.name)
                                Spacer()
                                if runtime.isDownloading {
                                    ProgressView(value: runtime.downloadProgress)
                                        .frame(width: 80)
                                }
                            }
                            Text(runtime.downloadedFileName.isEmpty
                                 ? "Download / verify client files when needed."
                                 : runtime.downloadedFileName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Prepare Client") {
                                Task { await runtime.prepareForDesktopPlay() }
                            }
                            .disabled(runtime.isDownloading)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Downloads")
            .task {
                readiness = ClientAssetStore.shared.availability()
            }
        }
    }

    private func verifyAssets() async {
        guard !isVerifying else { return }
        isVerifying = true
        defer { isVerifying = false }
        let result = await Task.detached(priority: .utility) {
            ClientAssetStore.shared.verify()
        }.value
        report = result
    }
}
