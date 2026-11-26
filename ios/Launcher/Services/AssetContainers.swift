import Foundation

/// Errors shared by the `.pack` and `.rcc` readers. All offsets are reported in
/// bytes from the start of the container; no offset is ever trusted before its
/// range has been checked against the loaded data.
public enum AssetContainerError: Error, LocalizedError, Equatable {
    case truncated(field: String, expected: Int, available: Int)
    case invalidMagic
    case unsupportedVersion(UInt32)
    case invalidLayout(String)
    case limitExceeded(field: String, limit: Int)
    case invalidName(String)
    case invalidUTF16(String)
    case crcMismatch(expected: UInt32, actual: UInt32, entry: String)
    case unknownBlobOffset(Int)
    case invalidTree(String)
    case decompressorUnavailable

    public var errorDescription: String? {
        switch self {
        case .truncated(let field, let expected, let available):
            return "Truncated \(field): needed \(expected) byte(s), \(available) available."
        case .invalidMagic:
            return "Not a Qt resource collection (missing 'qres' magic)."
        case .unsupportedVersion(let version):
            return "Unsupported RCC version \(version); expected 1, 2, or 3."
        case .invalidLayout(let detail):
            return "Invalid container layout: \(detail)."
        case .limitExceeded(let field, let limit):
            return "\(field) exceeds the parser limit of \(limit)."
        case .invalidName(let name):
            return "Invalid or unsafe resource name '\(name)'."
        case .invalidUTF16(let field):
            return "\(field) is not valid UTF-16BE."
        case .crcMismatch(let expected, let actual, let entry):
            return String(
                format: "CRC-32 mismatch for '%@': expected 0x%08X, computed 0x%08X.",
                entry, expected, actual
            )
        case .unknownBlobOffset(let offset):
            return String(format: "No data blob starts at offset 0x%08X.", offset)
        case .invalidTree(let detail):
            return "Invalid RCC tree: \(detail)."
        case .decompressorUnavailable:
            return "No zlib decompressor is installed; use payload(for:) or set zlibDecompressor."
        }
    }
}

// MARK: - Safe primitive reads

/// Big-endian readers that work on `Data` subscripts and slices only. There is
/// no pointer arithmetic, and every read is bounded by the supplied limit
/// (often another section offset, not just the end of the file).
private func readBE16(_ data: Data, at offset: Int, limit: Int, field: String) throws -> UInt16 {
    let range = try checkedRange(offset: offset, length: 2, limit: limit, field: field)
    var value: UInt16 = 0
    for byte in data.subdata(in: range) {
        value = (value << 8) | UInt16(byte)
    }
    return value
}

private func readBE32(_ data: Data, at offset: Int, limit: Int, field: String) throws -> UInt32 {
    let range = try checkedRange(offset: offset, length: 4, limit: limit, field: field)
    var value: UInt32 = 0
    for byte in data.subdata(in: range) {
        value = (value << 8) | UInt32(byte)
    }
    return value
}

private func readBE64(_ data: Data, at offset: Int, limit: Int, field: String) throws -> UInt64 {
    let range = try checkedRange(offset: offset, length: 8, limit: limit, field: field)
    var value: UInt64 = 0
    for byte in data.subdata(in: range) {
        value = (value << 8) | UInt64(byte)
    }
    return value
}

private func checkedInt(_ value: UInt32, field: String) throws -> Int {
    guard let result = Int(exactly: value) else {
        throw AssetContainerError.limitExceeded(field: field, limit: Int.max)
    }
    return result
}

private func checkedRange(offset: Int, length: Int, limit: Int, field: String) throws -> Range<Int> {
    guard offset >= 0, length >= 0 else {
        throw AssetContainerError.invalidLayout("negative length for \(field)")
    }
    let (end, overflow) = offset.addingReportingOverflow(length)
    guard !overflow, end <= limit else {
        let available = offset <= limit ? limit - offset : 0
        throw AssetContainerError.truncated(field: field, expected: length, available: available)
    }
    return offset..<end
}

// MARK: - .pack

/// One directory record from a `.pack` container. `payloadOffset` is absolute
/// from the start of the file, and `crc32` is the standard reflected CRC-32 of
/// exactly `payloadSize` bytes at that offset.
public struct PackEntry: Equatable, Sendable {
    public let name: String
    public let payloadOffset: Int
    public let payloadSize: Int
    public let crc32: UInt32
}

