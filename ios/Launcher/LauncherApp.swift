import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
struct LauncherApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .onAppear {
                    applyDownloadGuard()
                }
                .onChange(of: state.hasActiveDownloads) { _, isDownloading in
                    applyDownloadGuard()
                    if !isDownloading {
                        #if canImport(UIKit)
                        DownloadLifecycleGuard.shared.endBackgroundTask()
                        #endif
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        #if canImport(UIKit)
                        DownloadLifecycleGuard.shared.endBackgroundTask()
                        #endif
                        Task {
                            for runtime in state.runtimes where !runtime.isRefreshing {
                                await runtime.refresh()
                            }
                        }
                    case .background:
                        guard state.hasActiveDownloads else { return }
                        // The C# launcher cancels window closing and shows this
                        // exact message. iOS cannot cancel termination, so it
                        // keeps the screen on, asks for background time, and
                        // shows the same warning when the app is foregrounded.
                        state.notify("Cannot close the launcher while downloading.", isError: true)
                        #if canImport(UIKit)
                        DownloadLifecycleGuard.shared.beginBackgroundTaskIfNeeded()
                        #endif
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }

    private func applyDownloadGuard() {
        #if canImport(UIKit)
        DownloadLifecycleGuard.shared.setDownloadsActive(state.hasActiveDownloads)
        #endif
    }
}

#if canImport(UIKit)
/// iOS counterpart to Avalonia's `OnClosing` download guard. The app cannot
/// refuse the OS home gesture or an app switch, but it can prevent the screen
/// from sleeping and request extra time to finish an in-flight client download.
@MainActor
final class DownloadLifecycleGuard {
    static let shared = DownloadLifecycleGuard()

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    func setDownloadsActive(_ active: Bool) {
        UIApplication.shared.isIdleTimerDisabled = active
        if !active { endBackgroundTask() }
    }

    func beginBackgroundTaskIfNeeded() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "OSFR client download"
        ) { [weak self] in
            Task { @MainActor in
                self?.endBackgroundTask()
            }
        }
    }

    func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        let task = backgroundTask
        backgroundTask = .invalid
        UIApplication.shared.endBackgroundTask(task)
    }
}
#endif
