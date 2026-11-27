import Foundation

// MARK: - SNAV / DotRecast mesh-set reader
//
// Sanctuary loads `Resources/NavMeshes/<Zone>.navmesh` with
// `Sanctuary.Game.Pathing.NavMeshLoader`: an ASCII `SNAV` signature, a UInt32
// version, then a zlib stream containing a DotRecast `DtMeshSet`. The inspected
// shipped FabledRealms file is SNAV v1 -> MSET 0x8802 with 7,566 DNAV v0x8809
// tiles. This is a bounded, Foundation-only reader for that observed layout; it
// reconstructs polygon connectivity from the same `dtPoly.neis` values the C#
// `DtNavMesh.AddTile` uses rather than pretending to be a full Recast port.

enum NavMeshError: Error, LocalizedError, Equatable {
    case invalidSNAVHeader
    case unsupportedMeshSetVersion(UInt32)
    case truncated(String)
    case invalidTile(Int, String)
    case unsupportedTileVersion(Int32)
    case invalidPolygon(Int)

    var errorDescription: String? {
        switch self {
        case .invalidSNAVHeader:
            return "The navmesh does not begin with SNAV version 1."
        case .unsupportedMeshSetVersion(let version):
            return "Unsupported DotRecast mesh-set version 0x\(String(version, radix: 16))."
        case .truncated(let field):
            return "Truncated navmesh while reading \(field)."
        case .invalidTile(let index, let detail):
            return "Invalid navmesh tile \(index): \(detail)."
        case .unsupportedTileVersion(let version):
            return "Unsupported DNAV tile version \(version)."
        case .invalidPolygon(let index):
            return "Navmesh polygon \(index) references a vertex outside its tile."
        }
    }
}

/// The navmesh is a class because tiles are decoded lazily and cached; movement
/// is driven from one engine thread, so no locking is used here.
final class NavMeshSet {
    struct Point: Equatable, Sendable {
        var x: Float
        var y: Float
        var z: Float

        init(x: Float, y: Float, z: Float) {
            self.x = x
            self.y = y
            self.z = z
        }
    }

    struct Node: Hashable, Sendable {
        let tile: Int
        let polygon: Int
    }

    private struct GridKey: Hashable {
        let x: Int32
        let y: Int32
        let layer: Int32
    }

    private struct TileHeader {
        let index: Int
        let offset: Int
        let size: Int
        let gridX: Int32
        let gridY: Int32
        let layer: Int32
        let polygonCount: Int
        let vertexCount: Int
        let climb: Float
    }

    private struct MeshHeader {
        let version: Int32
        let polygonCount: Int
        let vertexCount: Int
        let climb: Float
    }

    private struct Polygon {
        var vertices: [Int]
        var neighbors: [Int]
        var isOffMesh: Bool
    }

    private struct OpenEntry {
        let node: Node
        let priority: Double
    }

    /// Binary min-heap for A*. The previous linear scan over the open set was
    /// quadratic in a burst of gateway-independent waypoint requests.
    private struct OpenHeap {
        private var entries: [OpenEntry] = []

        var isEmpty: Bool { entries.isEmpty }

        mutating func push(_ entry: OpenEntry) {
            entries.append(entry)
            var child = entries.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard entries[child].priority < entries[parent].priority else { break }
                entries.swapAt(child, parent)
                child = parent
            }
        }