/// Read-only parser for the original client's chained-directory `.pack` format.
///
/// The format has no magic: a directory block starts with `u32 nextOffset` (0
/// ends the chain) and `u32 entryCount`, both big-endian, followed by
/// `{u32 nameLength, UTF-8 name, u32 payloadOffset, u32 payloadSize, u32 crc32}`
/// records. Payloads are not decompressed or executed; `payload(for:)` returns
/// the stored bytes after verifying their CRC-32.
public struct PackArchive {
    private enum Limits {
        static let maxBlocks = 4_096
        static let maxEntries = 1_000_000
        static let maxNameBytes = 4_096
    }

    /// Directory records in chained-block order.
    public let entries: [PackEntry]

    private let data: Data
    private let firstIndexByName: [String: Int]

    public init(_ data: Data) throws {
        // Copy so that slices with a non-zero startIndex behave like files.
        let bytes = Data(data)
        var cursor = 0
        var parsed: [PackEntry] = []
        var visitedNextOffsets: Set<Int> = []
        var blockCount = 0

        while true {
            let directoryOffset = cursor
            guard blockCount < Limits.maxBlocks else {
                throw AssetContainerError.limitExceeded(field: "directory blocks", limit: Limits.maxBlocks)
            }
            blockCount += 1

            let nextRaw = try readBE32(bytes, at: cursor, limit: bytes.count, field: "next directory offset")
            cursor += 4
            let countRaw = try readBE32(bytes, at: cursor, limit: bytes.count, field: "entry count")
            cursor += 4
            let nextOffset = try checkedInt(nextRaw, field: "next directory offset")
            let entryCount = try checkedInt(countRaw, field: "entry count")

            guard entryCount <= Limits.maxEntries,
                  parsed.count <= Limits.maxEntries - entryCount
            else {
                throw AssetContainerError.limitExceeded(field: "pack entries", limit: Limits.maxEntries)
            }

            if nextOffset != 0 {
                guard nextOffset > directoryOffset, nextOffset <= bytes.count else {
                    throw AssetContainerError.invalidLayout(
                        "next directory offset \(nextOffset) does not advance within the file"
                    )
                }
                guard visitedNextOffsets.insert(nextOffset).inserted else {
                    throw AssetContainerError.invalidLayout("directory chain revisits offset \(nextOffset)")
                }
            }

            for _ in 0..<entryCount {
                let nameLength = try checkedInt(
                    try readBE32(bytes, at: cursor, limit: bytes.count, field: "entry name length"),
                    field: "entry name length"
                )
                cursor += 4
                guard nameLength <= Limits.maxNameBytes else {
                    throw AssetContainerError.limitExceeded(field: "entry name length", limit: Limits.maxNameBytes)
                }
                let nameRange = try checkedRange(
                    offset: cursor, length: nameLength, limit: bytes.count, field: "entry name"
                )
                cursor = nameRange.upperBound
                guard let name = String(data: bytes.subdata(in: nameRange), encoding: .utf8),
                      !name.isEmpty
                else {
                    throw AssetContainerError.invalidName("invalid UTF-8 or empty name at \(nameRange.lowerBound)")
                }

                let payloadOffset = try checkedInt(
                    try readBE32(bytes, at: cursor, limit: bytes.count, field: "payload offset for \(name)"),
                    field: "payload offset for \(name)"
                )
                cursor += 4
                let payloadSize = try checkedInt(
                    try readBE32(bytes, at: cursor, limit: bytes.count, field: "payload size for \(name)"),
                    field: "payload size for \(name)"
                )
                cursor += 4
                let crc = try readBE32(bytes, at: cursor, limit: bytes.count, field: "CRC-32 for \(name)")
                cursor += 4

                _ = try checkedRange(
                    offset: payloadOffset, length: payloadSize, limit: bytes.count,
                    field: "payload for \(name)"
                )
                parsed.append(PackEntry(
                    name: name, payloadOffset: payloadOffset, payloadSize: payloadSize, crc32: crc
                ))
            }

            if nextOffset == 0 { break }
            guard nextOffset >= cursor else {
                throw AssetContainerError.invalidLayout(
                    "next directory offset \(nextOffset) overlaps the current directory"
                )
            }
            cursor = nextOffset
        }

        var indexByName: [String: Int] = [:]
        for (index, entry) in parsed.enumerated() where indexByName[entry.name] == nil {
            indexByName[entry.name] = index
        }
        self.entries = parsed
        self.data = bytes
        self.firstIndexByName = indexByName
    }

    public init(data: Data) throws {
        try self.init(data)
    }

