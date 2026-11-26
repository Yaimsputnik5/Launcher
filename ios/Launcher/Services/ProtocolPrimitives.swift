import Foundation

// MARK: - Errors

/// Errors raised while decoding Sanctuary wire data.
enum ProtocolError: Error, LocalizedError, Equatable {
    case truncated(expected: Int, available: Int)
    case negativeLength(String)
    case invalidBool(UInt8)
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .truncated(let expected, let available):
            return "Truncated packet: needed \(expected) byte(s), only \(available) available."
        case .negativeLength(let field):
            return "Negative \(field) length on the wire."
        case .invalidBool(let value):
            return "Invalid boolean byte 0x\(String(value, radix: 16)); expected 0 or 1."
        case .invalidUTF8:
            return "String payload is not valid UTF-8."
        }
    }
}

// MARK: - Wire constants

enum PacketConstants {
    /// Magic prefix used by Sanctuary packets.
    static let magic: UInt32 = 0xF3D4A5C9
}

// MARK: - Writer

/// Writes Sanctuary primitives: little-endian scalars, one-byte bools,
/// Int32-prefixed UTF-8 strings, and Int32-prefixed byte payloads.
struct PacketWriter {
    var data = Data()

    mutating func writeUInt8(_ value: UInt8) {
        data.append(value)
    }

    mutating func writeUInt16(_ value: UInt16) {
        appendLittleEndian(value)
    }

    mutating func writeUInt32(_ value: UInt32) {
        appendLittleEndian(value)
    }

    mutating func writeUInt64(_ value: UInt64) {
        appendLittleEndian(value)
    }

    mutating func writeInt32(_ value: Int32) {
        writeUInt32(UInt32(bitPattern: value))
    }

    mutating func writeInt64(_ value: Int64) {
        writeUInt64(UInt64(bitPattern: value))
    }

    mutating func writeFloat(_ value: Float) {
        writeUInt32(value.bitPattern)
    }

    /// A bool is exactly one byte on the wire: 0 or 1.
    mutating func writeBool(_ value: Bool) {
        writeUInt8(value ? 1 : 0)
    }

    /// Writes an Int32 UTF-8 byte count followed by the bytes.
    /// `nil` and `""` both encode as a zero length (the wire has no null marker).
    mutating func writeString(_ value: String?) {
        let bytes: [UInt8]
        if let value {
            bytes = Array(value.utf8)
        } else {
            bytes = []
        }
        precondition(bytes.count <= Int(Int32.max), "String is too long for an Int32 length prefix")
        writeInt32(Int32(bytes.count))
        data.append(contentsOf: bytes)
    }

    /// Writes an Int32 byte count followed by the payload bytes.
    mutating func writeData(_ value: Data) {
        precondition(value.count <= Int(Int32.max), "Payload is too long for an Int32 length prefix")
        writeInt32(Int32(value.count))
        data.append(value)
    }

    private mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        for shift in stride(from: 0, to: T.bitWidth, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }
}

// MARK: - Reader

/// Reads Sanctuary primitives with explicit bounds checks. Every failure
/// leaves `offset` unchanged, so a failed read can be retried or inspected.
struct PacketReader {
    private let data: Data
    private(set) var offset = 0

    init(_ data: Data) {
        self.data = data
    }

    var remaining: Int { data.count - offset }
    var isAtEnd: Bool { offset == data.count }

    mutating func readUInt8() throws -> UInt8 {
        try readByte()
    }

    mutating func readUInt16() throws -> UInt16 {
        try readLittleEndian(UInt16.self)
    }

    mutating func readUInt32() throws -> UInt32 {
        try readLittleEndian(UInt32.self)
    }

    mutating func readUInt64() throws -> UInt64 {
        try readLittleEndian(UInt64.self)
    }

    mutating func readInt32() throws -> Int32 {
        Int32(bitPattern: try readUInt32())
    }

