import Foundation

/// A placed object from a shipped `FabledRealms_*.gcnk` chunk.
///
/// The position is stored in world coordinates. A cross-check against
/// `FabledRealmsAreas.xml` shows, for example, the first object in
/// `FabledRealms_0_-8.gcnk` at `(-448.996, 37.093, 35.793)` next to the
/// `HighroadJunction_sparkles_*` area definitions near `(-425, 26)`.
struct ClientChunkObject: Equatable, Sendable {
    let chunkName: String
    let assetName: String
    let position: ZoneVector
    let rotation: ClientChunkRotation
    let scale: Double
}

struct ClientChunkRotation: Equatable, Sendable {
    let x: Double
    let y: Double
    let z: Double
}

/// Parsed object placements from the client's GCNK chunk archives.
struct ClientChunkCatalog: Equatable, Sendable {
    let objects: [ClientChunkObject]
    let chunkCount: Int
    let status: String

    static let empty = ClientChunkCatalog(
        objects: [],
        chunkCount: 0,
        status: "No client chunk objects loaded"
    )

    /// Reads every `FabledRealms_*.gcnk` entry in the embedded pack chain.
    /// Failures are recorded in `status` instead of discarding the whole catalog:
    /// a single corrupt chunk must not hide the rest of the shipped zone.
    static func loadFabledRealms(
        loader: ClientAssetDataLoader = ClientAssetDataLoader(),
        decompressor: @escaping (Data) throws -> Data = UdpLibrary.inflateZlib
    ) -> ClientChunkCatalog {
        var objects: [ClientChunkObject] = []
        var chunkCount = 0
        var failures = 0

        archives: for archive in archiveNames {
            guard let names = try? loader.packEntryNames(archivePath: archive) else {
                failures += 1
                continue
            }
            for name in names where name.hasPrefix("FabledRealms_") && name.hasSuffix(".gcnk") {
                guard chunkCount < Limits.maxChunks,
                      objects.count < Limits.maxObjects
                else { break archives }
                do {
                    let data = try loader.data(relativePath: "\(archive)#\(name)")
                    objects.append(
                        contentsOf: try parseGCNK(
                            data,
                            chunkName: name,
                            decompressor: decompressor
                        )
                    )
                    chunkCount += 1
                } catch {
                    failures += 1
                }
            }
        }

        let suffix = failures == 0 ? "" : ", \(failures) chunk(s) skipped"
        return ClientChunkCatalog(
            objects: objects,
            chunkCount: chunkCount,
            status: "\(objects.count) client objects from \(chunkCount) GCNK chunks\(suffix)"
        )
    }

    /// GCNK v6 header: magic, version, uncompressed length, compressed length,
    /// then an RFC 1950 zlib stream at offset 16.
    static func parseGCNK(
        _ data: Data,
        chunkName: String,
        decompressor: (Data) throws -> Data
    ) throws -> [ClientChunkObject] {
        let bytes = [UInt8](data)
        guard bytes.count >= 16 else {
            throw ClientChunkError.truncated("GCNK header")
        }
        guard String(bytes: bytes[0..<4], encoding: .ascii) == "GCNK" else {
            throw ClientChunkError.invalidMagic
        }
        let version = Self.u32(bytes, 4)
        guard version == 6 else {
            throw ClientChunkError.unsupportedVersion(version)
        }
        let expectedLength = Int(Self.u32(bytes, 8))
        guard expectedLength > 0, expectedLength <= Limits.maxDecompressedBytes else {
            throw ClientChunkError.invalidLength(expectedLength)
        }
        let inflated = [UInt8](try decompressor(Data(bytes[16...])))
        guard inflated.count == expectedLength else {
            throw ClientChunkError.lengthMismatch(
                expected: expectedLength,
                actual: inflated.count
            )
        }
        return try parseDecompressed(inflated, chunkName: chunkName)
    }