    public init(contentsOf url: URL) throws {
        try self.init(Data(contentsOf: url))
    }

    public init(url: URL) throws {
        try self.init(contentsOf: url)
    }

    /// Returns all records with this exact name. Some packs contain localized
    /// duplicates; use `payload(for:)` to select one of them.
    public func entries(named name: String) -> [PackEntry] {
        entries.filter { $0.name == name }
    }

    /// Stored bytes for an index in `entries`, verified against its CRC-32.
    public func payload(at index: Int) throws -> Data {
        guard entries.indices.contains(index) else {
            throw AssetContainerError.invalidLayout("entry index \(index) out of range")
        }
        let entry = entries[index]
        let range = try checkedRange(
            offset: entry.payloadOffset, length: entry.payloadSize, limit: data.count,
            field: "payload for \(entry.name)"
        )
        let payload = data.subdata(in: range)
        let actual = CRC32.checksum(payload)
        guard actual == entry.crc32 else {
            throw AssetContainerError.crcMismatch(
                expected: entry.crc32, actual: actual, entry: entry.name
            )
        }
        return payload
    }

    /// Stored bytes for one directory record, verified against its CRC-32.
    public func payload(for entry: PackEntry) throws -> Data {
        guard let index = entries.firstIndex(where: { $0 == entry }) else {
            throw AssetContainerError.invalidLayout("entry '\(entry.name)' is not in this archive")
        }
        return try payload(at: index)
    }

    /// Stored bytes for the first record with this name, verified against CRC-32.
    public func payload(named name: String) throws -> Data {
        guard let index = firstIndexByName[name] else {
            throw AssetContainerError.invalidLayout("no entry named '\(name)'")
        }
        return try payload(at: index)
    }

    /// Verifies every payload and returns the number checked.
    @discardableResult
    public func verifyAll() throws -> Int {
        for index in entries.indices { _ = try payload(at: index) }
        return entries.count
    }
}

// MARK: - .rcc

/// How a file node stores its blob. This is a TCG/extended RCC variant: bit 1
/// marks a zlib stream and bit 3 marks a zstd stream. Both bits set is treated
/// as zlib, matching the observed files.
public enum RccCompression: Equatable, Sendable {
    case none
    case zlib
    case zstd
}

/// Metadata for one tree node. Directory and file nodes use the same 14-byte
/// (v1) or 22-byte (v2/v3) record but interpret the middle fields differently.
public enum RccNodeKind: Equatable, Sendable {
    case directory(childCount: Int, firstChildIndex: Int)
    case file(dataOffset: Int, compression: RccCompression)
}

public struct RccNode: Equatable, Sendable {
    public let index: Int
    public let nameOffset: Int
    public let name: String
    /// Slash-separated path from the archive root, without a leading slash.
    /// The unnamed root node has path `""`.
    public let path: String
    public let flags: UInt16
    public let kind: RccNodeKind
    /// Present for file nodes; territory and language selectors in TCG RCCs.
    public let territory: UInt16?
    public let language: UInt16?
    /// Present only in version 2 and 3 trees, as a big-endian UInt64.
    public let mtime: UInt64?
    /// Index into the archive's sequential data-blob table, for file nodes.
    public let blobIndex: Int?

    public var isDirectory: Bool {
        if case .directory = kind { return true }
        return false
    }

    public var isFile: Bool {
        if case .file = kind { return true }
        return false
    }

    public var isCompressed: Bool {
        if case .file(_, let compression) = kind { return compression != .none }
        return false
    }
}

/// Read-only parser for Qt binary resource collections (`.rcc`) as shipped by
/// the original client, including its 0x73 XOR-obfuscated payloads.
///
/// Layout assumptions: `qres` magic, big-endian u32 version (1...3), tree/data/
/// names offsets, plus a u32 global flags word in v3. The tree is a flat array
/// of 14-byte (v1) or 22-byte (v2/v3) nodes; the names block consists of
/// `u16 UTF-16BE length + u32 hash + UTF-16BE characters`; the data block is a
/// sequence of `u32 blobLength + blob bytes`. A file node's `dataOffset` is
/// relative to the start of the data block and points at a blob's length word.
public struct RccArchive {
    private enum Limits {
        static let maxNameUnits = 4_096
        static let maxNodes = 1_000_000
        static let maxBlobs = 1_000_000
    }

