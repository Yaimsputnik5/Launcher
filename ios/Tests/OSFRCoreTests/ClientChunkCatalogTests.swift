import Foundation
import XCTest
@testable import OSFRCore

final class ClientChunkCatalogTests: XCTestCase {
    func testGCNKParserReadsShippedObjectRecordLayout() throws {
        let inflated = Self.sampleChunk()
        let header = Self.header(version: 6, expectedLength: inflated.count)
        let catalog = try ClientChunkCatalog.parseGCNK(
            header,
            chunkName: "FabledRealms_0_-8.gcnk",
            decompressor: { _ in inflated }
        )

        XCTAssertEqual(catalog.count, 1)
        let object = try XCTUnwrap(catalog.first)
        XCTAssertEqual(object.chunkName, "FabledRealms_0_-8.gcnk")
        XCTAssertEqual(object.assetName, "sg_tree_giant_03.adr")
        XCTAssertEqual(object.position.x, -448.9955, accuracy: 0.001)
        XCTAssertEqual(object.position.y, 37.0929, accuracy: 0.001)
        XCTAssertEqual(object.position.z, 35.7929, accuracy: 0.001)
        XCTAssertEqual(object.scale, 1, accuracy: 0.001)
        XCTAssertEqual(object.rotation.x, -4.2945, accuracy: 0.001)
    }

    func testGCNKParserRejectsBadMagicAndVersion() {
        var badMagic = Data([0, 0, 0, 0])
        badMagic.append(Self.le32(6))
        badMagic.append(Self.le32(8))
        badMagic.append(Self.le32(0x78_9C))
        XCTAssertThrowsError(
            try ClientChunkCatalog.parseGCNK(
                badMagic,
                chunkName: "bad.gcnk",
                decompressor: { _ in Data(repeating: 0, count: 8) }
            )
        ) { error in
            XCTAssertEqual(error as? ClientChunkError, .invalidMagic)
        }

        let badVersion = Self.header(version: 5, expectedLength: 8)
        XCTAssertThrowsError(
            try ClientChunkCatalog.parseGCNK(
                badVersion,
                chunkName: "bad.gcnk",
                decompressor: { _ in Data(repeating: 0, count: 8) }
            )
        ) { error in
            XCTAssertEqual(error as? ClientChunkError, .unsupportedVersion(5))
        }
    }

    func testGCNKParserSkipsBinaryTextThatIsNotAnObjectRecord() throws {
        var inflated = Data("newLight\0\0briar_patch_orange\0\0".utf8)
        inflated.append(Self.sampleChunk())
        let objects = try ClientChunkCatalog.parseDecompressed(
            [UInt8](inflated),
            chunkName: "mixed.gcnk"
        )
        XCTAssertEqual(objects.map(\.assetName), ["sg_tree_giant_03.adr"])
    }

    private static func header(version: UInt32, expectedLength: Int) -> Data {
        var data = Data("GCNK".utf8)
        data.append(le32(version))
        data.append(le32(UInt32(expectedLength)))
        data.append(le32(0x78_9C))
        return data
    }

    private static func sampleChunk() -> Data {
        var data = Data("sg_tree_giant_03.adr".utf8)
        data.append(0) // name terminator
        data.append(0) // observed separator byte
        let fields: [Float] = [-448.9955, 37.0929, 35.7929, 1.0, -4.2945, -0.053, -0.278, 0, 0.99]
        for value in fields {
            data.append(le32(value.bitPattern))
        }
        data.append(le32(0x00FF_0000)) // observed property word
        data.append(Data(repeating: 0, count: 12))
        return data
    }

    private static func le32(_ value: UInt32) -> Data {
        Data([
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 24)
        ])
    }
}
