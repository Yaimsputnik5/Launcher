import Foundation

/// Errors from the original client's comma-delimited asset manifests and the
/// chained-directory `.pack` files that back them.
public enum WorldAssetCatalogError: Error, LocalizedError, Equatable {
    case unsafeName(String)
    case malformedManifest(String, line: Int)
    case manifestLimit(Int)
    case packLimit(Int)
    case unreadable(String)
    case truncated(String, expected: Int, available: Int)
    case invalidLayout(String)
    case notFound(String)
    case crcMismatch(expected: UInt32, actual: UInt32, entry: String)
    case manifestPackMismatch(entry: String, manifestCRC: UInt32, packCRC: UInt32)

    public var errorDescription: String? {
        switch self {
        case .unsafeName(let name):
            return "Unsafe asset name: \(name)"
        case .malformedManifest(let detail, let line):
            return "Malformed asset manifest at line \(line): \(detail)"
        case .manifestLimit(let limit):
            return "Asset manifest exceeds \(limit) records"
        case .packLimit(let limit):
            return "Pack directory exceeds \(limit) entries"
        case .unreadable(let path):
            return "Could not read asset file: \(path)"
        case .truncated(let field, let expected, let available):
            return "Truncated \(field): needed \(expected) byte(s), \(available) available"
        case .invalidLayout(let detail):
            return "Invalid asset container layout: \(detail)"
        case .notFound(let name):
            return "Asset not found: \(name)"
        case .crcMismatch(let expected, let actual, let entry):
            return "CRC-32 mismatch for \(entry): expected \(expected), got \(actual)"
        case .manifestPackMismatch(let entry, let manifestCRC, let packCRC):
            return "Manifest/pack CRC mismatch for \(entry): \(manifestCRC) vs \(packCRC)"
        }
    }
}

/// One `name,crc32,size` row from an original-client asset manifest.
///
/// `storedSize` is the size recorded by the patch manifest. Packs often store
/// the same asset under a name with `.z` removed and hold the uncompressed
/// payload, so `storedSize` is retained for evidence but is deliberately not
/// used as the pack payload length.
public struct WorldAssetManifestEntry: Equatable, Sendable {
    public let name: String
    public let crc32: UInt32
    public let storedSize: Int64
}

/// A parsed comma-delimited asset manifest. Duplicate names keep the first row
/// but remain countable, so a manifest can be audited without guessing which
/// duplicate the original client would have chosen.
public struct WorldAssetManifest: Equatable, Sendable {
    public let source: String
    public let entries: [WorldAssetManifestEntry]
    public let duplicateCount: Int

    private let firstIndexByName: [String: Int]

    public init(source: String, entries: [WorldAssetManifestEntry], duplicateCount: Int = 0) {
        self.source = source
        self.entries = entries
        self.duplicateCount = duplicateCount
        var index: [String: Int] = [:]
        for (position, entry) in entries.enumerated() where index[entry.name] == nil {
            index[entry.name] = position
        }
        self.firstIndexByName = index
    }

    /// Exact lookup, then the same name with a trailing `.z` removed. The
    /// original client's pack directories use the stripped name for many
    /// manifest-only `.z` records.
    public func entry(named name: String) -> WorldAssetManifestEntry? {
        if let index = firstIndexByName[name] { return entries[index] }
        if name.hasSuffix(".z") {
            let stripped = String(name.dropLast(2))
            guard let index = firstIndexByName[stripped] else { return nil }
            return entries[index]
        }
        guard let index = firstIndexByName[name + ".z"] else { return nil }
        return entries[index]
    }

    public static func parse(
        _ data: Data,
        source: String = "Assets_manifest.txt",
        limit: Int = 250_000
    ) throws -> WorldAssetManifest {
        var entries: [WorldAssetManifestEntry] = []
        var firstNames: Set<String> = []
        var duplicates = 0
        var lineNumber = 0

        // Split on bytes: the shipped manifests use CRLF, which Swift treats as
        // one Character and would therefore never match a "\n" separator.
        for rawLine in data.split(separator: 0x0A, omittingEmptySubsequences: false) {
            lineNumber += 1
            var bytes = Array(rawLine)
            if bytes.last == 0x0D { bytes.removeLast() }
            if bytes.isEmpty { continue }
            guard bytes.count <= 4_096 else {
                throw WorldAssetCatalogError.malformedManifest("line too long", line: lineNumber)
            }
            guard let line = String(bytes: bytes, encoding: .utf8) else {
                throw WorldAssetCatalogError.malformedManifest("invalid UTF-8", line: lineNumber)
            }
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3 else {
                throw WorldAssetCatalogError.malformedManifest("expected name,crc32,size", line: lineNumber)
            }
            let name = fields[0]
            guard isSafeName(name) else {
                throw WorldAssetCatalogError.unsafeName(name)
            }
            guard let crc = UInt32(fields[1]), let size = Int64(fields[2]), size >= 0 else {
                throw WorldAssetCatalogError.malformedManifest("invalid crc32 or size", line: lineNumber)
            }
            guard entries.count < limit else {
                throw WorldAssetCatalogError.manifestLimit(limit)
            }
            let entry = WorldAssetManifestEntry(name: name, crc32: crc, storedSize: size)
            if firstNames.insert(name).inserted {
                entries.append(entry)
            } else {
                duplicates += 1
            }
        }
        return WorldAssetManifest(source: source, entries: entries, duplicateCount: duplicates)
    }