    public let version: UInt32
    /// Version 3 stores a global flags word after the names offset.
    public let globalFlags: UInt32?
    /// Tree nodes in on-disk order; node 0 is the unnamed root.
    public let nodes: [RccNode]
    /// Convenience view of `nodes` containing file nodes only.
    public let files: [RccNode]

    /// Optional decompression hook for compressed nodes. It receives the stored
    /// blob body after the four-byte uncompressed-size word and after XOR
    /// deobfuscation. On Apple platforms this can be backed by the Compression
    /// framework's zlib decoder; Linux builds can leave it unset.
    public var zlibDecompressor: ((Data) throws -> Data)?

    /// Paths of all file nodes, in tree order.
    public var paths: [String] { files.map(\.path) }

    private let blobs: [Data]

    public init(_ data: Data) throws {
        let bytes = Data(data)
        let fileLimit = bytes.count

        let magic = try readBE32(bytes, at: 0, limit: fileLimit, field: "RCC magic")
        guard magic == 0x7172_6573 else { throw AssetContainerError.invalidMagic } // "qres"
        let version = try readBE32(bytes, at: 4, limit: fileLimit, field: "RCC version")
        guard version == 1 || version == 2 || version == 3 else {
            throw AssetContainerError.unsupportedVersion(version)
        }
        let treeOffset = try checkedInt(
            try readBE32(bytes, at: 8, limit: fileLimit, field: "tree offset"), field: "tree offset"
        )
        let dataOffset = try checkedInt(
            try readBE32(bytes, at: 12, limit: fileLimit, field: "data offset"), field: "data offset"
        )
        let namesOffset = try checkedInt(
            try readBE32(bytes, at: 16, limit: fileLimit, field: "names offset"), field: "names offset"
        )
        let headerLength = version == 3 ? 24 : 20
        let globalFlags = version == 3
            ? try readBE32(bytes, at: 20, limit: fileLimit, field: "global flags")
            : nil

        guard dataOffset >= headerLength, namesOffset >= dataOffset,
              treeOffset >= namesOffset, treeOffset <= fileLimit
        else {
            throw AssetContainerError.invalidLayout(
                "expected header <= data <= names <= tree <= EOF, got \(headerLength)/\(dataOffset)/\(namesOffset)/\(treeOffset)/\(fileLimit)"
            )
        }

        // Names block: offset -> UTF-16BE string. The table is bounded by treeOffset.
        var names: [Int: String] = [:]
        var nameCursor = namesOffset
        while nameCursor < treeOffset {
            let unitCount = try readBE16(bytes, at: nameCursor, limit: treeOffset, field: "name length")
            guard Int(unitCount) <= Limits.maxNameUnits else {
                throw AssetContainerError.limitExceeded(field: "name length", limit: Limits.maxNameUnits)
            }
            _ = try readBE32(bytes, at: nameCursor + 2, limit: treeOffset, field: "name hash")
            let textRange = try checkedRange(
                offset: nameCursor + 6, length: Int(unitCount) * 2, limit: treeOffset, field: "name"
            )
            guard let name = String(data: bytes.subdata(in: textRange), encoding: .utf16BigEndian) else {
                throw AssetContainerError.invalidUTF16("name at \(nameCursor)")
            }
            names[nameCursor - namesOffset] = name
            nameCursor = textRange.upperBound
        }

        // Data block: sequential blobs, each prefixed by a big-endian u32 length.
        var blobs: [Data] = []
        var blobStarts: [Int: Int] = [:]
        var blobCursor = dataOffset
        while blobCursor < namesOffset {
            let blobLength = try checkedInt(
                try readBE32(bytes, at: blobCursor, limit: namesOffset, field: "blob length"),
                field: "blob length"
            )
            guard blobs.count < Limits.maxBlobs else {
                throw AssetContainerError.limitExceeded(field: "data blobs", limit: Limits.maxBlobs)
            }
            let bodyRange = try checkedRange(
                offset: blobCursor + 4, length: blobLength, limit: namesOffset, field: "data blob"
            )
            blobStarts[blobCursor - dataOffset] = blobs.count
            blobs.append(bytes.subdata(in: bodyRange))
            blobCursor = bodyRange.upperBound
        }

        // Tree block: flat array of nodes. The root's name is always empty even
        // when its nameOffset aliases the first real name-table entry.
        let nodeStride = version == 1 ? 14 : 22
        let treeLength = fileLimit - treeOffset
        let nodeCount = treeLength / nodeStride
        guard nodeCount >= 1 else {
            throw AssetContainerError.invalidTree("no root node")
        }
        guard nodeCount <= Limits.maxNodes else {
            throw AssetContainerError.limitExceeded(field: "tree nodes", limit: Limits.maxNodes)
        }

        struct RawNode {
            let nameOffset: Int
            let name: String
            let flags: UInt16
            let kind: RccNodeKind
            let territory: UInt16?
            let language: UInt16?
            let mtime: UInt64?
            let blobIndex: Int?
        }

        var rawNodes: [RawNode] = []
        rawNodes.reserveCapacity(nodeCount)
        for index in 0..<nodeCount {
            let base = treeOffset + index * nodeStride
            let nameOffset = try checkedInt(
                try readBE32(bytes, at: base, limit: fileLimit, field: "node name offset"),
                field: "node name offset"
            )
            let flags = try readBE16(bytes, at: base + 4, limit: fileLimit, field: "node flags")

            var kind: RccNodeKind
            var territory: UInt16?
            var language: UInt16?
            var blobIndex: Int?
            if (flags & 0x02) != 0 {
                let childCount = try checkedInt(
                    try readBE32(bytes, at: base + 6, limit: fileLimit, field: "child count"),
                    field: "child count"
                )
                let firstChild = try checkedInt(
                    try readBE32(bytes, at: base + 10, limit: fileLimit, field: "first child"),
                    field: "first child"
                )
                kind = .directory(childCount: childCount, firstChildIndex: firstChild)
            } else {
                territory = try readBE16(bytes, at: base + 6, limit: fileLimit, field: "territory")
                language = try readBE16(bytes, at: base + 8, limit: fileLimit, field: "language")
                let relativeOffset = try checkedInt(
                    try readBE32(bytes, at: base + 10, limit: fileLimit, field: "blob offset"),
                    field: "blob offset"
                )
                guard let index = blobStarts[relativeOffset] else {
                    throw AssetContainerError.unknownBlobOffset(relativeOffset)
                }
                blobIndex = index
                let compression: RccCompression = (flags & 0x01) != 0
                    ? .zlib
                    : ((flags & 0x04) != 0 ? .zstd : .none)
                kind = .file(dataOffset: relativeOffset, compression: compression)
            }

            let mtime: UInt64? = version >= 2
                ? try readBE64(bytes, at: base + 14, limit: fileLimit, field: "node mtime")
                : nil

            let name: String
            if index == 0 {
                name = ""
            } else {
                guard let decoded = names[nameOffset], !decoded.isEmpty else {
                    throw AssetContainerError.invalidName("missing name at offset \(nameOffset) for node \(index)")
                }
                guard !decoded.contains("/"), !decoded.contains("\0") else {
                    throw AssetContainerError.invalidName(decoded)
                }
                name = decoded
            }
            rawNodes.append(RawNode(
                nameOffset: nameOffset, name: name, flags: flags, kind: kind,
                territory: territory, language: language, mtime: mtime, blobIndex: blobIndex
            ))
        }

        // Iterative traversal: no recursion on attacker-controlled tree depth.
        var paths: [String?] = Array(repeating: nil, count: nodeCount)
        paths[0] = ""
        var stack: [Int] = [0]
        while let parentIndex = stack.popLast() {
            guard case .directory(let childCount, let firstChild) = rawNodes[parentIndex].kind else {
                continue
            }
            guard firstChild <= nodeCount, childCount <= nodeCount - firstChild else {
                throw AssetContainerError.invalidTree(
                    "node \(parentIndex) addresses children \(firstChild)..<\(firstChild + childCount)"
                )
            }
            let parentPath = paths[parentIndex] ?? ""
            for childIndex in firstChild..<(firstChild + childCount) {
                guard paths[childIndex] == nil else {
                    throw AssetContainerError.invalidTree("node \(childIndex) has more than one parent")
                }
                let childName = rawNodes[childIndex].name
                paths[childIndex] = parentPath.isEmpty ? childName : "\(parentPath)/\(childName)"
                stack.append(childIndex)
            }
        }

        var nodes: [RccNode] = []
        nodes.reserveCapacity(nodeCount)
        for index in 0..<nodeCount {
            guard let path = paths[index] else {
                throw AssetContainerError.invalidTree("node \(index) is unreachable from the root")
            }
            let raw = rawNodes[index]
            nodes.append(RccNode(
                index: index, nameOffset: raw.nameOffset, name: raw.name, path: path,
                flags: raw.flags, kind: raw.kind, territory: raw.territory,
                language: raw.language, mtime: raw.mtime, blobIndex: raw.blobIndex
            ))
        }

        self.version = version
        self.globalFlags = globalFlags
        self.nodes = nodes
        self.files = nodes.filter(\.isFile)
        self.blobs = blobs
        self.zlibDecompressor = nil
    }

