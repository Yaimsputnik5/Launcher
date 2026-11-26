import Foundation
import OSLog
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    private static let logger = Logger(subsystem: "dev.opensourcefreerealms.launcher", category: "notifications")

    @Published private(set) var settings: AppSettings
    @Published private(set) var runtimes: [ServerRuntime] = []
    @Published private(set) var remoteSession: WorldSessionConfiguration?
    @Published private(set) var gatewaySession: GatewayUDPSession?
    @Published private(set) var gatewayStatus = "Not connected"
    @Published var notifications: [AppNotice] = []

    init() {
        let loaded = AppSettings.load()
        settings = loaded
        runtimes = loaded.servers.map { ServerRuntime(info: $0) }
        for runtime in runtimes { runtime.state = self }

        if loaded.servers.isEmpty && !loaded.didSeedDefaultServers {
            // Install the bundled preset synchronously so the public server is
            // always visible, then replace its details with the live manifest.
            var preset = DefaultServer.info()
            preset.isBootstrapOnly = true
            settings.didSeedDefaultServers = true
            settings.servers = [preset]
            let presetRuntime = ServerRuntime(info: preset)
            presetRuntime.state = self
            runtimes = [presetRuntime]
            persistSettings()
            Task { await presetRuntime.refresh() }
        }
    }

    func runtime(with id: UUID) -> ServerRuntime? {
        runtimes.first { $0.id == id }
    }

    func addServer(urlString: String) async throws {
        let base = try URLHelper.baseURL(urlString)
        let normalized = base.absoluteString
        guard !settings.servers.contains(where: {
            (try? URLHelper.baseURL($0.url).absoluteString) == normalized
        }) else {
            throw LauncherError.malformedManifest("That server has already been added.")
        }

        let manifest = try await HTTPClient.shared.serverManifest(
            from: URLHelper.joining(base, AppConstants.serverManifestFile)
        )
        let info = ServerInfo.make(
            url: normalized,
            name: manifest.name,
            description: manifest.descriptionText,
            webAPIURL: manifest.webAPIURL,
            loginServer: manifest.loginServer
        )
        settings.servers.append(info)
        let runtime = ServerRuntime(info: info)
        runtime.state = self
        runtimes.append(runtime)
        persistSettings()
        notify("Added \(info.name).")
    }

    func deleteServer(_ runtime: ServerRuntime) {
        guard !runtime.isDownloading else {
            notify("Wait for the download to finish before deleting \(runtime.info.name).", isError: true)
            return
        }
        guard
            let runtimeIndex = runtimes.firstIndex(where: { $0.id == runtime.id }),
            let settingsIndex = settings.servers.firstIndex(where: { $0.id == runtime.id })
        else { return }
        let info = settings.servers[settingsIndex]
        CredentialStore.shared.delete(for: info.id)
        if let directory = try? AppPaths.serverDirectory(info) {
            try? FileManager.default.removeItem(at: directory)
        }
        runtimes.remove(at: runtimeIndex)
        settings.servers.remove(at: settingsIndex)
        if remoteSession?.host == info.loginServer {
            remoteSession = nil
            disconnectGateway()
        }
        persistSettings()
        notify("Deleted \(info.name).")
    }

    func update(_ info: ServerInfo) {
        guard let index = settings.servers.firstIndex(where: { $0.id == info.id }) else { return }
        settings.servers[index] = info
        persistSettings()
    }

    func setDownloadThreads(_ value: Int) {
        settings.downloadThreads = max(2, value)
        persistSettings()
    }

    func setParallelDownloads(_ enabled: Bool) {
        settings.parallelDownloads = enabled
        persistSettings()
    }

    /// Sessions are kept in memory only, matching the C# launcher's decision
    /// not to persist launch tickets passwords or tokens.
    func setRemoteSession(_ configuration: WorldSessionConfiguration) {
        remoteSession = configuration
        gatewaySession = nil
        gatewayStatus = "Not connected"
    }

    /// Opens the gateway UDP connection with the ticket returned by Sanctuary's
    /// character login handler. This does not fabricate a world state: it
    /// establishes the real transport and sends the documented client hello.
    func joinRemoteWorld() async {
        guard let session = remoteSession, session.canJoinGateway else {
            notify("Sign in completely before joining the world.", isError: true)
            return
        }
        guard let address = session.gatewayAddress,
              let guid = session.gatewayGUID,
              let ticket = session.ticket
        else { return }

        gatewayStatus = "Connecting…"
        do {
            let gateway = try await GatewayUDPSession.connect(
                address: address,
                ticket: ticket,
                guid: guid,
                version: session.gatewayVersion ?? GatewayUDPSession.defaultClientVersion
            )
            try gateway.sendInitialPackets(locale: session.locale)
            gatewaySession = gateway
            gatewayStatus = "Connected as \(session.characterName ?? "character")"
            notify("Joined \(address).")
        } catch {
            gatewayStatus = "Failed: \(error.localizedDescription)"
            notify("Gateway join failed: \(error.localizedDescription)", isError: true)
        }
    }

    func disconnectGateway() {
        gatewaySession?.close()
        gatewaySession = nil
        gatewayStatus = "Not connected"
    }

    func setLocale(_ locale: GameLocale) {
        settings.locale = locale
        persistSettings()
    }

    func notify(_ message: String, isError: Bool = false) {
        if isError {
            Self.logger.error("\(message, privacy: .public)")
        } else {
            Self.logger.info("\(message, privacy: .public)")
        }
        let notice = AppNotice(message: message, isError: isError)
        notifications.append(notice)
        if notifications.count > 3 {
            notifications.removeFirst(notifications.count - 3)
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self else { return }
            withAnimation { self.notifications.removeAll { $0.id == notice.id } }
        }
    }

    func persistSettings() {
        do {
            try settings.save()
        } catch {
            notify("Could not save settings: \(error.localizedDescription)", isError: true)
        }
    }

    /// Re-adds the bundled preset if the user has removed every server and asks
    /// to restore it from Settings. Existing lists are never overwritten.
    func restoreDefaultServer() async throws {
        if settings.servers.contains(where: { $0.id == DefaultServer.id }) {
            notify("The public server is already in your list.")
            return
        }
        var preset = DefaultServer.info()
        preset.isBootstrapOnly = true
        settings.servers.append(preset)
        let runtime = ServerRuntime(info: preset)
        runtime.state = self
        runtimes.append(runtime)
        persistSettings()
        notify("Restored \(preset.name).")
        await runtime.refresh()
    }
}

