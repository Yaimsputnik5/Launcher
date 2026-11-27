import Foundation
import XCTest
@testable import OSFRCore

final class CoreTests: XCTestCase {
    func testXXHash64Vectors() {
        XCTAssertEqual(XXHash64.hash(Data()), 0xEF46DB3751D8E999)
        XCTAssertEqual(XXHash64.hash(Data("abc".utf8)), 0x44BC2CF5AD770999)
    }

    func testEmbeddedClientEntryMatchesManifestFile() {
        let file = ClientFile(name: "a.bin", size: 3, hash: 0x2A)
        XCTAssertTrue(ClientAssetStore.embeddedEntryMatches(
            ClientAssetIndexEntry(path: "a.bin", size: 3, hash: 0x2A),
            file: file
        ))
        XCTAssertFalse(ClientAssetStore.embeddedEntryMatches(
            ClientAssetIndexEntry(path: "a.bin", size: 4, hash: 0x2A),
            file: file
        ))
        XCTAssertFalse(ClientAssetStore.embeddedEntryMatches(
            ClientAssetIndexEntry(path: "a.bin", size: 3, hash: 0x2B),
            file: file
        ))
        XCTAssertFalse(ClientAssetStore.embeddedEntryMatches(
            ClientAssetIndexEntry(path: "a.bin", size: -1, hash: 0x2A),
            file: file
        ))
    }

    func testBaseURLRejectsEmbeddedCredentials() throws {
        XCTAssertThrowsError(try URLHelper.baseURL("https://user:pass@example.com"))
    }

    func testBaseURLNormalizesTrailingSlash() throws {
        XCTAssertEqual(
            try URLHelper.baseURL("https://example.com/api").absoluteString,
            "https://example.com/api/"
        )
    }

    func testJoiningKeepsBasePath() {
        let base = URL(string: "https://example.com/api/")!
        XCTAssertEqual(
            URLHelper.joining(base, "login").absoluteString,
            "https://example.com/api/login"
        )
    }

    func testLoginResponseAcceptsSanctuaryCamelCaseJSON() throws {
        let json = #"{"sessionId":"abc123","launchArguments":"--locale en_US"}"#
        let response = try JSONDecoder().decode(LoginResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.sessionId, "abc123")
        XCTAssertEqual(response.launchArguments, "--locale en_US")
    }

    func testLoginResponseAcceptsPascalCaseJSON() throws {
        let json = #"{"SessionId":"def456","LaunchArguments":null}"#
        let response = try JSONDecoder().decode(LoginResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.sessionId, "def456")
        XCTAssertNil(response.launchArguments)
    }

    func testLoginResponseRejectsMissingSessionId() {
        let json = #"{"launchArguments":null}"#
        XCTAssertThrowsError(try JSONDecoder().decode(LoginResponse.self, from: Data(json.utf8))) { error in
            guard case DecodingError.keyNotFound(let key, _) = error else {
                return XCTFail("Expected keyNotFound, got \(error)")
            }
            XCTAssertEqual(key.stringValue, "sessionId")
        }
    }

    func testServerManifestV2() throws {
        let xml = """
        <?xml version="1.0"?><ServerManifest version="2">
          <Name>Sanctuary</Name>
          <Description>Local server</Description>
          <WebApiUrl>http://127.0.0.1:20040/</WebApiUrl>
          <LoginServer>127.0.0.1:20042</LoginServer>
        </ServerManifest>
        """
        let manifest = try ServerManifestParser().parse(Data(xml.utf8))
        XCTAssertEqual(manifest.version, 2)
        XCTAssertEqual(manifest.name, "Sanctuary")
        XCTAssertEqual(manifest.webAPIURL, "http://127.0.0.1:20040/")
        XCTAssertEqual(manifest.loginServer, "127.0.0.1:20042")
    }

    func testClientManifestParsesFiles() throws {
        let hash = XXHash64.hash(Data("abc".utf8))
        let xml = """
        <?xml version="1.0"?><ClientManifest version="1" languages="en_US">
          <Folder name="client">
            <File name="a.bin" size="3" hash="\(hash)"/>
          </Folder>
        </ClientManifest>
        """
        let manifest = try ClientManifestParser().parse(Data(xml.utf8))
        XCTAssertEqual(manifest.languages, [.en_US])
        XCTAssertEqual(manifest.rootFolder.name, "client")
        XCTAssertEqual(manifest.rootFolder.files.count, 1)
        XCTAssertEqual(manifest.rootFolder.files[0].name, "a.bin")
        XCTAssertEqual(manifest.rootFolder.files[0].hash, hash)
    }

