import Foundation

enum AppPaths {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("OSFRLauncher", isDirectory: true)
    }

    static var serversRoot: URL {
        root.appendingPathComponent("Servers", isDirectory: true)
    }

    static var settingsFile: URL {
        root.appendingPathComponent("settings.json")
    }

    static var logsDirectory: URL {
        root.appendingPathComponent("logs", isDirectory: true)
    }

    /// Original client payload copied into the app bundle by
    /// `scripts/fetch_client_payload.sh`.
    static var bundledClientAssets: URL? {
        Bundle.main.url(forResource: "ClientAssets", withExtension: nil)
    }

    /// Server-side Sanctuary data copied into the app bundle by
    /// `scripts/sync_sanctuary_resources.sh`.
    static var bundledSanctuaryResources: URL? {
        Bundle.main.url(forResource: "SanctuaryResources", withExtension: nil)
    }

    /// Writable copy of the client payload, useful after a repair download.
    static var sandboxClientAssets: URL {
        root.appendingPathComponent("ClientAssets", isDirectory: true)
    }

    static func serverDirectory(_ info: ServerInfo) throws -> URL {
        let leaf = try SafePath.validatedLeaf(info.savePath)
        return try SafePath.contained(base: serversRoot, components: [leaf])
    }

    static func clientDirectory(_ info: ServerInfo) throws -> URL {
        try serverDirectory(info).appendingPathComponent("Client", isDirectory: true)
    }
}

enum SafePath {
    private static let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")

    static func sanitizedLeaf(_ raw: String) -> String {
        let pieces = raw.components(separatedBy: invalidCharacters).joined(separator: "-")
        let cleaned = pieces
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "..", with: "")
        let trimmed = String(cleaned.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Server" : trimmed
    }

    static func validatedLeaf(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != ".",
              trimmed != "..",
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              !trimmed.contains("\0"),
              trimmed.rangeOfCharacter(from: invalidCharacters) == nil,
              trimmed.rangeOfCharacter(from: .controlCharacters) == nil
        else {
            throw LauncherError.unsafePath(raw)
        }
        return trimmed
    }

    /// Resolves a resource inside a trusted read-only `Bundle.main` directory.
    ///
    /// LiveContainer can expose bundle resources through canonical paths that
    /// do not share the literal bundle prefix, so path-string containment and
    /// symlink resolution are both inappropriate here. `validatedLeaf` still
    /// rejects separators, NULs, control characters and dot segments, which is
    /// sufficient for a caller-supplied relative path under a trusted root.
    static func bundledResourceURL(base: URL, components: [String]) throws -> URL {
        var result = base
        for component in components {
            result = result.appendingPathComponent(try validatedLeaf(component))
        }
        return result
    }

    /// - Parameter resolveSymlinks: Set `false` only when a caller already knows
    ///   the root is trusted and read-only. Prefer `bundledResourceURL` for
    ///   `Bundle.main` resources; writable roots must keep symlink resolution
    ///   enabled so an escape symlink cannot redirect I/O.
    static func contained(
        base: URL,
        components: [String],
        resolveSymlinks: Bool = true
    ) throws -> URL {
        var result = base
        for component in components {
            result = result.appendingPathComponent(try validatedLeaf(component))
        }

        let basePath = normalizedPath(base)
        let resultPath = normalizedPath(result)
        guard isContained(resultPath, in: basePath) else {
            throw LauncherError.unsafePath(result.path)
        }
        guard resolveSymlinks else { return result }

        let resolvedBasePath = normalizedPath(base.resolvingSymlinksInPath())
        let resolvedResultPath = normalizedPath(result.resolvingSymlinksInPath())
        guard isContained(resolvedResultPath, in: resolvedBasePath) else {
            throw LauncherError.unsafePath(result.path)
        }
        return result
    }

    private static func isContained(_ path: String, in base: String) -> Bool {
        path == base || path.hasPrefix(base + "/")
    }

    /// Collapses `.`/`..` segments, removes duplicate separators and drops a
    /// trailing slash so `URL.path` differences between Foundation platforms do
    /// not turn a contained path into a false rejection.
    private static func normalizedPath(_ url: URL) -> String {
        let standardized = (url.standardizedFileURL.path as NSString).standardizingPath
        var path = standardized
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}
