import Foundation
import XCTest
@testable import OSFRCore

final class RealZoneSmokeTests: XCTestCase {
    private var assetsURL: URL {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let ios = tests.deletingLastPathComponent().deletingLastPathComponent()
        return ios.appendingPathComponent("Launcher/Resources/ClientAssets")
    }

    func testRealFabledRealmsGzneParses() throws {
        let archiveURL = assetsURL.appendingPathComponent("Assets_004.pack")
        let loader = ClientAssetDataLoader { requested in
            requested == "Assets_004.pack" ? try? Data(contentsOf: archiveURL) : nil
        }
        let zone = try loader.zoneManifest(forZoneName: "FabledRealms")
        XCTAssertEqual(zone.version, 3)
        XCTAssertEqual(zone.tileResolution, 128)
        XCTAssertEqual(zone.tileWorldSize, 64)
        XCTAssertEqual(zone.minChunkX, -32)
        XCTAssertEqual(zone.minChunkY, -48)
        XCTAssertEqual(zone.maxChunkX, 96)
        XCTAssertEqual(zone.maxChunkY, 80)
        XCTAssertEqual(zone.materials.count, 55)
        XCTAssertEqual(zone.material(index: 1)?.name, "SG_Dirt")
        XCTAssertEqual(zone.material(named: "ss_sand")?.flora.count, 2)
    }

    func testMaterialCatalogEntriesAreVerifiedPackPaths() throws {
        let paths = Set(ClientMaterialCatalog.entries.map {
            "\($0.archive)#\($0.entryName)"
        })
        XCTAssertEqual(paths.count, ClientMaterialCatalog.entries.count)
        XCTAssertEqual(
            ClientMaterialCatalog.texturePath(forTextureName: "SG_DIRT.DDS"),
            "Assets_008.pack#sg_dirt.dds"
        )
        XCTAssertNil(ClientMaterialCatalog.texturePath(forTextureName: "missing.dds"))

        for entry in ClientMaterialCatalog.entries {
            let archiveURL = assetsURL.appendingPathComponent(entry.archive)
            let data = try Data(contentsOf: archiveURL)
            let archive = try PackArchive(data)
            XCTAssertNotNil(
                try? archive.payload(named: entry.entryName),
                "Missing or corrupt \(entry.archive)#\(entry.entryName)"
            )
        }
    }
}
