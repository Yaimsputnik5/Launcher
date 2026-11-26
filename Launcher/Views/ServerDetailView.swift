import SwiftUI

struct ServerDetailView: View {
    @ObservedObject var runtime: ServerRuntime
    @EnvironmentObject private var state: AppState
    @Environment(\.openURL) private var openURL

    @State private var showingLogin = false
    @State private var showingDesktopOnly = false
    @State private var confirmingDelete = false

    var body: some View {
        Form {
            Section("Status") {
                HStack {
                    StatusBadge(status: runtime.status)
                    Spacer()
                    if runtime.isRefreshing {
                        ProgressView()
                    }
                }
                Text(runtime.statusMessage.isEmpty ? "No status received yet." : runtime.statusMessage)
                    .font(.subheadline)
                Button("Refresh") {
                    Task { await runtime.refresh() }
                }
                .disabled(runtime.isRefreshing)
            }

            Section("About") {
                Text(runtime.info.descriptionText.isEmpty ? "No description provided." : runtime.info.descriptionText)
                    .font(.body)
                    .textSelection(.enabled)
                if let url = URL(string: runtime.info.url), url.scheme?.lowercased() == "https" || url.scheme?.lowercased() == "http" {
                    Button("Open Server Website") { openURL(url) }
                }
                if runtime.info.webAPIURL.lowercased().hasPrefix("http://") {
                    InsecureEndpointWarning()
                }
            }

            Section("Client Files") {
                Button {
                    Task {
                        await runtime.prepareForDesktopPlay()
                        showingDesktopOnly = true
                    }
                } label: {
                    Label("Download / Verify Client", systemImage: "arrow.down.to.line")
                }
                .disabled(runtime.isDownloading)

                if runtime.isDownloading {
                    ProgressView(value: runtime.downloadProgress)
                    Text(runtime.downloadedFileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Downloads are stored in the app sandbox. This build cannot launch \(AppConstants.desktopExecutable).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Account") {
                Button("Sign In") { showingLogin = true }
                if runtime.info.rememberUsername && !runtime.info.username.isEmpty {
                    Text("Remembered user: \(runtime.info.username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Delete Server", role: .destructive) { confirmingDelete = true }
            }
        }
        .navigationTitle(runtime.info.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await runtime.refresh()
        }
        .sheet(isPresented: $showingLogin) {
            LoginView(runtime: runtime)
        }
        .sheet(isPresented: $showingDesktopOnly) {
            DesktopOnlySheet(runtime: runtime)
        }
        .alert("Delete \(runtime.info.name)?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                state.deleteServer(runtime)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The saved client files and remembered password for this server will be removed.")
        }
    }
}

struct DesktopOnlySheet: View {
    let runtime: ServerRuntime
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("Desktop Game Required")
                    .font(.title2.bold())
                Text("Client files are managed, but iOS cannot execute \(AppConstants.desktopExecutable) or Wine. Open the server website on a Windows, macOS, or Linux computer to play.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if let url = URL(string: runtime.info.loginServer), url.scheme != nil {
                    Link("Open Game Website", destination: url)
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Not Available on iOS")
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }
}
