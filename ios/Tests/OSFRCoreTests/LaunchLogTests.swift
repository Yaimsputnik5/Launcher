import Foundation
import XCTest
@testable import OSFRCore

final class LaunchLogTests: XCTestCase {
    private func temporaryDirectory(_ name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("osfr-log-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func testWritesTimestampedLevelsAndKeepsOneEntryPerLine() {
        let directory = temporaryDirectory("write")
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = LaunchLog(directory: directory)

        log.log(.info, "Added server")
        log.log(.error, "HTTP 500\nfor /login")

        let text = log.read() ?? ""
        XCTAssertTrue(text.contains("[info] Added server"))
        XCTAssertTrue(text.contains("[error] HTTP 500 for /login"))
        XCTAssertEqual(text.split(separator: "\n").count, 2)
    }

    func testRotatesWhenCurrentFileExceedsLimit() {
        let directory = temporaryDirectory("rotate")
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = LaunchLog(directory: directory)

        log.log(.info, String(repeating: "x", count: 2 * 1024 * 1024))
        log.log(.info, "after rotation")

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("Launcher.1.log").path
        ))
        XCTAssertTrue((log.read() ?? "").contains("[info] after rotation"))
        XCTAssertEqual(log.exportURLs().first?.lastPathComponent, "Launcher.log")
    }

    func testExportOnlyContainsLogFilesThatExist() {
        let directory = temporaryDirectory("export")
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = LaunchLog(directory: directory)

        XCTAssertTrue(log.exportURLs().isEmpty)
        log.log(.warning, "Download resumed")
        XCTAssertEqual(log.exportURLs().map(\.lastPathComponent), ["Launcher.log"])
    }
}
