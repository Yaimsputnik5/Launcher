import Foundation
import XCTest
@testable import OSFRCore

// Tiny in-memory container builders. No sample asset files are read by these
// tests; the layouts mirror the observed original-client formats.

private func be16(_ value: UInt16) -> Data {
    Data([UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
}

private func be32(_ value: UInt32) -> Data {
    Data([
        UInt8(truncatingIfNeeded: value >> 24),
        UInt8(truncatingIfNeeded: value >> 16),
        UInt8(truncatingIfNeeded: value >> 8),
        UInt8(truncatingIfNeeded: value)
    ])
}

private func be64(_ value: UInt64) -> Data {
    Data([
        UInt8(truncatingIfNeeded: value >> 56),
        UInt8(truncatingIfNeeded: value >> 48),
        UInt8(truncatingIfNeeded: value >> 40),
        UInt8(truncatingIfNeeded: value >> 32),
        UInt8(truncatingIfNeeded: value >> 24),
        UInt8(truncatingIfNeeded: value >> 16),
        UInt8(truncatingIfNeeded: value >> 8),
        UInt8(truncatingIfNeeded: value)
    ])
}

private struct PackSpec {
    let name: String
    let payload: Data
    let crc: UInt32?

    init(_ name: String, _ payload: Data, crc: UInt32? = nil) {
        self.name = name
        self.payload = payload
        self.crc = crc
    }
}

private func makePack(blocks: [[PackSpec]]) -> Data {
    func directory(_ specs: [PackSpec], next: UInt32, offsets: [Int]) -> Data {
        var result = be32(next)
        result.append(be32(UInt32(specs.count)))
        for (spec, offset) in zip(specs, offsets) {
            let name = Data(spec.name.utf8)
            result.append(be32(UInt32(name.count)))
            result.append(name)
            result.append(be32(UInt32(offset)))
            result.append(be32(UInt32(spec.payload.count)))
            result.append(be32(spec.crc ?? CRC32.checksum(spec.payload)))
        }
        return result
    }

    let blockSizes = blocks.map { directory($0, next: 0, offsets: Array(repeating: 0, count: $0.count)).count }
    var cursor = blockSizes.reduce(0, +)
    var offsets: [[Int]] = []
    for block in blocks {
        var row: [Int] = []
        for spec in block {
            row.append(cursor)
            cursor += spec.payload.count
        }
        offsets.append(row)
    }

    var result = Data()
    for (index, block) in blocks.enumerated() {
        let next: UInt32 = index + 1 < blocks.count
            ? UInt32(blockSizes[0...index].reduce(0, +))
            : 0
        result.append(directory(block, next: next, offsets: offsets[index]))
    }
    for block in blocks {
        for spec in block { result.append(spec.payload) }
    }
    return result
}

private struct RccNodeSpec {
    let name: String
    let isDirectory: Bool
    let flags: UInt16
    let firstChild: Int
    let childCount: Int
    let blob: Data?
    let territory: UInt16
    let language: UInt16
    let mtime: UInt64

    init(
        _ name: String, isDirectory: Bool, flags: UInt16,
        firstChild: Int = 0, childCount: Int = 0, blob: Data? = nil,
        territory: UInt16 = 0, language: UInt16 = 0, mtime: UInt64 = 0
    ) {
        self.name = name
        self.isDirectory = isDirectory
        self.flags = flags
        self.firstChild = firstChild
        self.childCount = childCount
        self.blob = blob
        self.territory = territory
        self.language = language
        self.mtime = mtime
    }
}

private func makeRcc(version: UInt32, nodes: [RccNodeSpec], globalFlags: UInt32? = nil) -> Data {
    var names = Data()
    var nameOffsets: [Int] = []
    for node in nodes {
        nameOffsets.append(names.count)
        var units = be16(UInt16(node.name.utf16.count))
        units.append(be32(0)) // Name hash is not verified by the reader.
        for unit in node.name.utf16 { units.append(be16(unit)) }
        names.append(units)
    }

    var dataSection = Data()
    var blobOffsets: [Int?] = Array(repeating: nil, count: nodes.count)
    for (index, node) in nodes.enumerated() where !node.isDirectory {
        blobOffsets[index] = dataSection.count
        let blob = node.blob ?? Data()
        dataSection.append(be32(UInt32(blob.count)))
        dataSection.append(blob)
    }

    var tree = Data()
    for (index, node) in nodes.enumerated() {
        tree.append(be32(UInt32(nameOffsets[index])))
        tree.append(be16(node.flags))
        if node.isDirectory {
            tree.append(be32(UInt32(node.childCount)))
            tree.append(be32(UInt32(node.firstChild)))
        } else {
            tree.append(be16(node.territory))
            tree.append(be16(node.language))
            tree.append(be32(UInt32(blobOffsets[index] ?? 0)))
        }
        if version >= 2 { tree.append(be64(node.mtime)) }
    }

    let headerLength = version == 3 ? 24 : 20
    let dataOffset = headerLength
    let namesOffset = dataOffset + dataSection.count
    let treeOffset = namesOffset + names.count

    var result = Data("qres".utf8)
    result.append(be32(version))
    result.append(be32(UInt32(treeOffset)))
    result.append(be32(UInt32(dataOffset)))
    result.append(be32(UInt32(namesOffset)))
    if version == 3 { result.append(be32(globalFlags ?? 0)) }
    result.append(dataSection)
    result.append(names)
    result.append(tree)
    return result
}

private func sampleRccNodes(logoBlob: Data, readmeBlob: Data) -> [RccNodeSpec] {
    [
        RccNodeSpec("", isDirectory: true, flags: 0x02, firstChild: 1, childCount: 2),
        RccNodeSpec("images", isDirectory: true, flags: 0x02, firstChild: 3, childCount: 1),
        RccNodeSpec(
            "readme.txt", isDirectory: false, flags: 0x00,
            blob: readmeBlob, territory: 7, language: 9
        ),
        RccNodeSpec(
            "logo.png", isDirectory: false, flags: 0x01,
            blob: logoBlob, territory: 11, language: 13, mtime: 0x0123_4567_89AB_CDEF
        )
    ]
}

final class AssetContainerTests: XCTestCase {
    // MARK: - .pack

    func testPackChainedDirectoryParsing() throws {
        let first = PackSpec("a.txt", Data("alpha".utf8))
        let second = PackSpec("b.bin", Data([0x00, 0x01, 0x02]))
        let data = makePack(blocks: [[first], [second]])

        let archive = try PackArchive(data)
        XCTAssertEqual(archive.entries.map(\.name), ["a.txt", "b.bin"])
        XCTAssertEqual(archive.entries[0].payloadSize, 5)
        XCTAssertEqual(archive.entries[1].payloadSize, 3)
        XCTAssertGreaterThan(archive.entries[1].payloadOffset, archive.entries[0].payloadOffset)
        XCTAssertEqual(try archive.payload(named: "a.txt"), Data("alpha".utf8))
        XCTAssertEqual(try archive.payload(at: 1), Data([0x00, 0x01, 0x02]))
        XCTAssertEqual(try archive.payload(for: archive.entries[0]), Data("alpha".utf8))
        XCTAssertEqual(try archive.verifyAll(), 2)
        XCTAssertEqual(archive.entries(named: "missing").count, 0)
    }

    func testPackPayloadCRCIsVerified() throws {
        let data = makePack(blocks: [[PackSpec("a.txt", Data("alpha".utf8))]])
        let archive = try PackArchive(data)
        let entry = try XCTUnwrap(archive.entries.first)

        var corrupted = data
        corrupted[entry.payloadOffset] ^= 0xFF
        let badArchive = try PackArchive(corrupted)

        XCTAssertThrowsError(try badArchive.payload(named: "a.txt")) { error in
            guard case AssetContainerError.crcMismatch(let expected, let actual, let name) = error else {
                return XCTFail("Expected crcMismatch, got \(error)")
            }
            XCTAssertEqual(expected, entry.crc32)
            XCTAssertNotEqual(actual, expected)
            XCTAssertEqual(name, "a.txt")
        }
        // The original bytes still verify after the copy was corrupted.
        XCTAssertEqual(try archive.payload(named: "a.txt"), Data("alpha".utf8))
    }

    func testPackHandlesTruncationAndBadChains() {
        XCTAssertThrowsError(try PackArchive(Data([0x00, 0x00, 0x00]))) { error in
            guard case AssetContainerError.truncated = error else {
                return XCTFail("Expected truncated, got \(error)")
            }
        }

        let valid = makePack(blocks: [[PackSpec("a.txt", Data("alpha".utf8))]])
        XCTAssertThrowsError(try PackArchive(Data(valid.dropLast(2))))

        // Directory header claims one entry, but the name length is truncated.
        let shortEntry = be32(0) + be32(1) + be32(0)
        XCTAssertThrowsError(try PackArchive(shortEntry))

        // nextOffset points past EOF and would leave the directory chain dangling.
        XCTAssertThrowsError(try PackArchive(be32(9_999) + be32(0))) { error in
            guard case AssetContainerError.invalidLayout = error else {
                return XCTFail("Expected invalidLayout, got \(error)")
            }
        }
    }

    // MARK: - .rcc

    func testRCCV1ParsesTreeNamesAndData() throws {
        let plainLogoBlob = be32(8) + Data([0x78, 0x9C, 0x01, 0x02, 0x03, 0x04])
        let logoBlob = RccArchive.deobfuscate(plainLogoBlob)
        let nodes = sampleRccNodes(logoBlob: logoBlob, readmeBlob: Data("hello".utf8))
        let archive = try RccArchive(makeRcc(version: 1, nodes: nodes))

        XCTAssertEqual(archive.version, 1)
        XCTAssertNil(archive.globalFlags)
        XCTAssertEqual(archive.nodes.count, 4)
        XCTAssertEqual(archive.paths, ["readme.txt", "images/logo.png"])
        XCTAssertEqual(archive.nodes[0].path, "")
        XCTAssertTrue(archive.nodes[0].isDirectory)
        XCTAssertEqual(archive.children(of: archive.nodes[0]).map(\.name), ["images", "readme.txt"])
        XCTAssertEqual(archive.children(of: archive.nodes[1]).map(\.path), ["images/logo.png"])

        let logo = try XCTUnwrap(archive.node(atPath: "/images/logo.png"))
        XCTAssertTrue(logo.isFile)
        XCTAssertTrue(logo.isCompressed)
        XCTAssertEqual(logo.territory, 11)
        XCTAssertEqual(logo.language, 13)
        XCTAssertNil(logo.mtime)
        XCTAssertEqual(try archive.payload(for: logo), logoBlob)
        XCTAssertEqual(try archive.storedBlob(for: logo), be32(UInt32(logoBlob.count)) + logoBlob)
        XCTAssertEqual(try archive.deobfuscatedPayload(for: logo), plainLogoBlob)
        XCTAssertEqual(try archive.declaredUncompressedSize(for: logo), 8)
        XCTAssertEqual(try archive.deobfuscatedPayload(for: logo, key: 0), logoBlob)
        XCTAssertNil(try archive.declaredUncompressedSize(for: archive.nodes[2]))

        let readme = try XCTUnwrap(archive.node(atPath: "readme.txt"))
        XCTAssertFalse(readme.isCompressed)
        XCTAssertEqual(try archive.payload(for: readme), Data("hello".utf8))
    }

    func testRCCNestedPathsAndBlobStarts() throws {
        let nodes = sampleRccNodes(logoBlob: Data([0xAA, 0xBB]), readmeBlob: Data([0x01]))
        let archive = try RccArchive(makeRcc(version: 1, nodes: nodes))
        let logo = try XCTUnwrap(archive.node(atPath: "images//logo.png/"))

        XCTAssertEqual(logo.name, "logo.png")
        XCTAssertEqual(logo.path, "images/logo.png")
        XCTAssertEqual(logo.index, 3)
        guard case .file(let dataOffset, let compression) = logo.kind else {
            return XCTFail("Expected a file node")
        }
        XCTAssertEqual(dataOffset, 5) // Second blob; first blob is 4 + 1 bytes.
        XCTAssertEqual(compression, .zlib)
        XCTAssertNil(archive.node(atPath: "images/missing.png"))
    }

    func testRCCXORDeobfuscation() throws {
        XCTAssertEqual(
            RccArchive.deobfuscate(Data([0x3C, 0x14, 0x14, 0x20])),
            Data("OggS".utf8)
        )
        XCTAssertEqual(
            Data(RccArchive.deobfuscate(Data([0xFA, 0x23, 0x3D, 0x34])).prefix(4)),
            Data([0x89, 0x50, 0x4E, 0x47])
        )

        let secret = Data("secret".utf8)
        let nodes = sampleRccNodes(
            logoBlob: Data([0x78, 0x9C, 0x00]),
            readmeBlob: RccArchive.deobfuscate(secret)
        )
        let archive = try RccArchive(makeRcc(version: 1, nodes: nodes))
        let readme = try XCTUnwrap(archive.node(atPath: "readme.txt"))

        XCTAssertNotEqual(try archive.payload(for: readme), secret)
        XCTAssertEqual(try archive.deobfuscatedPayload(for: readme), secret)
        XCTAssertEqual(try archive.deobfuscatedPayload(for: readme, key: 0),
                       try archive.payload(for: readme))
    }

    func testRCCDecompressorHookIsOptional() throws {
        let plainLogoBlob = be32(3) + Data([0x78, 0x9C, 0x01])
        let logoBlob = RccArchive.deobfuscate(plainLogoBlob)
        let nodes = sampleRccNodes(logoBlob: logoBlob, readmeBlob: Data())
        var archive = try RccArchive(makeRcc(version: 1, nodes: nodes))
        let logo = try XCTUnwrap(archive.node(atPath: "images/logo.png"))

        XCTAssertThrowsError(try archive.decompressedPayload(for: logo)) { error in
            guard case AssetContainerError.decompressorUnavailable = error else {
                return XCTFail("Expected decompressorUnavailable, got \(error)")
            }
        }

        var received: Data?
        archive.zlibDecompressor = { stream in
            received = stream
            return Data("decoded".utf8)
        }
        XCTAssertEqual(try archive.decompressedPayload(for: logo), Data("decoded".utf8))
        XCTAssertEqual(received, Data(plainLogoBlob.dropFirst(4)))
        XCTAssertThrowsError(try archive.decompressedPayload(for: archive.nodes[2]))
    }

    func testRCCV2StoresMTime() throws {
        let nodes = sampleRccNodes(logoBlob: Data([0x01]), readmeBlob: Data([0x02]))
        let archive = try RccArchive(makeRcc(version: 2, nodes: nodes))
        XCTAssertEqual(archive.nodes[3].mtime, 0x0123_4567_89AB_CDEF)
        XCTAssertNil(archive.globalFlags)
        XCTAssertEqual(try archive.payload(for: archive.nodes[3]), Data([0x01]))
    }

    func testRCCV3ReadsGlobalFlags() throws {
        let nodes = sampleRccNodes(logoBlob: Data([0x01]), readmeBlob: Data([0x02]))
        let archive = try RccArchive(makeRcc(version: 3, nodes: nodes, globalFlags: 0x0000_00FF))
        XCTAssertEqual(archive.globalFlags, 0xFF)
        XCTAssertEqual(archive.nodes.count, 4)
        XCTAssertEqual(try archive.payload(for: archive.nodes[3]), Data([0x01]))
    }

    func testRCCRejectsUnsupportedVersionAndTruncation() {
        let nodes = sampleRccNodes(logoBlob: Data([0x01]), readmeBlob: Data())
        let unsupported = makeRcc(version: 4, nodes: nodes)
        XCTAssertThrowsError(try RccArchive(unsupported)) { error in
            guard case AssetContainerError.unsupportedVersion(let version) = error else {
                return XCTFail("Expected unsupportedVersion, got \(error)")
            }
            XCTAssertEqual(version, 4)
        }

        let valid = makeRcc(version: 1, nodes: nodes)
        XCTAssertThrowsError(try RccArchive(Data(valid.prefix(10)))) { error in
            guard case AssetContainerError.truncated = error else {
                return XCTFail("Expected truncated, got \(error)")
            }
        }
        XCTAssertThrowsError(try RccArchive(Data("nope".utf8))) { error in
            guard case AssetContainerError.invalidMagic = error else {
                return XCTFail("Expected invalidMagic, got \(error)")
            }
        }
    }
}
