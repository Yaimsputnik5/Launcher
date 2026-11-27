import Foundation
import XCTest
@testable import OSFRCore

final class ClientMinimapAtlasTests: XCTestCase {
    private func be32(_ value: UInt32) -> Data {
        Data([
            UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value)
        ])
    }

    /// Single-entry `.pack` with the observed big-endian directory layout.
    private func pack(name: String, payload: Data) -> Data {
        let nameBytes = Data(name.utf8)
        var directory = be32(0)
        directory.append(be32(1))
        directory.append(be32(UInt32(nameBytes.count)))
        directory.append(nameBytes)
        directory.append(be32(UInt32(directory.count + 12)))
        directory.append(be32(UInt32(payload.count)))
        directory.append(be32(CRC32.checksum(payload)))
        return directory + payload
    }

    func testAtlasIntersectsTileInfoWithActuallyShippedDDSFiles() {
        let name = "FabledRealms_Tile_005_-32_0_0.dds"
        let row = "\(name)\t-2048.000000\t0.000000\t320.000000\t128.000000\t128.000000\n"
        let tilePack = pack(name: name, payload: Data([0x44, 0x44, 0x53, 0x20]))
        let infoPack = pack(name: "FabledRealms_TileInfo.txt", payload: Data(row.utf8))
        let loader = ClientAssetDataLoader { path in
            switch path {
            case "Assets_000.pack": return tilePack
            case "Assets_002.pack": return infoPack
            default: return nil
            }
        }

        let atlas = ClientMinimapAtlas(dataLoader: loader)
        XCTAssertEqual(atlas.rowCount, 1)
        XCTAssertEqual(atlas.tiles.count, 1)
        let tile = atlas.tiles[0]
        XCTAssertEqual(tile.name, name)
        XCTAssertEqual(tile.archiveName, "Assets_000.pack")
        XCTAssertEqual(tile.texturePath, "Assets_000.pack#\(name)")
        XCTAssertEqual(tile.centerX, -1984)
        XCTAssertEqual(tile.centerZ, 384)
        XCTAssertEqual(tile.width, 128)
        XCTAssertEqual(tile.height, 128)
        XCTAssertTrue(atlas.status.contains("decoded") == false)
    }

    func testMissingTileInfoOrDDSYieldsEmptyAtlasWithoutInventedTiles() {
        let empty = ClientMinimapAtlas(dataLoader: ClientAssetDataLoader { _ in nil })
        XCTAssertTrue(empty.tiles.isEmpty)
        XCTAssertEqual(empty.rowCount, 0)

        let tilePack = pack(
            name: "FabledRealms_Tile_005_-32_0_0.dds",
            payload: Data([0x44, 0x44, 0x53, 0x20])
        )
        let withoutTable = ClientMinimapAtlas(dataLoader: ClientAssetDataLoader { path in
            path == "Assets_000.pack" ? tilePack : nil
        })
        XCTAssertTrue(withoutTable.tiles.isEmpty)
        XCTAssertTrue(withoutTable.status.contains("TileInfo"))
    }
}
