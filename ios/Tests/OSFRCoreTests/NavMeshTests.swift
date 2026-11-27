import Foundation
import XCTest
@testable import OSFRCore

/// Reads the shipped Sanctuary SNAV file rather than a fabricated waypoint
/// graph. The test skips when the resource is absent so the package remains
/// usable outside the full client checkout.
final class NavMeshTests: XCTestCase {
    private var navmeshURL: URL? {
        let file = URL(fileURLWithPath: #filePath)
        let package = file
            .deletingLastPathComponent() // OSFRCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ios
        return package
            .appendingPathComponent("Launcher/Resources/SanctuaryResources/Resources/NavMeshes/FabledRealms.navmesh")
    }

    private func loadShippedMesh() throws -> NavMeshSet {
        guard let url = navmeshURL, FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("FabledRealms.navmesh is not available in this checkout")
        }
        let data = try Data(contentsOf: url)
        #if canImport(Compression)
        return try NavMeshSet(data: data)
        #else
        // Linux has no Compression framework. Use the platform zlib only in the
        // test harness; production iOS still enters through `NavMeshSet(data:)`.
        guard data.count > 12,
              data.starts(with: [0x53, 0x4e, 0x41, 0x56]),
              try Self.u32(data, 4) == 1
        else {
            throw XCTSkip("FabledRealms.navmesh has an unexpected SNAV header")
        }
        return try NavMeshSet(inflated: try inflateWithPython(data.subdata(in: 8..<data.count)))
        #endif
    }

    #if !canImport(Compression)
    private static func u32(_ data: Data, _ offset: Int) throws -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private func inflateWithPython(_ source: Data) throws -> Data {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("osfr-navmesh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("nav.snav")
        let output = directory.appendingPathComponent("nav.mset")
        try source.write(to: input)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            "-c",
            "import sys,zlib; open(sys.argv[2],'wb').write(zlib.decompress(open(sys.argv[1],'rb').read()))",
            input.path,
            output.path
        ]
        do {
            try process.run()
        } catch {
            throw XCTSkip("python3 is unavailable for Linux zlib test inflation: \(error)")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw XCTSkip("python3 could not inflate the shipped navmesh")
        }
        return try Data(contentsOf: output)
    }
    #endif

    func testShippedFabledRealmsNavMeshParses() throws {
        let mesh = try loadShippedMesh()

        XCTAssertEqual(mesh.tileCount, 7_566)
        XCTAssertEqual(mesh.polygonCount, 308_264)
        XCTAssertEqual(mesh.maxVerticesPerPolygon, 6)
        XCTAssertEqual(mesh.maxTiles, 7_680)
        XCTAssertEqual(mesh.maxPolygons, 65_536)
        XCTAssertEqual(mesh.origin.x, -3072)
        XCTAssertEqual(mesh.origin.z, -2048)
        XCTAssertEqual(mesh.tileWidth, 64)
        XCTAssertEqual(mesh.tileHeight, 64)
    }

    func testShippedNavMeshFindsPacketIndependentWalkPath() throws {
        let mesh = try loadShippedMesh()
        let start = NavMeshSet.Point(x: -1904.883, y: -39.7098, z: 412.6024)
        let goal = NavMeshSet.Point(x: -1700, y: -39.7098, z: 412.6024)

        let startNode = try XCTUnwrap(mesh.nearestPolygon(to: start), "No decoded polygon near start")
        let goalNode = try XCTUnwrap(mesh.nearestPolygon(to: goal), "No decoded polygon near goal")
        XCTAssertNotEqual(startNode, goalNode)

        let path = try XCTUnwrap(mesh.findPath(from: start, to: goal), "No decoded polygon path")
        XCTAssertFalse(path.isEmpty)
        XCTAssertLessThan(path.count, 512)
        XCTAssertTrue(path.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        let first = try XCTUnwrap(path.first)
        let last = try XCTUnwrap(path.last)
        XCTAssertLessThan(abs(first.x - start.x), 64)
        XCTAssertLessThan(abs(first.z - start.z), 64)
        XCTAssertLessThan(abs(last.x - goal.x), 64)
        XCTAssertLessThan(abs(last.z - goal.z), 64)
    }

    func testSimulationUsesShippedNavMeshForOfflineWaypoints() throws {
        #if !canImport(Compression)
        throw XCTSkip("Simulation loads SNAV through Apple Compression; parser is covered above on Linux")
        #else
        guard let url = navmeshURL, FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("FabledRealms.navmesh is not available in this checkout")
        }
        let root = url
            .deletingLastPathComponent() // NavMeshes
            .deletingLastPathComponent() // Resources
            .deletingLastPathComponent() // SanctuaryResources
        let simulation = try WorldSimulation(rootURL: root, zoneID: 1)
        let route = simulation.navigationWaypoints(
            from: ZoneVector(x: -1904.883, y: -39.7098, z: 412.6024, w: 0),
            to: ZoneVector(x: -1700, y: -39.7098, z: 412.6024, w: 0)
        )
        let waypoints = try XCTUnwrap(route, "Simulation did not decode a real navmesh route")
        XCTAssertGreaterThan(waypoints.count, 1)
        XCTAssertTrue(waypoints.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        #endif
    }
}