    mutating func readInt64() throws -> Int64 {
        Int64(bitPattern: try readUInt64())
    }

    mutating func readFloat() throws -> Float {
        Float(bitPattern: try readUInt32())
    }

    mutating func readBool() throws -> Bool {
        let raw = try readByte()
        switch raw {
        case 0: return false
        case 1: return true
        default: throw ProtocolError.invalidBool(raw)
        }
    }

    /// Reads an Int32 byte count and decodes that many bytes as UTF-8.
    /// A zero-length string decodes as `""`; the wire cannot distinguish nil from empty.
    mutating func readString() throws -> String {
        let length = try readInt32()
        guard length >= 0 else { throw ProtocolError.negativeLength("string") }
        let bytes = try readBytes(Int(length))
        guard let value = String(data: bytes, encoding: .utf8) else {
            throw ProtocolError.invalidUTF8
        }
        return value
    }

    /// Reads an Int32 byte count followed by that many payload bytes.
    mutating func readData() throws -> Data {
        let length = try readInt32()
        guard length >= 0 else { throw ProtocolError.negativeLength("payload") }
        return try readBytes(Int(length))
    }

    private mutating func readByte() throws -> UInt8 {
        guard offset < data.count else {
            throw ProtocolError.truncated(expected: 1, available: 0)
        }
        defer { offset += 1 }
        return data[offset]
    }

    private mutating func readBytes(_ count: Int) throws -> Data {
        guard count >= 0 else { throw ProtocolError.negativeLength("payload") }
        guard count <= remaining else {
            throw ProtocolError.truncated(expected: count, available: remaining)
        }
        let range = offset..<(offset + count)
        offset += count
        return data.subdata(in: range)
    }

    private mutating func readLittleEndian<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        let bytes = try readBytes(MemoryLayout<T>.size)
        var value: T = 0
        for (index, byte) in bytes.enumerated() {
            value |= T(byte) << (8 * index)
        }
        return value
    }
}

// MARK: - CRC32

/// Reflected CRC-32 (polynomial 0xEDB88320), matching the table in
/// Sanctuary's `UdpMisc.Crc32` and zlib's CRC-32.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var entry = UInt32(index)
        for _ in 0..<8 {
            entry = (entry & 1) != 0 ? (entry >> 1) ^ 0xEDB88320 : entry >> 1
        }
        return entry
    }

    /// Standard CRC-32: init 0xFFFFFFFF, update with `data`, then complement.
    static func checksum(_ data: Data) -> UInt32 {
        ~update(0xFFFF_FFFF, with: data)
    }

    /// Sanctuary UDP variant. The 32-bit `encryptCode` is NOT XORed into the
    /// final result. Starting from the normal 0xFFFFFFFF state, the four bytes
    /// of the code are fed through the CRC table least-significant byte first
    /// (i.e. the little-endian encoding of the code), followed by `data`, then
    /// the state is complemented. This is exactly the C# implementation:
    ///
    ///     crc = 0xffffffffu;
    ///     foreach (var b in encryptCodeLittleEndian) crc = step(crc, b);
    ///     foreach (var b in data) crc = step(crc, b);
    ///     return ~crc;
    ///
    /// Note that `encryptCode: 0` consumes four zero bytes, so it differs from
    /// `checksum(data)`; only `checksum(_:)` matches zlib.
    static func checksum(_ data: Data, encryptCode: UInt32) -> UInt32 {
        let codeBytes: [UInt8] = [
            UInt8(truncatingIfNeeded: encryptCode),
            UInt8(truncatingIfNeeded: encryptCode >> 8),
            UInt8(truncatingIfNeeded: encryptCode >> 16),
            UInt8(truncatingIfNeeded: encryptCode >> 24)
        ]
        let seeded = update(0xFFFF_FFFF, with: codeBytes)
        return ~update(seeded, with: data)
    }

    private static func update<C: Collection>(_ crc: UInt32, with bytes: C) -> UInt32 where C.Element == UInt8 {
        var result = crc
        for byte in bytes {
            result = (result >> 8) ^ table[Int((result ^ UInt32(byte)) & 0xFF)]
        }
        return result
    }
}

