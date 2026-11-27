import Foundation

/// Errors for the original client's `.gzne` zone-definition files.
public enum ClientZoneError: Error, LocalizedError, Equatable {
    case invalidMagic
    case unsupportedVersion(UInt32)
    case truncated(field: String, expected: Int, available: Int)
    case invalidString(field: String)
    case limitExceeded(field: String, limit: Int)
    case resourceNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMagic:
            return "Zone definition is missing the 'GZNE' magic."
        case .unsupportedVersion(let version):
            return "Unsupported GZNE version \(version); expected 2 or 3."
        case .truncated(let field, let expected, let available):
            return "Truncated \(field): needed \(expected) byte(s), \(available) available."
        case .invalidString(let field):
            return "Invalid null-terminated string for \(field)."
        case .limitExceeded(let field, let limit):
            return "\(field) exceeds the parser limit of \(limit)."
        case .resourceNotFound(let path):
            return "Client resource not found: \(path)."
        }
    }
}

/// One flora variant attached to a ground material in a `.gzne` file.
///
/// The floating-point fields are stored verbatim. Their gameplay meaning is
/// not inferred here; material name, texture name, and channel byte are the
/// evidence-backed values used by the renderer.
public struct ZoneFloraDefinition: Equatable, Sendable {
    public let channel: UInt8
    public let density: Float
    public let scale: Float
    public let variation: Float
    public let name: String
}

/// One ground material record from the zone material table.
public struct ZoneMaterialDefinition: Equatable, Sendable {
    public let index: UInt32
    public let flags: UInt32
    public let name: String
    public let textureName: String
    public let flora: [ZoneFloraDefinition]
}

/// Parsed header and material table from a real client zone definition.
///
/// `FabledRealms.gzne` is version 3: 12 header fields after the magic, then a
/// material table whose records are `{name, texture, flags, floraCount,
/// flora[floraCount], index}`. Version 2 has one fewer bounds field and a
/// trailing timestamp; both layouts were confirmed against shipped zones.
public struct ClientZoneManifest: Equatable, Sendable {
    public let version: UInt32
    public let unknownHeaderValue: UInt32
    public let tileResolution: UInt32
    public let tileWorldSize: Float
    public let flags: UInt32
    public let minChunkX: Int32
    public let minChunkY: Int32
    public let maxChunkX: Int32
    public let maxChunkY: Int32
    public let checksum: UInt32
    public let materials: [ZoneMaterialDefinition]
    /// Byte offset where the next zone section begins after the material table.
    public let payloadOffset: Int

    public func material(named name: String) -> ZoneMaterialDefinition? {
        materials.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func material(index: UInt32) -> ZoneMaterialDefinition? {
        materials.first { $0.index == index }
    }
}

/// Explicit mapping for zones whose container entry has been verified.
public enum ClientZoneCatalog {
    public static func zonePath(forZoneName zoneName: String) -> String? {
        switch zoneName.lowercased() {
        case "fabledrealms":
            return "Assets_004.pack#FabledRealms.gzne"
        default:
            return nil
        }
    }
}

/// Reads raw bytes from the embedded client store or an injected lookup.
///
/// It shares the `archive#entry` syntax with `TextureLoader` but returns bytes
/// instead of decoded images, so non-image zone data can be parsed.
public struct ClientAssetDataLoader {
    public typealias Lookup = @Sendable (String) -> Data?

    private let lookup: Lookup?

    public init(lookup: Lookup? = nil) {
        if let lookup {
            self.lookup = lookup
        } else {
            self.lookup = { ClientAssetStore.shared.data(for: $0) }
        }
    }

    public func data(relativePath: String) throws -> Data {
        let parts = relativePath.split(
            separator: "#", maxSplits: 1, omittingEmptySubsequences: false
        )
        let archivePath = String(parts[0])
        let entryName = parts.count == 2 ? String(parts[1]) : nil
        guard let archiveData = lookup?(archivePath) else {
            throw ClientZoneError.resourceNotFound(relativePath)
        }
        guard let entryName, !entryName.isEmpty else { return archiveData }
        guard (archivePath as NSString).pathExtension.lowercased() == "pack" else {
            throw ClientZoneError.resourceNotFound(relativePath)
        }
        let archive = try PackArchive(archiveData)
        return try archive.payload(named: entryName)
    }

    public func zoneManifest(forZoneName zoneName: String) throws -> ClientZoneManifest {
        guard let path = ClientZoneCatalog.zonePath(forZoneName: zoneName) else {
            throw ClientZoneError.resourceNotFound(zoneName)
        }
        return try ClientZoneManifest(data: data(relativePath: path))
    }
}

// MARK: - Parser

extension ClientZoneManifest {
    private enum Limits {
        static let maxMaterials = 4_096
        static let maxFloraPerMaterial = 256
        static let maxStringBytes = 4_096
    }

    private struct Reader {
        let bytes: [UInt8]
        private(set) var offset: Int

        init(_ data: Data, offset: Int = 0) {
            self.bytes = [UInt8](data)
            self.offset = offset
        }

        mutating func advance(_ length: Int, field: String) throws {
            guard length >= 0, offset >= 0, length <= bytes.count - offset else {
                throw ClientZoneError.truncated(
                    field: field, expected: length,
                    available: offset >= 0 && offset <= bytes.count ? bytes.count - offset : 0
                )
            }
            offset += length
        }

        mutating func u32(_ field: String) throws -> UInt32 {
            try advance(4, field: field)
            var value: UInt32 = 0
            for index in 0..<4 {
                value |= UInt32(bytes[offset - 4 + index]) << (8 * index)
            }
            return value
        }

