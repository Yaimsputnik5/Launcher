import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingAddServer = false
    @State private var showingSettings = false
    @State private var selection = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                NavigationStack {
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
                    .navigationTitle("Launcher")
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
                }
                .tabItem {
                    Label("Launcher", systemImage: "server.rack")
                }
                .tag(0)

                PlayOfflineView()
                    .tabItem {
                        Label("Play Offline", systemImage: "gamecontroller")
                    }
                    .tag(1)

                Group {
                    if state.canOpenWorld {
                        GamePlayerView()
                    } else {
                        WorldUnavailableView()
                    }
                }
                .tabItem {
                    Label("World", systemImage: "map.fill")
                }
                .tag(2)

                JoinServerView()
                    .tabItem {
                        Label("Join Server", systemImage: "network")
                    }
                    .tag(3)

                DownloadsView()
                    .tabItem {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }
                    .tag(4)

                DiagnosticsView()
                    .tabItem {
                        Label("Diagnostics", systemImage: "wrench.and.screwdriver")
                    }
                    .tag(5)
            }

            if !state.notifications.isEmpty {
                NoticeOverlay(notices: state.notifications)
                    .padding(.bottom, 12)
                    .zIndex(1)
            }
        }
        .sheet(isPresented: $showingAddServer) {
            AddServerView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .osfrShowOfflineTab)) { _ in
            selection = 1
        }
    }
}

/// A non-fake placeholder. It contains no characters, zone state, or tickets;
/// it exists only to explain why World is unavailable.
private struct WorldUnavailableView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("No Active World", systemImage: "map.fill")
            } description: {
                if state.remoteSession != nil && state.gatewaySession == nil {
                    Text("Sign in and choose Join World on a server, or start an Offline game. A login session alone is not a world.")
                } else {
                    Text("Start an Offline game or join a server before opening World. No world data is preloaded.")
                }
            } actions: {
                Button("Play Offline") {
                    NotificationCenter.default.post(name: .osfrShowOfflineTab, object: nil)
                }
                .buttonStyle(.borderedProminent)
            }
            .navigationTitle("World")
        }
    }
}

extension Notification.Name {
    static let osfrShowOfflineTab = Notification.Name("osfrShowOfflineTab")
}