    /// Scans decompressed chunk bytes for null-terminated `.adr`, `.agr`, and
    /// `.cln` asset names. Each accepted record has the observed two-zero-byte
    /// separator, finite world coordinates, and the observed `0x00ff0000`
    /// property word. Anything else is skipped rather than guessed.
    static func parseDecompressed(
        _ bytes: [UInt8],
        chunkName: String
    ) throws -> [ClientChunkObject] {
        var objects: [ClientChunkObject] = []
        var index = 0

        while index < bytes.count {
            guard Self.isNameByte(bytes[index]) else {
                index += 1
                continue
            }
            let start = index
            var end = start
            while end < bytes.count,
                  Self.isNameByte(bytes[end]),
                  end - start < Limits.maxNameBytes
            {
                end += 1
            }
            let nameBytes = Array(bytes[start..<end])
            guard nameBytes.count >= Limits.minNameBytes,
                  Self.hasObjectSuffix(nameBytes),
                  end < bytes.count,
                  bytes[end] == 0,
                  end + 1 < bytes.count,
                  bytes[end + 1] == 0
            else {
                index = max(end, start + 1)
                continue
            }

            let floatStart = end + 2
            guard floatStart + 40 <= bytes.count else { break }
            let x = Double(Self.f32(bytes, floatStart))
            let y = Double(Self.f32(bytes, floatStart + 4))
            let z = Double(Self.f32(bytes, floatStart + 8))
            let scale = Double(Self.f32(bytes, floatStart + 12))
            let rotation = ClientChunkRotation(
                x: Double(Self.f32(bytes, floatStart + 16)),
                y: Double(Self.f32(bytes, floatStart + 20)),
                z: Double(Self.f32(bytes, floatStart + 24))
            )
            let property = Self.u32(bytes, floatStart + 36)

            guard Self.finite(x, within: -8_192...8_192),
                  Self.finite(y, within: -1_024...1_024),
                  Self.finite(z, within: -8_192...8_192),
                  Self.finite(scale, within: 0.001...1_000),
                  Self.finite(rotation.x, within: -1_000...1_000),
                  Self.finite(rotation.y, within: -1_000...1_000),
                  Self.finite(rotation.z, within: -1_000...1_000),
                  property == 0x00FF_0000
            else {
                index = end + 1
                continue
            }

            guard let name = String(bytes: nameBytes, encoding: .utf8) else {
                index = end + 1
                continue
            }
            objects.append(
                ClientChunkObject(
                    chunkName: chunkName,
                    assetName: name,
                    position: ZoneVector(x: x, y: y, z: z, w: 0),
                    rotation: rotation,
                    scale: scale
                )
            )
            guard objects.count < Limits.maxObjects else { break }
            index = end + 1
        }
        return objects
    }

    private enum Limits {
        static let archiveCount = 10
        static let maxChunks = 512
        static let maxObjects = 20_000
        static let maxDecompressedBytes = 32 * 1024 * 1024
        static let minNameBytes = 5
        static let maxNameBytes = 256
    }

    private static let archiveNames = (0..<Limits.archiveCount).map {
        String(format: "Assets_%03d.pack", $0)
    }

    private static func finite(_ value: Double, within range: ClosedRange<Double>) -> Bool {
        value.isFinite && range.contains(value)
    }

    private static func isNameByte(_ byte: UInt8) -> Bool {
        (byte >= 65 && byte <= 90) ||
        (byte >= 97 && byte <= 122) ||
        (byte >= 48 && byte <= 57) ||
        byte == UInt8(ascii: "_") ||
        byte == UInt8(ascii: ".") ||
        byte == UInt8(ascii: "-") ||
        byte == UInt8(ascii: "/")
    }

    private static func hasObjectSuffix(_ bytes: [UInt8]) -> Bool {
        let lower = bytes.map { $0 >= 65 && $0 <= 90 ? $0 + 32 : $0 }
        for suffix in [Array(".adr".utf8), Array(".agr".utf8), Array(".cln".utf8)] {
            if lower.count >= suffix.count,
               Array(lower.suffix(suffix.count)) == suffix
            {
                return true
            }
        }
        return false
    }

    private static func u32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) |
        (UInt32(bytes[offset + 1]) << 8) |
        (UInt32(bytes[offset + 2]) << 16) |
        (UInt32(bytes[offset + 3]) << 24)
    }

    private static func f32(_ bytes: [UInt8], _ offset: Int) -> Float {
        Float(bitPattern: u32(bytes, offset))
    }
}

enum ClientChunkError: Error, LocalizedError, Equatable {
    case truncated(String)
    case invalidMagic
    case unsupportedVersion(UInt32)
    case invalidLength(Int)
    case lengthMismatch(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .truncated(let field): return "Truncated GCNK \(field)."
        case .invalidMagic: return "Chunk data does not begin with GCNK."
        case .unsupportedVersion(let version): return "Unsupported GCNK version \(version)."
        case .invalidLength(let length): return "Invalid GCNK uncompressed length \(length)."
        case .lengthMismatch(let expected, let actual):
            return "GCNK declares \(expected) decompressed bytes but produced \(actual)."
        }
    }
}
