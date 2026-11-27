import Foundation

/// Bounded, rotating file log for the iOS launcher.
///
/// The desktop launcher writes `logs/Launcher.log` through NLog. A sandboxed
/// iOS app cannot open a desktop file manager on that directory, so the app
/// also exposes the same file in Diagnostics with a share action. Messages are
/// already sanitized by their callers; request bodies and credentials are never
/// passed here.
final class LaunchLog {
    enum Level: String {
        case info
        case warning
        case error
    }

    static let shared = LaunchLog()

    private let lock = NSLock()
    private let directory: URL
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// NLog's file target in the C# launcher is unbounded, which can grow
    /// forever on a long-lived desktop install. Keep three rotated files.
    private let maximumBytes = 2 * 1024 * 1024
    private let retainedFiles = 4

    init(directory: URL = AppPaths.logsDirectory) {
        self.directory = directory
    }

    var currentFileURL: URL {
        directory.appendingPathComponent("Launcher.log", isDirectory: false)
    }

    func log(_ level: Level, _ message: String) {
        lock.lock()
        defer { lock.unlock() }

        let fm = FileManager.default
        guard (try? fm.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else { return }

        if let size = try? currentFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size >= maximumBytes {
            rotate()
        }

        let flat = message
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let line = "\(formatter.string(from: Date())) [\(level.rawValue)] \(flat)\n"
        guard let data = line.data(using: .utf8) else { return }

        if !fm.fileExists(atPath: currentFileURL.path) {
            fm.createFile(atPath: currentFileURL.path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: currentFileURL.path) else { return }
        defer { try? handle.close() }
        _ = handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.synchronize()
    }

    func read() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return try? String(contentsOf: currentFileURL, encoding: .utf8)
    }

    /// Current and rotated logs, newest first, for `ShareLink`.
    func exportURLs() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names
            .filter { $0 == "Launcher.log" || ($0.hasPrefix("Launcher.") && $0.hasSuffix(".log")) }
            .sorted { lhs, rhs in
                if lhs == "Launcher.log" { return true }
                if rhs == "Launcher.log" { return false }
                return lhs > rhs
            }
            .map { directory.appendingPathComponent($0, isDirectory: false) }
            .filter { fm.fileExists(atPath: $0.path) }
    }

    private func rotate() {
        let fm = FileManager.default
        let oldest = directory.appendingPathComponent("Launcher.\(retainedFiles - 1).log")
        try? fm.removeItem(at: oldest)
        if fm.fileExists(atPath: currentFileURL.path) {
            for index in stride(from: retainedFiles - 2, through: 1, by: -1) {
                let source = directory.appendingPathComponent("Launcher.\(index).log")
                guard fm.fileExists(atPath: source.path) else { continue }
                let target = directory.appendingPathComponent("Launcher.\(index + 1).log")
                if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }
                try? fm.moveItem(at: source, to: target)
            }
            try? fm.moveItem(at: currentFileURL, to: directory.appendingPathComponent("Launcher.1.log"))
        }
    }
}