@MainActor
final class ServerRuntime: ObservableObject, Identifiable {
    let id: UUID

    @Published var info: ServerInfo
    @Published var status: ServerStatus?
    @Published var presentationState: ServerPresentationState = .unknown
    @Published var statusText = "Offline"
    @Published var taskStatusMessage = ""
    @Published var lastError: String?
    @Published var isRefreshing = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var downloadedFileName = ""

    weak var state: AppState?

    init(info: ServerInfo) {
        self.id = info.id
        self.info = info
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        presentationState = .refreshing
        statusText = "Refreshing…"
        defer { isRefreshing = false }

        do {
            let base = try URLHelper.baseURL(info.url)
            let manifest = try await HTTPClient.shared.serverManifest(
                from: URLHelper.joining(base, AppConstants.serverManifestFile)
            )
            var updated = info
            updated.name = manifest.name
            updated.descriptionText = manifest.descriptionText
            updated.webAPIURL = manifest.webAPIURL
            updated.loginServer = manifest.loginServer
            updated.isBootstrapOnly = false
            info = updated
            state?.update(updated)

            let queried = await ServerStatusClient.query(address: updated.loginServer)
            status = queried
            if let queried, queried.online {
                if queried.joining {
                    presentationState = .locked
                    statusText = "Server is locked"
                } else {
                    presentationState = .online
                    statusText = "\(queried.onlinePlayers) players online"
                }
            } else {
                presentationState = .offline
                statusText = "Server is offline or unreachable"
            }
        } catch {
            lastError = error.localizedDescription
            status = nil
            if case LauncherError.unsupportedManifestVersion = error {
                presentationState = .unsupported
            } else {
                presentationState = .error
            }
            statusText = "Could not refresh server: \(error.localizedDescription)"
            if info.isBootstrapOnly {
                taskStatusMessage = "Using preset endpoints — refresh failed."
            }
            state?.notify("Could not refresh \(info.name): \(error.localizedDescription)", isError: true)
        }
    }

    /// Downloads and verifies all client files. Returns true only when every
    /// planned file is current and verified, matching C# play gating.
    @discardableResult
    func prepareForDesktopPlay() async -> Bool {
        guard !isDownloading else { return false }
        isDownloading = true
        lastError = nil
        downloadProgress = 0
        defer {
            isDownloading = false
            downloadedFileName = ""
        }

        do {
            let base = try URLHelper.baseURL(info.url)
            let manifest = try await HTTPClient.shared.clientManifest(
                from: URLHelper.joining(base, AppConstants.clientManifestFile)
            )
            let locale = state?.settings.locale ?? .en_US
            guard manifest.languages.contains(locale) else {
                let supported = manifest.languages.map(\.displayName).joined(separator: ", ")
                let message = "Language \(locale.displayName) is not available on this server. Supported: \(supported.isEmpty ? "none" : supported)."
                taskStatusMessage = message
                state?.notify(message, isError: true)
                return false
            }

            var items: [DownloadItem] = []
            let clientRoot = try AppPaths.clientDirectory(info)
            try collect(folder: manifest.rootFolder, components: [], base: base, clientRoot: clientRoot, into: &items)

            guard !items.isEmpty else {
                taskStatusMessage = "The client manifest contains no files."
                state?.notify("The client manifest contains no files.", isError: true)
                return false
            }

            let fm = FileManager.default
            var planned: [DownloadItem] = []
            for item in items {
                if fileIsCurrent(item, using: fm) { continue }
                planned.append(item)
            }

            if planned.isEmpty {
                downloadProgress = 1
                taskStatusMessage = "All \(items.count) client files are up to date."
                return true
            }

            taskStatusMessage = "Preparing \(planned.count) of \(items.count) client files…"
            let results: [DownloadResult]
            if state?.settings.parallelDownloads == true {
                let limit = max(1, state?.settings.downloadThreads ?? 2)
                results = await runParallel(planned, limit: limit)
            } else {
                var sequential: [DownloadResult] = []
                for (index, item) in planned.enumerated() {
                    downloadedFileName = item.file.name
                    let error = await Self.download(
                        item,
                        index: index,
                        total: planned.count
                    ) { [weak self] fraction in
                        Task { @MainActor in self?.setProgress(index: index, fraction: fraction, total: planned.count) }
                    }
                    sequential.append(DownloadResult(index: index, name: item.file.name, error: error))
                }
                results = sequential
            }

            let failures = results.filter { $0.error != nil }
            downloadProgress = 1
            if failures.isEmpty {
                taskStatusMessage = "Client files are ready. The native world engine uses these files."
                state?.notify("Downloaded \(planned.count) client files.")
                return true
            }

            let names = failures.prefix(10).map(\.name).joined(separator: ", ")
            let suffix = failures.count > 10 ? " …and \(failures.count - 10) more" : ""
            taskStatusMessage = "\(failures.count) file(s) failed: \(names)\(suffix)"
            state?.notify(taskStatusMessage, isError: true)
            return false
        } catch {
            lastError = error.localizedDescription
            taskStatusMessage = "Download failed: \(error.localizedDescription)"
            state?.notify("Download failed: \(error.localizedDescription)", isError: true)
            return false
        }
    }

