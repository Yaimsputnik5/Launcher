import Foundation
import XCTest
@testable import OSFRCore

final class WorldMapTests: XCTestCase {
    private var tempRoots: [URL] = []

    override func tearDown() {
        for root in tempRoots {
            try? FileManager.default.removeItem(at: root)
        }
        tempRoots.removeAll()
        super.tearDown()
    }

    private func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WorldMapTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempRoots.append(url)
        return url
    }

    private func write(_ text: String, relativePath: String, in root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func makeMap() throws -> WorldMap {
        let root = try makeRoot()
        try write(Self.zoneJSON, relativePath: "Zones/FabledRealms.json", in: root)
        try write(Self.environmentJSON, relativePath: "Zones/Environments/FabledRealms.json", in: root)
        try write(Self.poiJSON, relativePath: "Resources/PointOfInterests.json", in: root)
        return try WorldMapLoader.load(rootURL: root)
    }

    func testLoadsZoneGridAndDestinations() throws {
        let map = try makeMap()

        XCTAssertEqual(map.zone.name, "FabledRealms")
        XCTAssertEqual(map.longitudeCount, 2)
        XCTAssertEqual(map.latitudeCount, 2)
        XCTAssertEqual(map.environmentID(longitude: 1, latitude: 0), 10)
        XCTAssertEqual(map.environmentID(longitude: 0, latitude: 0), -1)
        XCTAssertEqual(map.environmentName(id: 10), "Blackspore")
        XCTAssertEqual(map.environmentName(id: -1), "OutOfBounds")

        XCTAssertEqual(map.pointsOfInterest.count, 1)
        let poi = try XCTUnwrap(map.pointsOfInterest.first)
        XCTAssertEqual(poi.id, 3)
        XCTAssertEqual(poi.name, "Snowhill")
        XCTAssertEqual(poi.position.x, 32)
        XCTAssertEqual(poi.atlasName, "sacredgrove")
    }

    func testTileUnitAndWorldConversionsRoundTrip() throws {
        let map = try makeMap()
        let position = map.tilePosition(longitude: 1, latitude: 0)

        XCTAssertEqual(position.x, -3040)
        XCTAssertEqual(position.z, -1952)
        let tile = map.tile(for: position)
        XCTAssertEqual(tile.longitude, 1)
        XCTAssertEqual(tile.latitude, 0)

        let unit = try XCTUnwrap(map.unitPosition(for: position))
        XCTAssertEqual(unit.x, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(unit.y, 0.75, accuracy: 0.000_001)

        let restored = map.worldPosition(unitX: unit.x, unitY: unit.y)
        XCTAssertEqual(restored.x, position.x)
        XCTAssertEqual(restored.z, position.z)
    }

    func testOutsideGridHasNoUnitPosition() throws {
        let map = try makeMap()
        let outside = ZoneVector(x: 10_000, y: 0, z: 10_000, w: 0)
        XCTAssertNil(map.unitPosition(for: outside))
    }

    func testWalkableUnitSnapsOutOfBoundsClick() throws {
        let map = try makeMap()
        // Longitude 0, latitude 0 is out of bounds; (0, 1) is walkable.
        let snapped = try XCTUnwrap(map.walkableUnit(near: 0.25, unitY: 0.25))
        let position = map.worldPosition(unitX: snapped.x, unitY: snapped.y)
        let tile = map.tile(for: position)
        XCTAssertEqual(map.environmentID(longitude: tile.longitude, latitude: tile.latitude), 10)
    }

    func testMissingZoneIsReported() throws {
        let root = try makeRoot()
        try write(Self.environmentJSON, relativePath: "Zones/Environments/FabledRealms.json", in: root)
        XCTAssertThrowsError(try WorldMapLoader.load(rootURL: root)) { error in
            XCTAssertEqual(error as? WorldMapError, .missingZone("FabledRealms"))
        }
    }

    private static let zoneJSON = """
    {
      "$type": "World",
      "Id": 1,
      "Name": "FabledRealms",
      "Type": "World",
      "TileSize": 64,
      "StartLatitude": -48,
      "StartLongitude": -32,
      "EndLatitude": 2,
      "EndLongitude": 2,
      "SpawnPosition": [-3040, -39.7098, -1952],
      "SpawnRotation": [0.55, 0.83],
      "Scripts": ["FabledRealms"],
      "EnabledClientAreaIds": [],
      "SeasonalClientAreas": [],
      "AreaDefinitions": []
    }
    """

    private static let environmentJSON = """
    {
      "Environments": { "-1": "OutOfBounds", "10": "Blackspore" },
      "StartLongitude": -32,
      "StartLatitude": -48,
      "Rows": [[-1, 10], [10, -1]]
    }
    """

    private static let poiJSON = """
    [
      {
        "Id": 3,
        "Comment": "Snowhill",
        "Position": [32, 30.987, 96],
        "SpawnPosition": [40, 30.987, 100],
        "IconId": 1345,
        "AtlasName": "sacredgrove"
      }
    ]
    """
}
