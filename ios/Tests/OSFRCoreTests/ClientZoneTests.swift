import Foundation
import XCTest
@testable import OSFRCore

final class ClientZoneTests: XCTestCase {
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

    private func f32(_ value: Float) -> Data { le32(value.bitPattern) }

    private func cString(_ value: String) -> Data {
        Data(value.utf8) + Data([0])
    }

    /// Minimal version-3 zone mirroring the observed `FabledRealms.gzne` layout.
    private func zoneFixture() -> Data {
        var data = Data("GZNE".utf8)
        data.append(le32(3))
        data.append(le32(0)) // reserved
        data.append(le32(0x0002_0000)) // observed header field
        data.append(le32(128))
        data.append(f32(64))
        data.append(le32(8))
        data.append(le32(UInt32(bitPattern: -32)))
        data.append(le32(UInt32(bitPattern: -48)))
        data.append(le32(96))
        data.append(le32(80))
        data.append(le32(0x0016_5C59))
        data.append(le32(2))
        data.append(le32(0)) // reserved
        precondition(data.count == 56)

        data.append(cString("SG_Dirt"))
        data.append(cString("sg_dirt.dds"))
        data.append(le32(8))
        data.append(le32(0))
        data.append(le32(1))

        data.append(cString("ss_grass"))
        data.append(cString("ss_grass.dds"))
        data.append(le32(9))
        data.append(le32(1))
        data.append(f32(1200))
        data.append(f32(1))
        data.append(f32(1))
        data.append(Data([0x20]))
        data.append(cString("flora_ss_green"))
        data.append(le32(3))

        data.append(Data([0xAA, 0xBB])) // next section marker
        return data
    }

    private func pack(named entry: String, payload: Data) -> Data {
        let name = Data(entry.utf8)
        var directory = be32(0)
        directory.append(be32(1))
        directory.append(be32(UInt32(name.count)))
        directory.append(name)
        directory.append(be32(UInt32(directory.count + 12)))
        directory.append(be32(UInt32(payload.count)))
        directory.append(be32(CRC32.checksum(payload)))
        return directory + payload
    }

    func testParsesVersionThreeHeaderAndMaterialTable() throws {
        let fixture = zoneFixture()
        let zone = try ClientZoneManifest(data: fixture)

        XCTAssertEqual(zone.version, 3)
        XCTAssertEqual(zone.unknownHeaderValue, 0x0002_0000)
        XCTAssertEqual(zone.tileResolution, 128)
        XCTAssertEqual(zone.tileWorldSize, 64)
        XCTAssertEqual(zone.flags, 8)
        XCTAssertEqual(zone.minChunkX, -32)
        XCTAssertEqual(zone.minChunkY, -48)
        XCTAssertEqual(zone.maxChunkX, 96)
        XCTAssertEqual(zone.maxChunkY, 80)
        XCTAssertEqual(zone.checksum, 0x0016_5C59)
        XCTAssertEqual(zone.materials.count, 2)
        XCTAssertEqual(zone.payloadOffset, fixture.count - 2)

        let dirt = try XCTUnwrap(zone.material(named: "SG_Dirt"))
        XCTAssertEqual(dirt.index, 1)
        XCTAssertEqual(dirt.flags, 8)
        XCTAssertEqual(dirt.textureName, "sg_dirt.dds")
        XCTAssertTrue(dirt.flora.isEmpty)

        let grass = try XCTUnwrap(zone.material(index: 3))
        XCTAssertEqual(grass.name, "ss_grass")
        XCTAssertEqual(grass.textureName, "ss_grass.dds")
        XCTAssertEqual(grass.flora.count, 1)
        let flora = try XCTUnwrap(grass.flora.first)
        XCTAssertEqual(flora.name, "flora_ss_green")
        XCTAssertEqual(flora.channel, 0x20)
        XCTAssertEqual(flora.density, 1200)
        XCTAssertEqual(flora.scale, 1)
        XCTAssertEqual(flora.variation, 1)
    }

    func testRejectsBadMagicVersionAndTruncatedTable() {
        XCTAssertThrowsError(try ClientZoneManifest(data: Data("NOPE".utf8))) { error in
            XCTAssertEqual(error as? ClientZoneError, .invalidMagic)
        }

        var badVersion = zoneFixture()
        badVersion.replaceSubrange(4..<8, with: le32(99))
        XCTAssertThrowsError(try ClientZoneManifest(data: badVersion)) { error in
            XCTAssertEqual(error as? ClientZoneError, .unsupportedVersion(99))
        }

        let truncated = zoneFixture().dropLast(40)
        XCTAssertThrowsError(try ClientZoneManifest(data: Data(truncated)))
    }

    func testDataLoaderReadsGzoneFromPackEntry() throws {
        let payload = zoneFixture()
        let archive = pack(named: "FabledRealms.gzne", payload: payload)
        let loader = ClientAssetDataLoader { path in
            path == "Assets_004.pack" ? archive : nil
        }

        let zone = try ClientZoneManifest(
            data: loader.data(relativePath: "Assets_004.pack#FabledRealms.gzne")
        )
        XCTAssertEqual(zone.materials.map(\.name), ["SG_Dirt", "ss_grass"])
        XCTAssertEqual(
            ClientZoneCatalog.zonePath(forZoneName: "FabledRealms"),
            "Assets_004.pack#FabledRealms.gzne"
        )
        XCTAssertNil(ClientZoneCatalog.zonePath(forZoneName: "Unknown"))
    }
}