    private static func isSafeName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("/") else { return false }
        let parts = name.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty else { return false }
        for part in parts {
            guard !part.isEmpty,
                  part != ".",
                  part != "..",
                  !part.contains("\\"),
                  !part.contains(":")
            else { return false }
        }
        return true
    }
}

/// A directory record from one of the original client's `.pack` files.
public struct WorldPackEntry: Equatable, Sendable {
    public let packRelativePath: String
    public let name: String
    public let payloadOffset: Int
    public let payloadSize: Int
    public let crc32: UInt32
}

/// A manifest row ending in `.z` whose CRC does not match the stored payload.
///
/// The crosswalk over the real client shows that these CRCs usually match the
/// uncompressed pack payload, but two rows do not; their manifest CRC is likely
/// computed over the delivered compressed `.z` bytes. Those bytes are not here,
/// so the disagreement is reported diagnostically rather than guessed.
public struct WorldCompressedManifestCRCDisagreement: Equatable, Sendable {
    public let manifestName: String
    public let manifestCRC: UInt32
    public let packRelativePath: String
    public let packName: String
    public let packCRC: UInt32
}

/// Index-over-manifests for the original client's world asset payload.
///
/// This reader never decompresses or executes anything. It verifies pack-entry
/// CRC-32 for every returned payload. Manifest/pack CRC is also enforced when
/// the manifest name exactly matches the pack name. For `.z` manifest rows that
/// map to a stripped pack name, a CRC difference is exposed by
/// `compressedManifestCRCDisagreement(for:)` because the manifest CRC can
/// describe compressed bytes. Runtime `.z` files that are not present in a pack
/// are reported as not found rather than guessed.
public final class WorldAssetCatalog: @unchecked Sendable {
    public static let defaultManifestPaths = [
        "Assets_manifest.txt",
        "assets/assetpack000_manifest.txt",
        "tcg/AssetsTcg_manifest.txt"
    ]

    public static let defaultPackPaths = [
        "AssetsW_000.pack",
        "AssetsW_001.pack",
        "Assets_000.pack",
        "Assets_001.pack",
        "Assets_002.pack",
        "Assets_003.pack",
        "Assets_004.pack",
        "Assets_005.pack",
        "Assets_006.pack",
        "Assets_007.pack",
        "Assets_008.pack",
        "Assets_009.pack",
        "assets/assetpack000W_000.pack"
    ]

    private enum Limits {
        static let maxBlocks = 4_096
        static let maxEntriesPerBlock = 1_000_000
        static let maxEntries = 1_000_000
        static let maxNameBytes = 4_096
    }

    /// Lazily built from the bundled payload first, then the sandbox copy. A
    /// missing manifest or pack set yields `nil` rather than a partial catalog.
    public static let bundledCatalog: WorldAssetCatalog? = {
        var roots: [URL] = []
        if let bundled = AppPaths.bundledClientAssets { roots.append(bundled) }
        roots.append(AppPaths.sandboxClientAssets)
        for root in roots {
            if let catalog = try? WorldAssetCatalog(root: root) { return catalog }
        }
        return nil
    }()

    public let root: URL
    public let manifests: [WorldAssetManifest]
    public let packEntries: [WorldPackEntry]

    private let packURLs: [String: URL]
    private let firstPackIndexByName: [String: [Int]]

