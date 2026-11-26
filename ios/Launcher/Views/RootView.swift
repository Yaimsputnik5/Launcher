import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingAddServer = false
    @State private var showingSettings = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
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

                PlayOfflineView()
                    .tabItem {
                        Label("Play Offline", systemImage: "gamecontroller")
                    }

                GamePlayerView()
                    .tabItem {
                        Label("World", systemImage: "map.fill")
                    }

                JoinServerView()
                    .tabItem {
                        Label("Join Server", systemImage: "network")
                    }

                DownloadsView()
                    .tabItem {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }

                DiagnosticsView()
                    .tabItem {
                        Label("Diagnostics", systemImage: "wrench.and.screwdriver")
                    }
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
    }
}
