import Foundation
import XCTest
@testable import OSFRCore

final class WorldAssetCatalogTests: XCTestCase {
    private func le32(_ value: UInt32) -> Data {
        Data([
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 24)
        ])
    }

    private func be32(_ value: UInt32) -> Data {
        Data([
            UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value)
        ])
    }

    /// A 4x4 DXT1 image with one all-black block.
    private func sampleDDS() -> Data {
        var data = Data("DDS ".utf8)
        data.append(le32(124))
        data.append(le32(0x1007))
        data.append(le32(4)) // height
        data.append(le32(4)) // width
        data.append(le32(8)) // pitch
        data.append(le32(0)) // depth
        data.append(le32(0)) // mip count
        for _ in 0..<11 { data.append(le32(0)) }
        data.append(le32(32))
        data.append(le32(0x4))
        data.append(Data("DXT1".utf8))
        data.append(le32(0))
        for _ in 0..<4 { data.append(le32(0)) }
        data.append(le32(0x1000))
        for _ in 0..<4 { data.append(le32(0)) }
        precondition(data.count == 128)
        data.append(Data(repeating: 0, count: 8))
        return data
    }

    private func makePack(entries: [(name: String, payload: Data)]) -> Data {
        var directory = be32(0)
        directory.append(be32(UInt32(entries.count)))
        var offsets: [Int] = []
        let directorySize = 8 + entries.reduce(0) { $0 + 4 + $1.name.utf8.count + 12 }
        var offset = directorySize
        for entry in entries {
            let name = Data(entry.name.utf8)
            directory.append(be32(UInt32(name.count)))
            directory.append(name)
            directory.append(be32(UInt32(offset)))
            directory.append(be32(UInt32(entry.payload.count)))
            directory.append(be32(CRC32.checksum(entry.payload)))
            offsets.append(offset)
            offset += entry.payload.count
        }
        precondition(directory.count == directorySize)
        precondition(offsets.allSatisfy { $0 >= directorySize })
        var result = directory
        for entry in entries { result.append(entry.payload) }
        return result
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OSFRWorldAssetCatalogTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }

    func testManifestParsesRowsAndRejectsUnsafeNames() throws {
        let text = "img1.dds.z,2304213141,422767\nimages/avatars/frames/bronze.png,1,20\n"
        let manifest = try WorldAssetManifest.parse(Data(text.utf8))
        XCTAssertEqual(manifest.entries.count, 2)
        XCTAssertEqual(manifest.entry(named: "img1.dds.z")?.crc32, 2_304_213_141)
        XCTAssertEqual(manifest.entry(named: "img1.dds")?.crc32, 2_304_213_141)
        XCTAssertEqual(manifest.entry(named: "images/avatars/frames/bronze.png")?.storedSize, 20)

        let unsafe = "ok.png,1,2\n../escape.png,1,2\n"
        XCTAssertThrowsError(try WorldAssetManifest.parse(Data(unsafe.utf8))) { error in
            guard case WorldAssetCatalogError.unsafeName("../escape.png") = error else {
                return XCTFail("Expected unsafeName, got \(error)")
            }
        }
    }

    func testCatalogResolvesZManifestNameToPackPayload() throws {
        let root = try makeRoot()
        let payload = sampleDDS()
        let crc = CRC32.checksum(payload)
        try Data("img1.dds.z,\(crc),999\n".utf8)
            .write(to: root.appendingPathComponent("Assets_manifest.txt"))
        try makePack(entries: [("img1.dds", payload)])
            .write(to: root.appendingPathComponent("Assets_000.pack"))

        let catalog = try WorldAssetCatalog(
            root: root,
            manifestPaths: ["Assets_manifest.txt"],
            packPaths: ["Assets_000.pack"]
        )
        XCTAssertEqual(catalog.manifests.count, 1)
        XCTAssertEqual(catalog.packEntries.count, 1)
        XCTAssertEqual(catalog.packEntry(for: "img1.dds.z")?.name, "img1.dds")
        XCTAssertEqual(try catalog.payload(for: "img1.dds.z"), payload)
        XCTAssertThrowsError(try catalog.payload(for: "missing.dds.z")) { error in
            guard case WorldAssetCatalogError.notFound = error else {
                return XCTFail("Expected notFound, got \(error)")
            }
        }
    }

    func testCatalogRejectsExactNameManifestPackCRCDisagreement() throws {
        let root = try makeRoot()
        let payload = sampleDDS()
        let crc = CRC32.checksum(payload) ^ 1
        try Data("img1.dds,\(crc),\(payload.count)\n".utf8)
            .write(to: root.appendingPathComponent("Assets_manifest.txt"))
        try makePack(entries: [("img1.dds", payload)])
            .write(to: root.appendingPathComponent("Assets_000.pack"))

        let catalog = try WorldAssetCatalog(
            root: root,
            manifestPaths: ["Assets_manifest.txt"],
            packPaths: ["Assets_000.pack"]
        )
        XCTAssertThrowsError(try catalog.payload(for: "img1.dds")) { error in
            guard case WorldAssetCatalogError.manifestPackMismatch = error else {
                return XCTFail("Expected manifestPackMismatch, got \(error)")
            }
        }
    }

    func testCompressedManifestCRCDisagreementStillReturnsPackPayload() throws {
        let root = try makeRoot()
        let payload = sampleDDS()
        let packCRC = CRC32.checksum(payload)
        try Data("img1.dds.z,\(packCRC ^ 1),999\n".utf8)
            .write(to: root.appendingPathComponent("Assets_manifest.txt"))
        try makePack(entries: [("img1.dds", payload)])
            .write(to: root.appendingPathComponent("Assets_000.pack"))

        let catalog = try WorldAssetCatalog(
            root: root,
            manifestPaths: ["Assets_manifest.txt"],
            packPaths: ["Assets_000.pack"]
        )
        XCTAssertEqual(try catalog.payload(for: "img1.dds.z"), payload)
        let disagreement = try XCTUnwrap(
            catalog.compressedManifestCRCDisagreement(for: "img1.dds.z")
        )
        XCTAssertEqual(disagreement.manifestName, "img1.dds.z")
        XCTAssertEqual(disagreement.manifestCRC, packCRC ^ 1)
        XCTAssertEqual(disagreement.packName, "img1.dds")
        XCTAssertEqual(disagreement.packCRC, packCRC)
    }

    func testTextureLoaderDecodesManifestWorldTexture() throws {
        let root = try makeRoot()
        let payload = sampleDDS()
        let crc = CRC32.checksum(payload)
        try Data("img1.dds.z,\(crc),999\n".utf8)
            .write(to: root.appendingPathComponent("Assets_manifest.txt"))
        try makePack(entries: [("img1.dds", payload)])
            .write(to: root.appendingPathComponent("AssetsW_000.pack"))

        let catalog = try WorldAssetCatalog(
            root: root,
            manifestPaths: ["Assets_manifest.txt"],
            packPaths: ["AssetsW_000.pack"]
        )
        let loader = TextureLoader(lookup: { _ in nil }, worldCatalog: catalog)
        let image = try loader.load(relativePath: "img1.dds.z")
        XCTAssertEqual(image.width, 4)
        XCTAssertEqual(image.height, 4)
        XCTAssertEqual(image.pixels.count, 64)
    }

    /// Opt-in acceptance test against the real OSFR client tree. It is skipped
    /// unless the maintainer sets OSFR_LOCAL_CLIENT_DIR; CI must not pretend to
    /// own a payload it cannot fetch from the public CDN.
    func testRealClientCatalogSmoke() throws {
        guard let raw = ProcessInfo.processInfo.environment["OSFR_LOCAL_CLIENT_DIR"],
              !raw.isEmpty
        else {
            throw XCTSkip("Set OSFR_LOCAL_CLIENT_DIR to verify the real client payload")
        }
        let root = URL(fileURLWithPath: raw, isDirectory: true)
        let catalog = try WorldAssetCatalog(root: root)
        XCTAssertGreaterThan(catalog.manifests[0].entries.count, 100_000)
        XCTAssertGreaterThan(catalog.packEntries.count, 60_000)

        let name = "FabledRealms_BlacksporeCave_Tile_650.40_-1984.00_-18.93_1_0.dds.z"
        let payload = try catalog.payload(for: name)
        XCTAssertEqual(Data(payload.prefix(4)), Data("DDS ".utf8))
        XCTAssertGreaterThan(payload.count, 128)

        // The crosswalk found exactly two `.z` rows whose CRC describes
        // compressed bytes rather than the stored pack payload. They must
        // still resolve; the disagreement is diagnostic, not fatal.
        for compressedName in [
            "FabledRealmsAreas.xml.z",
            "ActorSoundEmitterDefinitions.xml.z"
        ] {
            let xml = try catalog.payload(for: compressedName)
            XCTAssertGreaterThan(xml.count, 1_000)
            XCTAssertNotNil(
                catalog.compressedManifestCRCDisagreement(for: compressedName),
                "Expected a compressed-CRC diagnostic for \(compressedName)"
            )
        }
    }
}