    public init(
        root: URL,
        manifestPaths: [String] = WorldAssetCatalog.defaultManifestPaths,
        packPaths: [String] = WorldAssetCatalog.defaultPackPaths
    ) throws {
        self.root = root
        let manager = FileManager.default

        var loadedManifests: [WorldAssetManifest] = []
        for path in manifestPaths {
            let url = root.appendingPathComponent(path)
            guard manager.fileExists(atPath: url.path) else { continue }
            let data = try Data(contentsOf: url)
            loadedManifests.append(try WorldAssetManifest.parse(data, source: path))
        }
        guard !loadedManifests.isEmpty else {
            throw WorldAssetCatalogError.notFound(manifestPaths.first ?? "Assets_manifest.txt")
        }
        self.manifests = loadedManifests

        var urls: [String: URL] = [:]
        var entries: [WorldPackEntry] = []
        for path in packPaths {
            let url = root.appendingPathComponent(path)
            guard manager.fileExists(atPath: url.path) else { continue }
            let parsed = try Self.readPackDirectory(at: url, relativePath: path)
            guard !parsed.isEmpty else { continue }
            urls[path] = url
            entries.append(contentsOf: parsed)
        }
        guard !entries.isEmpty else {
            throw WorldAssetCatalogError.notFound(packPaths.first ?? "pack")
        }
        self.packEntries = entries
        self.packURLs = urls

        var index: [String: [Int]] = [:]
        for (position, entry) in entries.enumerated() {
            index[entry.name, default: []].append(position)
        }
        self.firstPackIndexByName = index
    }

    /// First matching pack record for a manifest name, including `.z` stripping.
    public func packEntry(for name: String) -> WorldPackEntry? {
        for candidate in Self.candidates(for: name) {
            guard let position = firstPackIndexByName[candidate]?.first else { continue }
            return packEntries[position]
        }
        return nil
    }

    /// Verified stored bytes for a manifest name. The returned bytes are the
    /// exact pack payload; a manifest-only `.z` suffix does not imply that this
    /// method performs decompression.
    public func payload(for name: String) throws -> Data {
        for candidate in Self.candidates(for: name) {
            guard let positions = firstPackIndexByName[candidate] else { continue }
            for position in positions {
                let entry = packEntries[position]
                guard let url = packURLs[entry.packRelativePath] else { continue }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let fileSize = try Self.fileSize(of: url)
                let data = try Self.readBytes(
                    from: handle,
                    fileSize: fileSize,
                    offset: UInt64(entry.payloadOffset),
                    count: entry.payloadSize,
                    field: "payload for \(entry.name)"
                )
                let actual = CRC32.checksum(data)
                guard actual == entry.crc32 else {
                    throw WorldAssetCatalogError.crcMismatch(
                        expected: entry.crc32, actual: actual, entry: entry.name
                    )
                }
                // Exact non-`.z` rows were verified 3,333/3,333 against their
                // pack entries. Only those can safely require matching CRCs.
                if let manifestEntry = manifestEntry(for: name),
                   manifestEntry.name == entry.name,
                   manifestEntry.crc32 != entry.crc32 {
                    throw WorldAssetCatalogError.manifestPackMismatch(
                        entry: entry.name,
                        manifestCRC: manifestEntry.crc32,
                        packCRC: entry.crc32
                    )
                }
                return data
            }
        }
        throw WorldAssetCatalogError.notFound(name)
    }

    /// Reports a CRC difference for a `.z` manifest row resolved to a stripped
    /// pack name. `nil` means names are not both present or the CRCs agree.
    public func compressedManifestCRCDisagreement(
        for name: String
    ) -> WorldCompressedManifestCRCDisagreement? {
        guard name.hasSuffix(".z"),
              let manifest = manifestEntry(for: name),
              let pack = packEntry(for: name),
              manifest.crc32 != pack.crc32
        else { return nil }
        return WorldCompressedManifestCRCDisagreement(
            manifestName: manifest.name,
            manifestCRC: manifest.crc32,
            packRelativePath: pack.packRelativePath,
            packName: pack.name,
            packCRC: pack.crc32
        )
    }

    private func manifestEntry(for name: String) -> WorldAssetManifestEntry? {
        for manifest in manifests {
            if let entry = manifest.entry(named: name) { return entry }
        }
        return nil
    }

    private static func candidates(for name: String) -> [String] {
        guard name.hasSuffix(".z") else { return [name] }
        return [name, String(name.dropLast(2))]
    }