    public init(data: Data) throws {
        try self.init(data)
    }

    public init(contentsOf url: URL) throws {
        try self.init(Data(contentsOf: url))
    }

    public init(url: URL) throws {
        try self.init(contentsOf: url)
    }

    private static func normalizedPath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
    }

    /// Looks up a file or directory by path. Leading, trailing, and repeated
    /// slashes are ignored, so both `"images/logo.png"` and `"/images/logo.png"`
    /// resolve to the same node.
    public func node(atPath path: String) -> RccNode? {
        let key = Self.normalizedPath(path)
        return nodes.first { Self.normalizedPath($0.path) == key }
    }

    /// Children of a directory node, in on-disk order. Returns `[]` for files.
    public func children(of node: RccNode) -> [RccNode] {
        guard case .directory(let childCount, let firstChild) = node.kind,
              nodes.indices.contains(node.index),
              firstChild >= 0, childCount >= 0,
              firstChild <= nodes.count - childCount
        else { return [] }
        return Array(nodes[firstChild..<(firstChild + childCount)])
    }

    /// The stored blob body for a file node, *excluding* the four-byte on-disk
    /// length prefix. For zlib nodes this is `u32 BE uncompressedSize || zlib
    /// stream`. TCG payloads are typically XOR-obfuscated with 0x73.
    public func payload(for node: RccNode) throws -> Data {
        guard node.isFile else {
            throw AssetContainerError.invalidLayout("node '\(node.path)' is a directory")
        }
        guard let index = node.blobIndex, blobs.indices.contains(index) else {
            throw AssetContainerError.invalidLayout("node '\(node.path)' has no data blob")
        }
        return blobs[index]
    }

    /// The complete stored blob, including its big-endian u32 length prefix.
    public func storedBlob(for node: RccNode) throws -> Data {
        let body = try payload(for: node)
        var result = Data()
        result.append(contentsOf: Self.be32(UInt32(body.count)))
        result.append(body)
        return result
    }

    /// XORs every byte with `key`. TCG archives use 0x73; passing 0 is a no-op.
    /// Apply this to the whole payload body, including the uncompressed-size
    /// word of compressed nodes.
    public static func deobfuscate(_ data: Data, key: UInt8 = 0x73) -> Data {
        var result = Data(capacity: data.count)
        for byte in data { result.append(byte ^ key) }
        return result
    }

    /// `payload(for:)` after XOR deobfuscation. Pass `key: 0` for archives whose
    /// blobs are not obfuscated.
    public func deobfuscatedPayload(for node: RccNode, key: UInt8 = 0x73) throws -> Data {
        Self.deobfuscate(try payload(for: node), key: key)
    }

    /// The declared uncompressed size of a compressed node, read from the
    /// deobfuscated four-byte prefix. Returns nil for uncompressed nodes.
    public func declaredUncompressedSize(for node: RccNode, key: UInt8 = 0x73) throws -> Int? {
        guard node.isCompressed else { return nil }
        let body = try deobfuscatedPayload(for: node, key: key)
        guard body.count >= 4 else {
            throw AssetContainerError.truncated(field: "uncompressed size", expected: 4, available: body.count)
        }
        return try checkedInt(readBE32(body, at: 0, limit: body.count, field: "uncompressed size"),
                              field: "uncompressed size")
    }

    /// Decompresses a zlib node using `zlibDecompressor`. The hook receives the
    /// deobfuscated zlib stream without the four-byte uncompressed-size word.
    /// Throws `.decompressorUnavailable` if no hook has been installed.
    public func decompressedPayload(for node: RccNode, key: UInt8 = 0x73) throws -> Data {
        guard case .file(_, let compression) = node.kind, compression == .zlib else {
            throw AssetContainerError.invalidLayout("node '\(node.path)' is not zlib-compressed")
        }
        guard let decompressor = zlibDecompressor else {
            throw AssetContainerError.decompressorUnavailable
        }
        let body = try deobfuscatedPayload(for: node, key: key)
        guard body.count >= 4 else {
            throw AssetContainerError.truncated(field: "zlib stream", expected: 4, available: body.count)
        }
        return try decompressor(Data(body.dropFirst(4)))
    }

    private static func be32(_ value: UInt32) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value)
        ]
    }
}
