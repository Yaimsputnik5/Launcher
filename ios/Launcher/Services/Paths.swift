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

    static func contained(base: URL, components: [String]) throws -> URL {
        var result = base
        for component in components {
            result = result.appendingPathComponent(try validatedLeaf(component))
        }

        let resolvedBase = base.resolvingSymlinksInPath().path
        let resolvedResult = result.resolvingSymlinksInPath().path
        guard resolvedResult == resolvedBase || resolvedResult.hasPrefix(resolvedBase + "/") else {
            throw LauncherError.unsafePath(result.path)
        }
        return result
    }
}
