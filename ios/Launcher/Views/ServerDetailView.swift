import SwiftUI
import UIKit

struct ServerDetailView: View {
    @ObservedObject var runtime: ServerRuntime
    @EnvironmentObject private var state: AppState
    @Environment(\.openURL) private var openURL

    @State private var showingLogin = false
    @State private var showingClientReady = false
    @State private var confirmingDelete = false
    @State private var shareItem: ShareItem?

    private var description: AttributedString {
        var rich = (try? AttributedString(
            markdown: runtime.info.descriptionText,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(runtime.info.descriptionText)
        for run in rich.runs {
            if let link = run.link {
                guard let components = URLComponents(url: link, resolvingAgainstBaseURL: false),
                      let scheme = components.scheme?.lowercased(),
                      scheme == "https" || scheme == "http"
                else {
                    rich[run.range].link = nil
                }
            }
        }
        return rich
    }

    var body: some View {
        Form {
            Section("Status") {
                HStack {
                    StatusBadge(state: runtime.presentationState)
                    Spacer()
                    if runtime.isRefreshing {
                        ProgressView()
                    }
                }
                Text(runtime.statusText)
                    .font(.subheadline)
                if runtime.info.isBootstrapOnly {
                    Text("Using preset endpoints — refresh failed. The saved record is not live manifest data.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button("Refresh") {
                    Task { await runtime.refresh() }
                }
                .disabled(runtime.isRefreshing)
            }

            Section("About") {
                Text(description)
                    .font(.body)
                    .textSelection(.enabled)
                if let url = URL(string: runtime.info.url), url.scheme?.lowercased() == "https" || url.scheme?.lowercased() == "http" {
                    Button("Open Server Website") { openURL(url) }
                }
                if isInsecureEndpoint(runtime.info.webAPIURL) {
                    InsecureEndpointWarning()
                }
            }

            Section("Client Files") {
                Button {
                    Task {
                        if await runtime.prepareForDesktopPlay() {
                            showingClientReady = true
                        }
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
                if !runtime.taskStatusMessage.isEmpty {
                    Text(runtime.taskStatusMessage)
                        .font(.caption)
                        .foregroundStyle(runtime.lastError == nil ? Color.secondary : Color.red)
                }
                if let folder = try? AppPaths.clientDirectory(runtime.info) {
                    Button("Share Client Folder") { shareItem = ShareItem(url: folder) }
                }
                Text("Downloads are stored in the app sandbox and consumed by the native World tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Account") {
                Button("Sign In") { showingLogin = true }
                    .disabled(runtime.presentationState != .online)
                if runtime.presentationState != .online {
                    Text("Sign in is available when the server is online.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if runtime.info.rememberUsername && !runtime.info.username.isEmpty {
                    Text("Remembered user: \(runtime.info.username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let session = state.remoteSession, session.host == runtime.info.loginServer {
                    LabeledContent("Game Session") {
                        Text(session.mode == .remote ? "Ready" : "Local")
                    }
                }
            }

            Section {
                Button("Delete Server", role: .destructive) { confirmingDelete = true }
                    .disabled(runtime.isDownloading)
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
        .sheet(isPresented: $showingClientReady) {
            ClientReadySheet(runtime: runtime)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
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

struct ClientReadySheet: View {
    let runtime: ServerRuntime
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("Client Files Verified")
                    .font(.title2.bold())
                Text("All files for \(runtime.info.name) are current. The native World tab reads them directly from the app sandbox.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if let url = URL(string: runtime.info.url), url.scheme == "https" || url.scheme == "http" {
                    Link("Open Server Website", destination: url)
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Client Ready")
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }
}

private struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