    func testClientManifestAllowsUnnamedRoot() throws {
        let xml = """
        <?xml version="1.0"?><ClientManifest version="1" languages="en_us">
          <Folder>
            <Folder name="data">
              <File name="a.bin" size="3" hash="1"/>
            </Folder>
          </Folder>
        </ClientManifest>
        """
        let manifest = try ClientManifestParser().parse(Data(xml.utf8))
        // The live OSFR manifest spells the locale `en_us`; C# parses manifest
        // locales case-insensitively, so this must resolve to `.en_US`.
        XCTAssertEqual(manifest.languages, [.en_US])
        XCTAssertEqual(manifest.rootFolder.name, "")
        XCTAssertEqual(manifest.rootFolder.folders.count, 1)
        XCTAssertEqual(manifest.rootFolder.folders[0].name, "data")
        XCTAssertEqual(manifest.rootFolder.folders[0].files[0].name, "a.bin")
    }

    func testClientManifestLanguagesAreCaseInsensitive() throws {
        let xml = """
        <?xml version="1.0"?><ClientManifest version="1" languages="EN_us, de_DE, fi_FI, unknown">
          <Folder><File name="a.bin" size="3" hash="1"/></Folder>
        </ClientManifest>
        """
        let manifest = try ClientManifestParser().parse(Data(xml.utf8))
        // `fi_FI` is the corrected spelling of the C# enum's `fi_FL` typo.
        XCTAssertEqual(manifest.languages, [.en_US, .de_DE, .fi_FL])
    }

    func testClientManifestRejectsTraversal() {
        let xml = """
        <?xml version="1.0"?><ClientManifest version="1" languages="en_US">
          <Folder name=".."><File name="a.bin" size="3" hash="1"/></Folder>
        </ClientManifest>
        """
        XCTAssertThrowsError(try ClientManifestParser().parse(Data(xml.utf8)))
    }

    func testSafePathValidatedLeaf() throws {
        XCTAssertEqual(try SafePath.validatedLeaf("Client"), "Client")
        XCTAssertThrowsError(try SafePath.validatedLeaf("../escape"))
        XCTAssertThrowsError(try SafePath.validatedLeaf("a/b"))
    }

    func testSafePathContainedAcceptsTrailingSlashBase() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("SafePath-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // Bundle.main URLs for directory resources can carry a trailing slash
        // on iOS; that must not make a contained child look unsafe.
        let trailingSlashRoot = URL(fileURLWithPath: root.path + "/", isDirectory: true)
        let url = try SafePath.contained(base: trailingSlashRoot, components: ["Npcs.json"])
        XCTAssertEqual(url.lastPathComponent, "Npcs.json")
    }

    func testSafePathContainedRejectsSymlinkEscape() throws {
        let fm = FileManager.default
        let parent = fm.temporaryDirectory.appendingPathComponent("SafePath-\(UUID().uuidString)", isDirectory: true)
        let root = parent.appendingPathComponent("root", isDirectory: true)
        let outside = parent.appendingPathComponent("outside", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: parent) }
        try Data("secret".utf8).write(to: outside.appendingPathComponent("secret.txt"))
        try fm.createSymbolicLink(
            at: root.appendingPathComponent("escape"),
            withDestinationURL: outside
        )

        XCTAssertThrowsError(
            try SafePath.contained(base: root, components: ["escape", "secret.txt"])
        )
    }

    func testSafePathContainedAcceptsSymlinkedRoot() throws {
        let fm = FileManager.default
        let parent = fm.temporaryDirectory.appendingPathComponent("SafePath-\(UUID().uuidString)", isDirectory: true)
        let real = parent.appendingPathComponent("real", isDirectory: true)
        let link = parent.appendingPathComponent("link", isDirectory: true)
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: parent) }
        try fm.createSymbolicLink(at: link, withDestinationURL: real)

        let url = try SafePath.contained(base: link, components: ["Npcs.json"])
        XCTAssertEqual(url.lastPathComponent, "Npcs.json")
    }

    func testSafePathReadOnlyRootSkipsSymlinkResolution() throws {
        let fm = FileManager.default
        let parent = fm.temporaryDirectory.appendingPathComponent("SafePath-\(UUID().uuidString)", isDirectory: true)
        let root = parent.appendingPathComponent("root", isDirectory: true)
        let outside = parent.appendingPathComponent("outside", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: parent) }
        try Data("secret".utf8).write(to: outside.appendingPathComponent("secret.txt"))
        try fm.createSymbolicLink(
            at: root.appendingPathComponent("escape"),
            withDestinationURL: outside
        )

        // Read-only bundle resources opt out of symlink resolution because
        // LiveContainer exposes the same files through a canonicalized path.
        let url = try SafePath.contained(
            base: root,
            components: ["secret.txt"],
            resolveSymlinks: false
        )
        XCTAssertEqual(url.lastPathComponent, "secret.txt")

        // Lexical traversal is still rejected in read-only mode.
        XCTAssertThrowsError(
            try SafePath.contained(
                base: root,
                components: ["..", "outside", "secret.txt"],
                resolveSymlinks: false
            )
        )
    }
}