    private func setProgress(index: Int, fraction: Double, total: Int) {
        guard total > 0 else { return }
        downloadProgress = min(1, max(0, (Double(index) + fraction) / Double(total)))
    }

    private func runParallel(_ items: [DownloadItem], limit: Int) async -> [DownloadResult] {
        await withTaskGroup(of: DownloadResult.self) { group in
            var iterator = items.makeIterator()
            var active = 0
            var nextIndex = 0
            var results: [DownloadResult] = []

            func enqueueNext() {
                while active < limit, let item = iterator.next() {
                    let index = nextIndex
                    nextIndex += 1
                    group.addTask {
                        let error = await Self.download(
                            item,
                            index: index,
                            total: items.count
                        ) { fraction in
                            Task { @MainActor in
                                self.setProgress(index: index, fraction: fraction, total: items.count)
                            }
                        }
                        return DownloadResult(index: index, name: item.file.name, error: error)
                    }
                    active += 1
                }
            }

            enqueueNext()
            for await result in group {
                active -= 1
                results.append(result)
                await MainActor.run {
                    self.downloadedFileName = result.name
                    self.downloadProgress = Double(results.count) / Double(max(1, items.count))
                }
                enqueueNext()
            }
            return results
        }
    }

    private static func download(
        _ item: DownloadItem,
        index: Int,
        total: Int,
        progress: @escaping (Double) -> Void
    ) async -> String? {
        _ = index
        _ = total
        var lastError: String?
        for attempt in 1...5 {
            do {
                try await HTTPClient.shared.downloadFile(
                    from: item.remoteURL,
                    to: item.localURL,
                    expectedSize: item.file.size,
                    expectedHash: item.file.hash,
                    progress: progress
                )
                return nil
            } catch {
                lastError = error.localizedDescription
                if attempt < 5 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 200_000_000)
                }
            }
        }
        return lastError ?? "Unknown download error"
    }

    private struct DownloadItem {
        let file: ClientFile
        let localURL: URL
        let remoteURL: URL
    }

    private struct DownloadResult {
        let index: Int
        let name: String
        let error: String?
    }

    private func collect(folder: ClientFolder,
                         components: [String],
                         base: URL,
                         clientRoot: URL,
                         into items: inout [DownloadItem]) throws {
        // Published manifests use an unnamed root <Folder>, which adds no path
        // component. Named child folders are still validated as single leaves.
        let folderComponents = folder.name.isEmpty
            ? components
            : components + [try SafePath.validatedLeaf(folder.name)]
        let localFolder = try SafePath.contained(base: clientRoot, components: folderComponents)

        for file in folder.files {
            let fileLeaf = try SafePath.validatedLeaf(file.name)
            let fullComponents = folderComponents + [fileLeaf]
            let local = try SafePath.contained(base: clientRoot, components: fullComponents)
            let remote = URLHelper.joining(
                base,
                ([AppConstants.clientRoot] + fullComponents).joined(separator: "/")
            )
            items.append(DownloadItem(
                file: file,
                localURL: local,
                remoteURL: remote
            ))
        }

        for child in folder.folders {
            try collect(folder: child, components: folderComponents, base: base, clientRoot: clientRoot, into: &items)
        }

        _ = localFolder
    }

    private func fileIsCurrent(_ item: DownloadItem, using fm: FileManager) -> Bool {
        guard fm.fileExists(atPath: item.localURL.path),
              let attributes = try? fm.attributesOfItem(atPath: item.localURL.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              size == item.file.size,
              let data = try? Data(contentsOf: item.localURL, options: .mappedIfSafe)
        else { return false }
        return XXHash64.hash(data) == item.file.hash
    }
}
