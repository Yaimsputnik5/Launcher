import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingAddServer = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                List {
                    ForEach(state.runtimes) { runtime in
                        NavigationLink(value: runtime.id) {
                            ServerRow(runtime: runtime)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                state.deleteServer(runtime)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .overlay {
                    if state.runtimes.isEmpty {
                        ContentUnavailableView(
                            "No Servers",
                            systemImage: "server.rack",
                            description: Text("Add a Free Realms server URL to begin.")
                        )
                    }
                }
                .navigationTitle("OSFR Launcher")
                .navigationDestination(for: UUID.self) { id in
                    if let runtime = state.runtime(with: id) {
                        ServerDetailView(runtime: runtime)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingAddServer = true
                        } label: {
                            Label("Add Server", systemImage: "plus")
                        }
                    }
                }

                if !state.notifications.isEmpty {
                    NoticeOverlay(notices: state.notifications)
                        .padding(.bottom, 12)
                        .zIndex(1)
                }
            }
        }
        .sheet(isPresented: $showingAddServer) {
            AddServerView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

private struct ServerRow: View {
    @ObservedObject var runtime: ServerRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(runtime.info.name)
                    .font(.headline)
                Spacer()
                StatusBadge(status: runtime.status)
            }
            Text(runtime.info.url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !runtime.statusMessage.isEmpty {
                Text(runtime.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(runtime.lastError == nil ? .secondary : .red)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
