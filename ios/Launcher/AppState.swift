import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var settings: AppSettings
    @Published private(set) var runtimes: [ServerRuntime] = []
    @Published var notifications: [AppNotice] = []

    init() {
        let loaded = AppSettings.load()
        settings = loaded
        runtimes = loaded.servers.map { ServerRuntime(info: $0) }
        for runtime in runtimes { runtime.state = self }

        if loaded.servers.isEmpty && !loaded.didSeedDefaultServers {
            settings.didSeedDefaultServers = true
            persistSettings()
            Task { await seedDefaultServers() }
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

        let manifest = try await HTTPClient.shared.serverManifest(from: base)
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

    func setLocale(_ locale: GameLocale) {
        settings.locale = locale
        persistSettings()
    }

    func notify(_ message: String, isError: Bool = false) {
        let notice = AppNotice(message: message, isError: isError)
        notifications.append(notice)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
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

    private func seedDefaultServers() async {
        for url in AppConstants.defaultServerURLs {
            try? await addServer(urlString: url)
        }
    }
}

@MainActor
final class ServerRuntime: ObservableObject, Identifiable {
    var id: UUID { info.id }

    @Published var info: ServerInfo
    @Published var status: ServerStatus?
    @Published var statusMessage = ""
    @Published var lastError: String?
    @Published var isRefreshing = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var downloadedFileName = ""

    weak var state: AppState?

    init(info: ServerInfo) {
        self.info = info
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
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
            info = updated
            state?.update(updated)

            status = await ServerStatusClient.query(address: updated.loginServer)
            statusMessage = status?.online == true
                ? "\(status?.onlinePlayers ?? 0) players online"
                : "Server is offline or unreachable"
        } catch {
            lastError = error.localizedDescription
            status = nil
            statusMessage = "Could not refresh server: \(error.localizedDescription)"
        }
    }

    /// Downloads and verifies all client files. iOS cannot execute the desktop
    /// game, so this only prepares files and reports readiness.
    func prepareForDesktopPlay() async {
        guard !isDownloading else { return }
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

            var items: [DownloadItem] = []
            let clientRoot = try AppPaths.clientDirectory(info)
            try collect(folder: manifest.rootFolder, components: [], base: base, clientRoot: clientRoot, into: &items)

            guard !items.isEmpty else {
                statusMessage = "The client manifest contains no files."
                return
            }

            let fm = FileManager.default
            var planned: [DownloadItem] = []
            for item in items {
                if fileIsCurrent(item, using: fm) { continue }
                planned.append(item)
            }

            if planned.isEmpty {
                downloadProgress = 1
                statusMessage = "All \(items.count) client files are up to date."
                return
            }

            statusMessage = "Preparing \(planned.count) of \(items.count) client files…"
            for (index, item) in planned.enumerated() {
                downloadedFileName = item.file.name
                downloadProgress = 0
                do {
                    try await HTTPClient.shared.downloadFile(
                        from: item.remoteURL,
                        to: item.localURL,
                        expectedSize: item.file.size,
                        expectedHash: item.file.hash
                    ) { [weak self] fraction in
                        Task { @MainActor in self?.downloadProgress = fraction }
                    }
                } catch {
                    // Retry once; transient network failures are common on mobile.
                    try await HTTPClient.shared.downloadFile(
                        from: item.remoteURL,
                        to: item.localURL,
                        expectedSize: item.file.size,
                        expectedHash: item.file.hash
                    ) { [weak self] fraction in
                        Task { @MainActor in self?.downloadProgress = fraction }
                    }
                }
                downloadProgress = Double(index + 1) / Double(planned.count)
            }
            statusMessage = "Client files are ready. The game itself requires a desktop computer."
            state?.notify("Downloaded \(planned.count) client files.")
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Download failed: \(error.localizedDescription)"
            state?.notify("Download failed: \(error.localizedDescription)", isError: true)
        }
    }

    private struct DownloadItem {
        let file: ClientFile
        let localURL: URL
        let remoteURL: URL
    }

    private func collect(folder: ClientFolder,
                         components: [String],
                         base: URL,
                         clientRoot: URL,
                         into items: inout [DownloadItem]) throws {
        let folderLeaf = try SafePath.validatedLeaf(folder.name)
        let folderComponents = components + [folderLeaf]
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
