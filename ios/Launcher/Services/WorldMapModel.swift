import Foundation

/// One labelled atlas destination from `Resources/PointOfInterests.json`.
struct WorldPointOfInterest: Codable, Equatable, Identifiable {
    let id: Int
    let name: String
    let position: ZoneVector
    let spawnPosition: ZoneVector
    let atlasName: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Comment"
        case position = "Position"
        case spawnPosition = "SpawnPosition"
        case atlasName = "AtlasName"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Destination \(id)"
        position = try c.decodeIfPresent(ZoneVector.self, forKey: .position) ?? .zero
        spawnPosition = try c.decodeIfPresent(ZoneVector.self, forKey: .spawnPosition) ?? position
        atlasName = try c.decodeIfPresent(String.self, forKey: .atlasName) ?? ""
    }
}

/// Everything the native world player needs to draw and navigate a zone.
///
/// Coordinate conventions follow Sanctuary's `BaseZone`: longitude comes from
/// world Z and latitude from world X, both divided by the zone's tile size.
struct WorldMap: Equatable {
    let zone: ZoneDefinition
    let environment: ZoneEnvironmentGrid
    let pointsOfInterest: [WorldPointOfInterest]

    /// Number of grid cells along world Z (the vertical axis of the atlas map).
    var longitudeCount: Int { environment.rows.count }
    /// Number of grid cells along world X (the horizontal axis of the atlas map).
    var latitudeCount: Int { environment.rows.first?.count ?? 0 }

    /// Environment id at a grid-relative tile coordinate.
    func environmentID(longitude: Int, latitude: Int) -> Int {
        environment.environmentID(
            longitude: zone.startLongitude + longitude,
            latitude: zone.startLatitude + latitude
        )
    }

    func environmentName(id: Int) -> String {
        environment.environmentNames[id] ?? (id == -1 ? "Out of bounds" : "Environment \(id)")
    }

    /// Centre of a tile in world space. Sanctuary's zone grid starts at
    /// `StartLatitude`/`StartLongitude`, not at world origin.
    func tilePosition(longitude: Int, latitude: Int) -> ZoneVector {
        ZoneVector(
            x: (Double(zone.startLatitude + latitude) + 0.5) * zone.tileSize,
            y: zone.spawnPosition.y,
            z: (Double(zone.startLongitude + longitude) + 0.5) * zone.tileSize,
            w: 0
        )
    }

    /// Grid-relative tile containing a world position.
    func tile(for position: ZoneVector) -> (longitude: Int, latitude: Int) {
        (
            Int(floor(position.z / zone.tileSize)) - zone.startLongitude,
            Int(floor(position.x / zone.tileSize)) - zone.startLatitude
        )
    }

    /// Normalised map coordinates in `0..<1`, or `nil` outside the grid.
    func unitPosition(for position: ZoneVector) -> (x: Double, y: Double)? {
        let latitude = position.x / zone.tileSize - Double(zone.startLatitude)
        let longitude = position.z / zone.tileSize - Double(zone.startLongitude)
        guard
            latitudeCount > 0, longitudeCount > 0,
            latitude >= 0, latitude <= Double(latitudeCount),
            longitude >= 0, longitude <= Double(longitudeCount)
        else { return nil }
        return (latitude / Double(latitudeCount), longitude / Double(longitudeCount))
    }

    /// World position at normalised map coordinates, clamped to the grid.
    func worldPosition(unitX: Double, unitY: Double) -> ZoneVector {
        let clampedX = min(max(unitX, 0), 0.999999)
        let clampedY = min(max(unitY, 0), 0.999999)
        return ZoneVector(
            x: (Double(zone.startLatitude) + clampedX * Double(max(latitudeCount, 1))) * zone.tileSize,
            y: zone.spawnPosition.y,
            z: (Double(zone.startLongitude) + clampedY * Double(max(longitudeCount, 1))) * zone.tileSize,
            w: 0
        )
    }

    /// Walks outward from a clicked tile until a traversable cell is found.
    func walkableUnit(near unitX: Double, unitY: Double, radius: Int = 4) -> (x: Double, y: Double)? {
        let point = worldPosition(unitX: unitX, unitY: unitY)
        let origin = tile(for: point)
        if environmentID(longitude: origin.longitude, latitude: origin.latitude) != -1 {
            return unitPosition(for: point)
        }
        for distance in 1...radius {
            for longitudeOffset in -distance...distance {
                for latitudeOffset in -distance...distance {
                    guard abs(longitudeOffset) == distance || abs(latitudeOffset) == distance else { continue }
                    let longitude = origin.longitude + longitudeOffset
                    let latitude = origin.latitude + latitudeOffset
                    guard environmentID(longitude: longitude, latitude: latitude) != -1 else { continue }
                    let candidate = tilePosition(longitude: longitude, latitude: latitude)
                    return unitPosition(for: candidate)
                }
            }
        }
        return nil
    }
}

enum WorldMapError: LocalizedError, Equatable {
    case missingZone(String)
    case missingEnvironment(String)
    case unsafePath(String)

    var errorDescription: String? {
        switch self {
        case .missingZone(let name): return "Zone definition not found: \(name)"
        case .missingEnvironment(let name): return "Environment grid not found: \(name)"
        case .unsafePath(let path): return "Unsafe resource path: \(path)"
        }
    }
}

/// Loads the world map from a bundled Sanctuary resource tree.
enum WorldMapLoader {
    static func load(rootURL: URL) throws -> WorldMap {
        let catalog = try ResourceCatalog(rootURL: rootURL)
        guard let zone = catalog.zones.first(where: { $0.name == "FabledRealms" }) ?? catalog.zones.first else {
            throw WorldMapError.missingZone("FabledRealms")
        }
        guard let environment = catalog.zoneEnvironments[zone.name] ?? catalog.zoneEnvironments.values.first else {
            throw WorldMapError.missingEnvironment(zone.name)
        }

        let poiURL: URL
        do {
            poiURL = try SafePath.contained(base: rootURL, components: ["Resources", "PointOfInterests.json"])
        } catch {
            throw WorldMapError.unsafePath("Resources/PointOfInterests.json")
        }

        var points: [WorldPointOfInterest] = []
        if FileManager.default.fileExists(atPath: poiURL.path) {
            let data = try Data(contentsOf: poiURL)
            points = try JSONDecoder().decode([WorldPointOfInterest].self, from: data)
        }

        return WorldMap(zone: zone, environment: environment, pointsOfInterest: points)
    }
}