        mutating func pop() -> OpenEntry? {
            guard let first = entries.first else { return nil }
            if entries.count == 1 {
                entries.removeLast()
                return first
            }
            entries[0] = entries.removeLast()
            var parent = 0
            while true {
                let left = parent * 2 + 1
                let right = left + 1
                var smallest = parent
                if left < entries.count, entries[left].priority < entries[smallest].priority {
                    smallest = left
                }
                if right < entries.count, entries[right].priority < entries[smallest].priority {
                    smallest = right
                }
                guard smallest != parent else { break }
                entries.swapAt(parent, smallest)
                parent = smallest
            }
            return first
        }
    }

    private struct Tile {
        let header: TileHeader
        let vertices: [Float]
        let polygons: [Polygon]
    }

    private let inflated: Data
    private var headers: [TileHeader] = []
    private var grid: [GridKey: Int] = [:]
    private var cache: [Int: Tile] = [:]

    private(set) var origin = Point(x: 0, y: 0, z: 0)
    private(set) var tileWidth: Float = 0
    private(set) var tileHeight: Float = 0
    private(set) var maxTiles: Int = 0
    private(set) var maxPolygons: Int = 0
    private(set) var maxVerticesPerPolygon: Int = 0
    private(set) var polygonCount: Int = 0

    var tileCount: Int { headers.count }

    convenience init(data: Data) throws {
        guard data.count > 12,
              data.starts(with: [0x53, 0x4e, 0x41, 0x56]), // "SNAV"
              try Self.u32(data, 4) == 1
        else {
            throw NavMeshError.invalidSNAVHeader
        }
        try self.init(inflated: try UdpLibrary.inflateZlib(data.subdata(in: 8..<data.count)))
    }

    /// Designated initializer over an already-inflated MSET payload. Tests use
    /// this to exercise the bounded parser where Apple's Compression framework
    /// is unavailable (Linux); production always enters through `init(data:)`.
    init(inflated: Data) throws {
        self.inflated = inflated

        try inflated.withUnsafeBytes { raw in
            guard raw.count >= 44 else { throw NavMeshError.truncated("MSET header") }
            let magic = try Self.u32(raw, 0)
            guard magic == 0x4d534554 else { throw NavMeshError.invalidSNAVHeader } // "MSET"
            let version = try Self.u32(raw, 4)
            guard version == 0x8802 || version == 0x8801 || version == 1 else {
                throw NavMeshError.unsupportedMeshSetVersion(version)
            }
            let tileCount = Int(try Self.u32(raw, 8))
            guard tileCount >= 0, tileCount <= 1_000_000 else {
                throw NavMeshError.truncated("tile count")
            }
            origin = Point(
                x: try Self.f32(raw, 12),
                y: try Self.f32(raw, 16),
                z: try Self.f32(raw, 20)
            )
            tileWidth = try Self.f32(raw, 24)
            tileHeight = try Self.f32(raw, 28)
            maxTiles = Int(try Self.u32(raw, 32))
            maxPolygons = Int(try Self.u32(raw, 36))
            guard tileWidth.isFinite, tileWidth > 0, tileHeight.isFinite, tileHeight > 0 else {
                throw NavMeshError.truncated("tile size")
            }

            // The MSET option is immediately followed by `maxVertsPerPoly`
            // only for the recast4j 0x8802 set version; `SNAV v1` with a C
            // mesh set or 0x8801 omits it. Tile versions are checked per tile.
            var offset = 40
            if version == 0x8802 {
                let maximum = Int(try Self.u32(raw, offset))
                offset += 4
                guard maximum >= 3, maximum <= 6 else {
                    throw NavMeshError.truncated("max vertices per polygon")
                }
                maxVerticesPerPolygon = maximum
            } else {
                maxVerticesPerPolygon = 6
            }

            var parsed: [TileHeader] = []
            parsed.reserveCapacity(tileCount)
            for index in 0..<tileCount {
                guard offset + 12 <= raw.count else {
                    throw NavMeshError.truncated("tile \(index) header")
                }
                // DtMeshSetReader reads a 64-bit tile ref followed by an Int32
                // data size. There is no C padding for recast4j versions.
                offset += 8
                let size = Int(try Self.u32(raw, offset))
                offset += 4
                let start = offset
                guard size > 0, start >= 0, start + size <= raw.count else {
                    throw NavMeshError.truncated("tile \(index) payload")
                }
                let mesh = try Self.readMeshHeader(raw, at: start, tile: index)
                parsed.append(TileHeader(
                    index: index,
                    offset: start,
                    size: size,
                    gridX: try Self.i32(raw, start + 8),
                    gridY: try Self.i32(raw, start + 12),
                    layer: try Self.i32(raw, start + 16),
                    polygonCount: mesh.polygonCount,
                    vertexCount: mesh.vertexCount,
                    climb: mesh.climb
                ))
                offset = start + size
            }
            headers = parsed
            polygonCount = parsed.reduce(0) { $0 + $1.polygonCount }
        }

        var byGrid: [GridKey: Int] = [:]
        byGrid.reserveCapacity(headers.count)
        for header in headers {
            let key = GridKey(x: header.gridX, y: header.gridY, layer: header.layer)
            if byGrid[key] == nil { byGrid[key] = header.index }
        }
        grid = byGrid
    }

    private static func readMeshHeader(
        _ raw: UnsafeRawBufferPointer,
        at start: Int,
        tile: Int
    ) throws -> MeshHeader {
        guard start + 100 <= raw.count else {
            throw NavMeshError.truncated("tile \(tile) mesh header")
        }
        guard try u32(raw, start) == 0x444e4156 else { // "DNAV"
            throw NavMeshError.invalidTile(tile, "invalid magic")
        }
        let version = try i32(raw, start + 4)
        guard version == 0x8809 || version == 0x8808 || version == 0x8807 else {
            throw NavMeshError.unsupportedTileVersion(version)
        }
        return MeshHeader(
            version: version,
            polygonCount: Int(try u32(raw, start + 24)),
            vertexCount: Int(try u32(raw, start + 28)),
            climb: try f32(raw, start + 68)
        )
    }

    private func tile(_ index: Int) throws -> Tile {
        if let cached = cache[index] { return cached }
        guard headers.indices.contains(index) else {
            throw NavMeshError.invalidTile(index, "out of range")
        }
        let header = headers[index]
        let version = try Self.i32(inflated, header.offset + 4)
        let decoded = try inflated.withUnsafeBytes { raw -> Tile in
            var cursor = header.offset + 100
            let end = header.offset + header.size
            var vertices: [Float] = []
            vertices.reserveCapacity(header.vertexCount * 3)
            for _ in 0..<header.vertexCount {
                guard cursor + 12 <= end, cursor + 12 <= raw.count else {
                    throw NavMeshError.truncated("tile \(index) vertices")
                }
                vertices.append(try Self.f32(raw, cursor))
                vertices.append(try Self.f32(raw, cursor + 4))
                vertices.append(try Self.f32(raw, cursor + 8))
                cursor += 12
            }

            var polygons: [Polygon] = []
            polygons.reserveCapacity(header.polygonCount)
            for polyIndex in 0..<header.polygonCount {
                // DotRecast 0x8807 stores `firstLink` before the vertex list;
                // 0x8808+ removes it. Either way the six vertex and six
                // neighbor shorts are followed by flags, count, and area/type.
                let hasFirstLink = version == 0x8807
                let stride = hasFirstLink ? 32 : 28
                guard cursor + stride <= end, cursor + stride <= raw.count else {
                    throw NavMeshError.truncated("tile \(index) polygon \(polyIndex)")
                }
                if hasFirstLink { cursor += 4 }
                var verts: [Int] = []
                var neis: [Int] = []
                verts.reserveCapacity(6)
                neis.reserveCapacity(6)
                for slot in 0..<6 {
                    verts.append(Int(try Self.u16(raw, cursor + slot * 2)))
                }
                cursor += 12
                for slot in 0..<6 {
                    neis.append(Int(try Self.u16(raw, cursor + slot * 2)))
                }
                cursor += 12
                _ = try Self.u16(raw, cursor) // flags
                let count = Int(raw[cursor + 2])
                let areaAndType = Int(raw[cursor + 3])
                cursor += 4
                guard count >= 3, count <= maxVerticesPerPolygon else {
                    throw NavMeshError.invalidPolygon(polyIndex)
                }
                for slot in 0..<count where verts[slot] >= header.vertexCount {
                    throw NavMeshError.invalidPolygon(polyIndex)
                }
                polygons.append(Polygon(
                    vertices: Array(verts[0..<count]),
                    neighbors: Array(neis[0..<count]),
                    isOffMesh: (areaAndType & 0xc0) == 0x40
                ))
            }
            return Tile(header: header, vertices: vertices, polygons: polygons)
        }
        cache[index] = decoded
        return decoded
    }

    /// Finds the closest polygon in tiles overlapping an extent box. This is a
    /// simplified `DtNavMeshQuery.FindNearestPoly`: it uses polygon edges in the
    /// X/Z plane and keeps Y only as a penalty, which is sufficient for the
    /// offline 2D movement surface used by the launcher.
    func nearestPolygon(
        to point: Point,
        extents: Point = Point(x: 48, y: 256, z: 48)
    ) -> Node? {
        let minX = point.x - abs(extents.x)
        let maxX = point.x + abs(extents.x)
        let minZ = point.z - abs(extents.z)
        let maxZ = point.z + abs(extents.z)
        let minTileX = Int(floor((Double(minX) - Double(origin.x)) / Double(tileWidth)))
        let maxTileX = Int(floor((Double(maxX) - Double(origin.x)) / Double(tileWidth)))
        let minTileY = Int(floor((Double(minZ) - Double(origin.z)) / Double(tileHeight)))
        let maxTileY = Int(floor((Double(maxZ) - Double(origin.z)) / Double(tileHeight)))

        var best: Node?
        var bestScore = Float.infinity
        for x in minTileX...maxTileX {
            for y in minTileY...maxTileY {
                for layer in Int32(0)...Int32(1) {
                    guard let index = grid[GridKey(x: Int32(x), y: Int32(y), layer: layer)],
                          let loaded = try? tile(index)
                    else { continue }
                    for (polyIndex, polygon) in loaded.polygons.enumerated() where !polygon.isOffMesh {
                        let closest = closestPoint(on: polygon, in: loaded, to: point)
                        let dx = closest.x - point.x
                        let dz = closest.z - point.z
                        let dy = closest.y - point.y
                        let score = dx * dx + dz * dz + dy * dy * 0.25
                        if score < bestScore {
                            bestScore = score
                            best = Node(tile: index, polygon: polyIndex)
                        }
                    }
                }
            }
        }
        return best
    }

    /// A* over the decoded polygon graph. The result is a sequence of polygon
    /// centroids ending at the closest point on the goal polygon. `nil` means
    /// no decoded graph path was found; callers then fall back to direct tile
    /// movement instead of inventing coordinates.
    func findPath(
        from start: Point,
        to goal: Point,
        maximumExpandedNodes: Int = 20_000
    ) throws -> [Point]? {
        guard let startNode = nearestPolygon(to: start),
              let goalNode = nearestPolygon(to: goal)
        else { return nil }

        var cameFrom: [Node: Node] = [:]
        var bestCost: [Node: Double] = [startNode: 0]
        var closed: Set<Node> = []
        var open = OpenHeap()
        open.push(OpenEntry(node: startNode, priority: 0))
        var expanded = 0

        while let next = open.pop() {
            let current = next.node
            if closed.contains(current) { continue }
            if current == goalNode {
                var nodes: [Node] = [current]
                var cursor = current
                while let previous = cameFrom[cursor] {
                    nodes.append(previous)
                    cursor = previous
                }
                nodes.reverse()
                var result: [Point] = nodes.compactMap { try? centroid(of: $0) }
                // Detour's straight-path begins at the closest point on the
                // start polygon, not at that polygon's centroid.
                if let startPolylineBegin = try? closestPointOnPolygon(startNode, to: start) {
                    if !result.isEmpty,
                       Self.distance(result[0], startPolylineBegin) > 0.25 {
                        result[0] = startPolylineBegin
                    } else if result.isEmpty {
                        result.append(startPolylineBegin)
                    }
                }
                if let goalPolylineEnd = try? closestPointOnPolygon(goalNode, to: goal) {
                    if let last = result.last,
                       Self.distance(last, goalPolylineEnd) > 0.25 {
                        result.append(goalPolylineEnd)
                    } else if result.isEmpty {
                        result.append(goalPolylineEnd)
                    }
                }
                return result.isEmpty ? nil : result
            }
            closed.insert(current)
            expanded += 1
            guard expanded <= maximumExpandedNodes else { return nil }

            let loaded = try tile(current.tile)
            let currentCenter = centroid(loaded.polygons[current.polygon], in: loaded)
            let currentCost = bestCost[current] ?? .infinity
            for neighbor in try neighbors(of: current, in: loaded) where !closed.contains(neighbor) {
                let neighborLoaded = try tile(neighbor.tile)
                let neighborCenter = centroid(neighborLoaded.polygons[neighbor.polygon], in: neighborLoaded)
                let tentative = currentCost + Double(Self.distance(currentCenter, neighborCenter))
                guard tentative < (bestCost[neighbor] ?? .infinity) else { continue }
                bestCost[neighbor] = tentative
                cameFrom[neighbor] = current
                open.push(OpenEntry(
                    node: neighbor,
                    priority: tentative + Double(Self.distance(neighborCenter, goal))
                ))
            }
        }
        return nil
    }

    func centroid(of node: Node) throws -> Point {
        let loaded = try tile(node.tile)
        guard loaded.polygons.indices.contains(node.polygon) else {
            throw NavMeshError.invalidPolygon(node.polygon)
        }
        return centroid(loaded.polygons[node.polygon], in: loaded)
    }

    private func closestPointOnPolygon(_ node: Node, to point: Point) throws -> Point {
        let loaded = try tile(node.tile)
        guard loaded.polygons.indices.contains(node.polygon) else {
            throw NavMeshError.invalidPolygon(node.polygon)
        }
        return closestPoint(on: loaded.polygons[node.polygon], in: loaded, to: point)
    }

    private func centroid(_ polygon: Polygon, in tile: Tile) -> Point {
        var x: Float = 0
        var y: Float = 0
        var z: Float = 0
        for index in polygon.vertices {
            let base = index * 3
            guard base + 2 < tile.vertices.count else { continue }
            x += tile.vertices[base]
            y += tile.vertices[base + 1]
            z += tile.vertices[base + 2]
        }
        let divisor = Float(max(1, polygon.vertices.count))
        return Point(x: x / divisor, y: y / divisor, z: z / divisor)
    }

    private func closestPoint(on polygon: Polygon, in tile: Tile, to point: Point) -> Point {
        var best = Point(x: 0, y: 0, z: 0)
        var bestDistance = Float.infinity
        for edge in polygon.vertices.indices {
            let next = polygon.vertices[(edge + 1) % polygon.vertices.count]
            let a = vertex(polygon.vertices[edge], in: tile)
            let b = vertex(next, in: tile)
            let candidate = closestPoint(onSegment: (a, b), to: point)
            let dx = candidate.x - point.x
            let dz = candidate.z - point.z
            let dy = candidate.y - point.y
            let distance = dx * dx + dz * dz + dy * dy * 0.25
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        return best
    }

    private func closestPoint(onSegment segment: (Point, Point), to point: Point) -> Point {
        let ax = Double(segment.0.x), az = Double(segment.0.z)
        let bx = Double(segment.1.x), bz = Double(segment.1.z)
        let px = Double(point.x), pz = Double(point.z)
        let vx = bx - ax, vz = bz - az
        let lengthSquared = vx * vx + vz * vz
        let rawT = lengthSquared > 0 ? ((px - ax) * vx + (pz - az) * vz) / lengthSquared : 0
        let t = min(max(rawT, 0), 1)
        return Point(
            x: Float(ax + vx * t),
            y: segment.0.y + (segment.1.y - segment.0.y) * Float(t),
            z: Float(az + vz * t)
        )
    }

    private func vertex(_ index: Int, in tile: Tile) -> Point {
        let base = index * 3
        guard base + 2 < tile.vertices.count else { return Point(x: 0, y: 0, z: 0) }
        return Point(x: tile.vertices[base], y: tile.vertices[base + 1], z: tile.vertices[base + 2])
    }

    /// Internal neighbors are stored as `polygon index + 1`. External neighbors
    /// store `DT_EXT_LINK | side`; Sanctuary/DotRecast rebuilds those by matching
    /// portal edges in the adjacent tile. This implements that same edge match
    /// for the decoded geometry without serializing Detour's mutable link pool.
    private func neighbors(of node: Node, in tile: Tile) throws -> [Node] {
        guard tile.polygons.indices.contains(node.polygon) else { return [] }
        let polygon = tile.polygons[node.polygon]
        var result: Set<Node> = []
        let directions: [(Int32, Int32)] = [
            (1, 0), (1, 1), (0, 1), (-1, 1),
            (-1, 0), (-1, -1), (0, -1), (1, -1)
        ]

        for edge in polygon.neighbors.indices {
            let neighbor = polygon.neighbors[edge]
            if neighbor == 0 { continue }
            if neighbor & 0x8000 != 0 {
                let side = neighbor & 0xff
                guard side >= 0, side < directions.count,
                      let adjacentIndex = grid[GridKey(
                          x: tile.header.gridX + directions[side].0,
                          y: tile.header.gridY + directions[side].1,
                          layer: tile.header.layer
                      )]
                else { continue }
                let adjacent = try self.tile(adjacentIndex)
                let a = vertex(polygon.vertices[edge], in: tile)
                let b = vertex(polygon.vertices[(edge + 1) % polygon.vertices.count], in: tile)
                // DotRecast's FindConnectingPolys looks for candidate edges on
                // the opposite side whose portal slab overlaps this edge. The
                // endpoint values need not match: adjacent tiles often have a
                // different number of portals along the shared boundary.
                let oppositeSide = (side + 4) & 0x7
                let requiredNeighbor = 0x8000 | oppositeSide
                let currentSlab = Self.slab(a, b, side)
                for (candidateIndex, candidate) in adjacent.polygons.enumerated() where !candidate.isOffMesh {
                    for candidateEdge in candidate.vertices.indices where candidate.neighbors[candidateEdge] == requiredNeighbor {
                        let c = vertex(candidate.vertices[candidateEdge], in: adjacent)
                        let d = vertex(candidate.vertices[(candidateEdge + 1) % candidate.vertices.count], in: adjacent)
                        let candidateSlab = Self.slab(c, d, oppositeSide)
                        let climb = max(tile.header.climb, adjacent.header.climb)
                        if Self.slabsOverlap(currentSlab, candidateSlab, climb: climb) {
                            result.insert(Node(tile: adjacentIndex, polygon: candidateIndex))
                        }
                    }
                }
            } else {
                let index = neighbor - 1
                guard tile.polygons.indices.contains(index), !tile.polygons[index].isOffMesh else { continue }
                result.insert(Node(tile: node.tile, polygon: index))
            }
        }
        return Array(result)
    }

    private struct PortalSlab {
        let position: Float
        let minimum: Float
        let maximum: Float
        let yMinimum: Float
        let yMaximum: Float
    }

    private static func slab(_ a: Point, _ b: Point, _ side: Int) -> PortalSlab {
        switch side {
        case 0, 4:
            return PortalSlab(
                position: (a.x + b.x) * 0.5,
                minimum: min(a.z, b.z),
                maximum: max(a.z, b.z),
                yMinimum: min(a.y, b.y),
                yMaximum: max(a.y, b.y)
            )
        case 2, 6:
            return PortalSlab(
                position: (a.z + b.z) * 0.5,
                minimum: min(a.x, b.x),
                maximum: max(a.x, b.x),
                yMinimum: min(a.y, b.y),
                yMaximum: max(a.y, b.y)
            )
        default:
            return PortalSlab(position: 0, minimum: 0, maximum: 0, yMinimum: 0, yMaximum: 0)
        }
    }

    private static func slabsOverlap(_ a: PortalSlab, _ b: PortalSlab, climb: Float) -> Bool {
        guard abs(a.position - b.position) <= 0.01 else { return false }
        let lower = max(a.minimum + 0.01, b.minimum + 0.01)
        let upper = min(a.maximum - 0.01, b.maximum - 0.01)
        guard lower <= upper else { return false }
        return max(a.yMinimum, b.yMinimum) <= min(a.yMaximum, b.yMaximum) + max(climb, 0.5)
    }

    private static func distance(_ a: Point, _ b: Point) -> Float {
        let dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    // MARK: Bounded primitive reads

    private static func u16(_ data: Data, _ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { throw NavMeshError.truncated("UInt16") }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func u32(_ data: Data, _ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { throw NavMeshError.truncated("UInt32") }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func u16(_ buffer: UnsafeRawBufferPointer, _ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= buffer.count else { throw NavMeshError.truncated("UInt16") }
        return UInt16(buffer[offset]) | (UInt16(buffer[offset + 1]) << 8)
    }

    private static func u32(_ buffer: UnsafeRawBufferPointer, _ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= buffer.count else { throw NavMeshError.truncated("UInt32") }
        return UInt32(buffer[offset])
            | (UInt32(buffer[offset + 1]) << 8)
            | (UInt32(buffer[offset + 2]) << 16)
            | (UInt32(buffer[offset + 3]) << 24)
    }

    private static func i32(_ buffer: UnsafeRawBufferPointer, _ offset: Int) throws -> Int32 {
        Int32(bitPattern: try u32(buffer, offset))
    }

    private static func i32(_ data: Data, _ offset: Int) throws -> Int32 {
        Int32(bitPattern: try u32(data, offset))
    }

    private static func f32(_ buffer: UnsafeRawBufferPointer, _ offset: Int) throws -> Float {
        Float(bitPattern: try u32(buffer, offset))
    }
}