// MARK: - RC4

/// RC4 keystream XOR used by the Login connection. The cipher is stateful:
/// calling `process` repeatedly continues the same keystream.
struct RC4 {
    /// Login key from the Sanctuary configuration.
    static let loginKeyBase64 = "F70IaxuU8C/w7FPXY1ibXw=="

    static var loginKey: Data {
        guard let key = Data(base64Encoded: loginKeyBase64) else {
            fatalError("Invalid base64 RC4 login key")
        }
        return key
    }

    private var state = [UInt8](repeating: 0, count: 256)
    private var i: UInt8 = 0
    private var j: UInt8 = 0

    init(key: Data) {
        let keyBytes = Array(key)
        precondition(!keyBytes.isEmpty, "RC4 requires a non-empty key")

        for index in 0..<256 {
            state[index] = UInt8(index)
        }

        var keyIndex = 0
        for index in 0..<256 {
            let keyByte = keyBytes[keyIndex]
            keyIndex = (keyIndex + 1) % keyBytes.count
            let mixed = (Int(state[index]) + Int(j) + Int(keyByte)) & 0xFF
            j = UInt8(mixed)
            state.swapAt(index, Int(j))
        }

        // RC4's PRGA starts from i = j = 0, independent of the KSA's final j.
        i = 0
        j = 0
    }

    mutating func process(_ data: Data) -> Data {
        var output = Data(capacity: data.count)
        for byte in data {
            i = i &+ 1
            j = j &+ state[Int(i)]
            state.swapAt(Int(i), Int(j))
            let keyByte = state[Int(state[Int(i)] &+ state[Int(j)])]
            output.append(byte ^ keyByte)
        }
        return output
    }
}

// MARK: - GuidHelper

/// Sanctuary GUID layout: the low four bits are the entity type and the
/// remaining 60 bits are the type-specific id.
enum GuidHelper {
    enum GuidType: UInt8 {
        case player = 1
        case npc = 2
        case locationTarget = 3
    }

    static let typeMask: UInt64 = 0xF
    private static let maxId: UInt64 = (1 << 60) - 1
    private static let serverId: UInt64 = 1
    private static let maxNpcCounter: UInt64 = (1 << 28) - 1
    private static let maxNpcInstanceId: UInt64 = (1 << 24) - 1

    static func playerGuid(_ id: UInt64) -> UInt64 {
        precondition(id <= maxId, "Player id does not fit in 60 bits")
        return (id << 4) | UInt64(GuidType.player.rawValue)
    }

    /// Returns the player id only when the GUID's low nibble is `Player`.
    static func playerId(_ guid: UInt64) -> UInt64? {
        guard guidType(guid) == .player else { return nil }
        return guid >> 4
    }

    /// Matches `GuidHelper.GetNpcGuid`: counter bits 36..63, instance id
    /// bits 8..31, server id nibble at bits 4..7, type nibble at bits 0..3.
    static func npcGuid(counter: UInt64, instanceId: UInt64) -> UInt64 {
        precondition(counter <= maxNpcCounter, "NPC counter out of range")
        precondition(instanceId <= maxNpcInstanceId, "NPC instance id out of range")
        let id = (counter << 32) | (instanceId << 4) | serverId
        return (id << 4) | UInt64(GuidType.npc.rawValue)
    }

    static func locationTargetGuid(_ nameId: UInt32) -> UInt64 {
        (UInt64(nameId) << 4) | UInt64(GuidType.locationTarget.rawValue)
    }

    static func guidType(_ guid: UInt64) -> GuidType? {
        GuidType(rawValue: UInt8(truncatingIfNeeded: guid & typeMask))
    }
}
