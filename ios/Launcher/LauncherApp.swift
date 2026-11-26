import SwiftUI

@main
struct LauncherApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        for runtime in state.runtimes where !runtime.isRefreshing {
                            await runtime.refresh()
                        }
                    }
                }
        }
    }
}