        mutating func i32(_ field: String) throws -> Int32 {
            Int32(bitPattern: try u32(field))
        }

        mutating func f32(_ field: String) throws -> Float {
            Float(bitPattern: try u32(field))
        }

        mutating func byte(_ field: String) throws -> UInt8 {
            try advance(1, field: field)
            return bytes[offset - 1]
        }

        mutating func cString(_ field: String) throws -> String {
            let start = offset
            var end = start
            while end < bytes.count, bytes[end] != 0 {
                end += 1
                guard end - start <= Limits.maxStringBytes else {
                    throw ClientZoneError.limitExceeded(
                        field: field, limit: Limits.maxStringBytes
                    )
                }
            }
            guard end < bytes.count else {
                throw ClientZoneError.invalidString(field: field)
            }
            let slice = bytes[start..<end]
            guard let value = String(bytes: slice, encoding: .utf8), !value.isEmpty else {
                throw ClientZoneError.invalidString(field: field)
            }
            offset = end + 1
            return value
        }

        func fourCC(_ field: String) throws -> String {
            guard bytes.count >= 4 else {
                throw ClientZoneError.truncated(field: field, expected: 4, available: bytes.count)
            }
            return String(bytes: bytes[0..<4], encoding: .ascii) ?? ""
        }
    }

    public init(data: Data) throws {
        var reader = Reader(data)
        guard try reader.fourCC("GZNE magic") == "GZNE" else {
            throw ClientZoneError.invalidMagic
        }
        _ = try reader.u32("magic")
        let version = try reader.u32("version")

        let header: Header
        switch version {
        case 2:
            header = Header(
                unknownHeaderValue: 0,
                tileResolution: try reader.u32("tile resolution"),
                tileWorldSize: try reader.f32("tile world size"),
                flags: try reader.u32("flags"),
                minChunkX: try reader.i32("minimum chunk X"),
                minChunkY: try reader.i32("minimum chunk Y"),
                maxChunkX: try reader.i32("maximum chunk X"),
                maxChunkY: try reader.i32("maximum chunk Y"),
                checksum: try reader.u32("checksum"),
                materialCount: try reader.u32("material count"),
                materialTableOffset: 52
            )
            // Version-2 zones store one maximum bound, then a reserved field and
            // a timestamp. The second bound is inferred as equal to the maximum.
            _ = try reader.u32("reserved header field")
            _ = try reader.u32("timestamp")
        case 3:
            _ = try reader.u32("reserved header field")
            header = Header(
                unknownHeaderValue: try reader.u32("unknown header value"),
                tileResolution: try reader.u32("tile resolution"),
                tileWorldSize: try reader.f32("tile world size"),
                flags: try reader.u32("flags"),
                minChunkX: try reader.i32("minimum chunk X"),
                minChunkY: try reader.i32("minimum chunk Y"),
                maxChunkX: try reader.i32("maximum chunk X"),
                maxChunkY: try reader.i32("maximum chunk Y"),
                checksum: try reader.u32("checksum"),
                materialCount: try reader.u32("material count"),
                materialTableOffset: 56
            )
            _ = try reader.u32("reserved header field")
        default:
            throw ClientZoneError.unsupportedVersion(version)
        }

        let materialCount = Int(header.materialCount)
        guard materialCount >= 0, materialCount <= Limits.maxMaterials else {
            throw ClientZoneError.limitExceeded(
                field: "zone materials", limit: Limits.maxMaterials
            )
        }

        var table = Reader(data, offset: header.materialTableOffset)
        var materials: [ZoneMaterialDefinition] = []
        materials.reserveCapacity(materialCount)
        for _ in 0..<materialCount {
            let name = try table.cString("material name")
            let textureName = try table.cString("material texture")
            let flags = try table.u32("material flags")
            let floraCount = Int(try table.u32("flora count"))
            guard floraCount >= 0, floraCount <= Limits.maxFloraPerMaterial else {
                throw ClientZoneError.limitExceeded(
                    field: "flora per material", limit: Limits.maxFloraPerMaterial
                )
            }
            var flora: [ZoneFloraDefinition] = []
            flora.reserveCapacity(floraCount)
            for _ in 0..<floraCount {
                let density = try table.f32("flora density")
                let scale = try table.f32("flora scale")
                let variation = try table.f32("flora variation")
                let channel = try table.byte("flora channel")
                let definition = ZoneFloraDefinition(
                    channel: channel,
                    density: density,
                    scale: scale,
                    variation: variation,
                    name: try table.cString("flora name")
                )
                flora.append(definition)
            }
            let index = try table.u32("material index")
            materials.append(ZoneMaterialDefinition(
                index: index,
                flags: flags,
                name: name,
                textureName: textureName,
                flora: flora
            ))
        }

        self.version = version
        self.unknownHeaderValue = header.unknownHeaderValue
        self.tileResolution = header.tileResolution
        self.tileWorldSize = header.tileWorldSize
        self.flags = header.flags
        self.minChunkX = header.minChunkX
        self.minChunkY = header.minChunkY
        self.maxChunkX = header.maxChunkX
        self.maxChunkY = header.maxChunkY
        self.checksum = header.checksum
        self.materials = materials
        self.payloadOffset = table.offset
    }
}

private extension ClientZoneManifest {
    struct Header {
        let unknownHeaderValue: UInt32
        let tileResolution: UInt32
        let tileWorldSize: Float
        let flags: UInt32
        let minChunkX: Int32
        let minChunkY: Int32
        let maxChunkX: Int32
        let maxChunkY: Int32
        let checksum: UInt32
        let materialCount: UInt32
        let materialTableOffset: Int
    }
}