    private static func fileSize(of url: URL) throws -> UInt64 {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw WorldAssetCatalogError.unreadable(url.lastPathComponent)
        }
        guard let number = attributes[.size] as? NSNumber else {
            throw WorldAssetCatalogError.unreadable(url.lastPathComponent)
        }
        return number.uint64Value
    }

    private static func readBytes(
        from handle: FileHandle,
        fileSize: UInt64,
        offset: UInt64,
        count: Int,
        field: String
    ) throws -> Data {
        guard count >= 0, offset <= fileSize, UInt64(count) <= fileSize - offset else {
            let available = offset <= fileSize ? Int(clamping: fileSize - offset) : 0
            throw WorldAssetCatalogError.truncated(
                field, expected: count, available: available
            )
        }
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: count), data.count == count else {
                throw WorldAssetCatalogError.truncated(
                    field, expected: count, available: 0
                )
            }
            return Data(data)
        } catch let error as WorldAssetCatalogError {
            throw error
        } catch {
            throw WorldAssetCatalogError.unreadable(field)
        }
    }

    private static func u32BE(_ data: Data, at offset: Int) throws -> UInt32 {
        guard offset >= 0, data.count >= offset + 4 else {
            throw WorldAssetCatalogError.truncated(
                "u32", expected: offset + 4, available: data.count
            )
        }
        var result: UInt32 = 0
        for byte in 0..<4 {
            result = (result << 8) | UInt32(data[data.index(data.startIndex, offsetBy: offset + byte)])
        }
        return result
    }

    private static func readPackDirectory(at url: URL, relativePath: String) throws -> [WorldPackEntry] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try Self.fileSize(of: url)

        var result: [WorldPackEntry] = []
        var visitedOffsets: Set<UInt64> = []
        var cursor: UInt64 = 0
        var blockCount = 0

        while true {
            guard blockCount < Limits.maxBlocks else {
                throw WorldAssetCatalogError.packLimit(Limits.maxBlocks)
            }
            blockCount += 1
            let directoryOffset = cursor
            let header = try readBytes(
                from: handle, fileSize: fileSize, offset: cursor, count: 8,
                field: "pack directory header in \(relativePath)"
            )
            let nextRaw = try u32BE(header, at: 0)
            let countRaw = try u32BE(header, at: 4)
            guard let entryCount = Int(exactly: countRaw), entryCount <= Limits.maxEntriesPerBlock,
                  result.count <= Limits.maxEntries - entryCount
            else {
                throw WorldAssetCatalogError.packLimit(Limits.maxEntries)
            }

            var recordOffset = directoryOffset + 8
            for _ in 0..<entryCount {
                let lengthBytes = try readBytes(
                    from: handle, fileSize: fileSize, offset: recordOffset, count: 4,
                    field: "pack entry name length in \(relativePath)"
                )
                let rawNameLength = try u32BE(lengthBytes, at: 0)
                guard let nameLength = Int(exactly: rawNameLength),
                      nameLength <= Limits.maxNameBytes
                else {
                    throw WorldAssetCatalogError.packLimit(Limits.maxNameBytes)
                }
                recordOffset += 4

                let nameBytes = try readBytes(
                    from: handle, fileSize: fileSize, offset: recordOffset, count: nameLength,
                    field: "pack entry name in \(relativePath)"
                )
                guard let name = String(data: nameBytes, encoding: .utf8), !name.isEmpty else {
                    throw WorldAssetCatalogError.invalidLayout(
                        "invalid UTF-8 or empty name in \(relativePath)"
                    )
                }
                recordOffset += UInt64(nameLength)

                let fields = try readBytes(
                    from: handle, fileSize: fileSize, offset: recordOffset, count: 12,
                    field: "pack entry fields in \(relativePath)"
                )
                recordOffset += 12
                guard let payloadOffset = Int(exactly: try u32BE(fields, at: 0)),
                      let payloadSize = Int(exactly: try u32BE(fields, at: 4))
                else {
                    throw WorldAssetCatalogError.invalidLayout(
                        "oversized payload offset in \(relativePath)"
                    )
                }
                let crc = try u32BE(fields, at: 8)
                guard UInt64(payloadOffset) <= fileSize,
                      UInt64(payloadSize) <= fileSize - UInt64(payloadOffset)
                else {
                    throw WorldAssetCatalogError.truncated(
                        "payload for \(name) in \(relativePath)",
                        expected: payloadSize,
                        available: UInt64(payloadOffset) <= fileSize
                            ? Int(clamping: fileSize - UInt64(payloadOffset)) : 0
                    )
                }
                result.append(WorldPackEntry(
                    packRelativePath: relativePath,
                    name: name,
                    payloadOffset: payloadOffset,
                    payloadSize: payloadSize,
                    crc32: crc
                ))
            }

            let nextOffset = UInt64(nextRaw)
            if nextOffset == 0 { break }
            guard nextOffset >= recordOffset, nextOffset <= fileSize else {
                throw WorldAssetCatalogError.invalidLayout(
                    "pack directory chain does not advance in \(relativePath)"
                )
            }
            guard visitedOffsets.insert(nextOffset).inserted else {
                throw WorldAssetCatalogError.invalidLayout(
                    "pack directory chain repeats in \(relativePath)"
                )
            }
            cursor = nextOffset
        }
        return result
    }
}
