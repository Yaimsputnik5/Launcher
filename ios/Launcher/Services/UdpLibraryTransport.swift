import Foundation
#if canImport(Compression)
import Compression
#endif

// Receive-side port of Sanctuary.UdpLibrary/UdpConnection.cs and
// Internal/UdpReliableChannel.cs.
//
// The login and gateway transports used to only accept a datagram that was
// itself a direct reliable frame. Sanctuary wraps cooked packets in Multi
// (type 3), wraps application packets in Group (type 25), processes fragments,
// and the gateway applies a user-supplied zlib/raw pass whose flag is at byte 2
// (before the reliable id). Live probes against play.opensourcefreerealms.com
// confirmed all four behaviors. Missing them made valid replies look like
// timeouts.
//
// Wire layout after UDP negotiation:
//   0x00, type, [user-supplied flag], <type-specific body>, CRC16
// The CRC covers every byte before the final two bytes and is seeded with the
// negotiated EncryptCode. The user-supplied flag is stripped (or inflated)
// before the remaining bytes are processed as a cooked packet.

enum UdpLibraryError: Error, LocalizedError, Equatable {
    case truncated(String)
    case badMarker(UInt8)
    case crcMismatch(expected: UInt16, actual: UInt16)
    case unsupportedCompression(UInt8)
    case compressionUnavailable
    case decompressionFailed
    case fragmentTooLarge(Int)
    case fragmentOverflow

    var errorDescription: String? {
        switch self {
        case .truncated(let what): return "Truncated UdpLibrary packet: \(what)."
        case .badMarker(let value): return "Invalid UdpLibrary marker 0x\(String(value, radix: 16))."
        case .crcMismatch(let expected, let actual):
            return "UdpLibrary CRC mismatch: expected 0x\(String(expected, radix: 16)), got 0x\(String(actual, radix: 16))."
        case .unsupportedCompression(let flag):
            return "Unsupported UdpLibrary compression flag \(flag)."
        case .compressionUnavailable:
            return "zlib compression is unavailable in this build."
        case .decompressionFailed:
            return "Failed to inflate a UdpLibrary packet."
        case .fragmentTooLarge(let length):
            return "UdpLibrary fragment declares an oversized packet (\(length) bytes)."
        case .fragmentOverflow:
            return "UdpLibrary fragment exceeds its declared packet length."
        }
    }
}

/// A packet after CRC validation and the user-supplied decryption pass.
enum UdpLibraryPacket: Equatable {
    case application(Data)
    case reliable(type: UInt8, reliableID: UInt16, body: Data, applications: [Data])
    case ack(type: UInt8, reliableID: UInt16)
    case ackAll(type: UInt8, reliableID: UInt16)
    case internalPacket(UInt8)
}

/// Per-connection state for reliable fragments. Sanctuary reassembles the
/// logical packet before handing it to `ProcessCookedPacket`.
struct UdpLibraryReassemblyState {
    var fragment: Data?
    var targetLength = 0

    mutating func reset() {
        fragment = nil
        targetLength = 0
    }
}

enum UdpLibrary {
    static let marker: UInt8 = 0
    static let crcByteCount = 2
    static let maximumReassemblyLength = 4 * 1024 * 1024

    /// `UdpConnection.IsNonEncryptPacket`: these are raw-sent and have no CRC.
    static func isNonEncrypted(_ type: UInt8) -> Bool {
        type == 1 || // Connect
        type == 2 || // Confirm
        type == 27 || // UnreachableConnection
        type == 28 || // RequestRemap
        type == 29 || // Unknown
        type == 30 // ServerStatus
    }

    /// Validate the datagram CRC and undo the optional user-supplied pass.
    static func cook(
        _ datagram: Data,
        encryptCode: UInt32,
        userSuppliedCompression: Bool
    ) throws -> Data {
        let bytes = Array(datagram)
        guard bytes.count >= 2 else { throw UdpLibraryError.truncated("datagram") }
        guard bytes[0] == marker else { throw UdpLibraryError.badMarker(bytes[0]) }

        if isNonEncrypted(bytes[1]) {
            return datagram
        }

        guard bytes.count > crcByteCount else {
            throw UdpLibraryError.truncated("CRC")
        }
        let signed = Data(bytes.dropLast(crcByteCount))
        let expected = UInt16(truncatingIfNeeded: CRC32.checksum(signed, encryptCode: encryptCode))
        let actual = (UInt16(bytes[bytes.count - 2]) << 8) | UInt16(bytes[bytes.count - 1])
        guard expected == actual else {
            throw UdpLibraryError.crcMismatch(expected: expected, actual: actual)
        }

        guard userSuppliedCompression else { return signed }
        guard signed.count >= 3 else {
            throw UdpLibraryError.truncated("user-supplied flag")
        }

        let cookedBytes = Array(signed)
        var result = Data(cookedBytes.prefix(2))
        if cookedBytes[2] == 1 {
            result.append(try inflate(Data(cookedBytes.dropFirst(3))))
        } else {
            // Sanctuary treats any non-1 flag as "raw" and drops one byte.
            result.append(contentsOf: cookedBytes.dropFirst(3))
        }
        return result
    }

    /// Parse a cooked packet into application payloads and transport events.
    /// Multi (3) and Group (25) containers are expanded recursively.
    static func parse(
        _ cooked: Data,
        state: inout UdpLibraryReassemblyState
    ) -> [UdpLibraryPacket] {
        let bytes = Array(cooked)
        guard !bytes.isEmpty else { return [] }

        // ProcessCookedPacket routes anything without a leading zero marker
        // straight to the application.
        guard bytes[0] == marker else { return [.application(Data(bytes))] }
        guard bytes.count >= 2 else { return [] }

        switch bytes[1] {
        case 0: // ZeroEscape: drop only the escape marker.
            return [.application(Data(bytes.dropFirst()))]

        case 3: // Multi: one-byte lengths, subpackets already cooked
            return parseContainers(bytes, lengthSize: 1, offset: 2, state: &state)

        case 9...12: // Reliable1-4
            return parseReliable(bytes, state: &state)

        case 13...16: // Fragment1-4
            return parseFragment(bytes, state: &state)

        case 17...20: // Ack1-4
            guard bytes.count >= 4 else { return [] }
            let reliableID = readBE16(bytes, offset: 2)
            return [.ack(type: bytes[1], reliableID: reliableID)]

        case 21...24: // AckAll1-4 (also carries a reliable id)
            guard bytes.count >= 4 else { return [] }
            let reliableID = readBE16(bytes, offset: 2)
            return [.ackAll(type: bytes[1], reliableID: reliableID)]

        case 25: // Group: variable-length application packets
            return parseContainers(bytes, lengthSize: 0, offset: 2, state: &state)

        default:
            return [.internalPacket(bytes[1])]
        }
    }

    /// Convenience overload for callers without a live connection.
    static func parse(_ cooked: Data) -> [UdpLibraryPacket] {
        var state = UdpLibraryReassemblyState()
        return parse(cooked, state: &state)
    }

    /// Build a reliable frame exactly as `UdpConnection.PhysicalSend` does.
    /// `GatewayConnection.EncryptUserSupplied` prepends its flag to everything
    /// after the two-byte internal header, so the flag precedes the reliable id.
    static func encodeReliable(
        type: UInt8,
        reliableID: UInt16,
        encryptCode: UInt32,
        userSuppliedCompression: Bool,
        payload: Data
    ) -> Data {
        var data = Data([marker, type])
        if userSuppliedCompression {
            data.append(0) // raw; this client never compresses outbound packets
        }
        data.append(UInt8(truncatingIfNeeded: reliableID >> 8))
        data.append(UInt8(truncatingIfNeeded: reliableID))

        let payloadBytes = Array(payload)
        if payloadBytes.first == marker {
            data.append(marker)
        }
        data.append(contentsOf: payloadBytes)

        let crc = UInt16(truncatingIfNeeded: CRC32.checksum(data, encryptCode: encryptCode))
        data.append(UInt8(truncatingIfNeeded: crc >> 8))
        data.append(UInt8(truncatingIfNeeded: crc))
        return data
    }

    /// Ack channel for a reliable or fragment packet type.
    static func ackType(for reliableType: UInt8) -> UInt8? {
        guard reliableType >= 9, reliableType <= 16 else { return nil }
        return 17 + ((reliableType - 9) % 4)
    }

    // MARK: - Private

    private static func parseReliable(
        _ bytes: [UInt8],
        state: inout UdpLibraryReassemblyState
    ) -> [UdpLibraryPacket] {
        guard bytes.count >= 4 else { return [] }
        guard state.fragment == nil else { return [] } // FragmentExpected

        let reliableID = readBE16(bytes, offset: 2)
        let body = Data(bytes.dropFirst(4))
        let applications = parse(body, state: &state).compactMap { packet -> Data? in
            guard case .application(let data) = packet else { return nil }
            return data
        }
        return [.reliable(
            type: bytes[1],
            reliableID: reliableID,
            body: body,
            applications: applications
        )]
    }

    private static func parseFragment(
        _ bytes: [UInt8],
        state: inout UdpLibraryReassemblyState
    ) -> [UdpLibraryPacket] {
        guard bytes.count >= 4 else { return [] }
        let reliableID = readBE16(bytes, offset: 2)
        var chunk = Data(bytes.dropFirst(4))

        if state.fragment == nil {
            guard chunk.count >= 4 else { return [] }
            // `UdpReliableChannel` writes this with WriteInt32BigEndian and
            // reads it back with TryReadInt32 (default big-endian).
            let length = Int(
                (UInt32(chunk[0]) << 24) |
                (UInt32(chunk[1]) << 16) |
                (UInt32(chunk[2]) << 8) |
                UInt32(chunk[3])
            )
            guard length > 0, length <= maximumReassemblyLength else { return [] }
            state.targetLength = length
            state.fragment = Data()
            chunk = Data(chunk.dropFirst(4))
        }

        guard let fragment = state.fragment else { return [] }
        guard fragment.count + chunk.count <= state.targetLength else {
            state.reset()
            return []
        }

        state.fragment!.append(chunk)
        guard state.fragment!.count == state.targetLength else { return [] }

        let reassembled = state.fragment!
        state.reset()
        var nestedState = UdpLibraryReassemblyState()
        let applications = parse(reassembled, state: &nestedState).compactMap { packet -> Data? in
            guard case .application(let data) = packet else { return nil }
            return data
        }
        return [.reliable(
            type: bytes[1],
            reliableID: reliableID,
            body: reassembled,
            applications: applications
        )]
    }

    /// `UdpMisc.GetVariableValue` for Group containers. `lengthSize == 1`
    /// selects the fixed one-byte length used by Multi containers.
    private static func parseContainers(
        _ bytes: [UInt8],
        lengthSize: Int,
        offset: Int,
        state: inout UdpLibraryReassemblyState
    ) -> [UdpLibraryPacket] {
        var result: [UdpLibraryPacket] = []
        var pointer = offset
        while pointer < bytes.count {
            var length: Int
            if lengthSize == 1 {
                length = Int(bytes[pointer])
                pointer += 1
            } else if bytes[pointer] == 0xff {
                if pointer + 3 <= bytes.count && bytes[pointer + 1] == 0xff && bytes[pointer + 2] == 0xff {
                    guard pointer + 7 <= bytes.count else { break }
                    length = (Int(bytes[pointer + 3]) << 24) |
                        (Int(bytes[pointer + 4]) << 16) |
                        (Int(bytes[pointer + 5]) << 8) |
                        Int(bytes[pointer + 6])
                    pointer += 7
                } else {
                    guard pointer + 3 <= bytes.count else { break }
                    length = (Int(bytes[pointer + 1]) << 8) | Int(bytes[pointer + 2])
                    pointer += 3
                }
            } else {
                length = Int(bytes[pointer])
                pointer += 1
            }
            guard length > 0, pointer + length <= bytes.count else { break }
            result.append(contentsOf: parse(Data(bytes[pointer..<(pointer + length)]), state: &state))
            pointer += length
        }
        return result
    }

    private static func readBE16(_ bytes: [UInt8], offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private static func inflate(_ source: Data) throws -> Data {
        #if canImport(Compression)
        // The iOS SDK imports these C pointers as non-optional, so neither
        // `nil` nor a no-argument initializer compiles there. Pass harmless
        // one-byte buffers; compression_stream_init replaces them immediately.
        let initialDst = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        initialDst.initialize(to: 0)
        let initialSrc = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        initialSrc.initialize(to: 0)
        defer {
            initialDst.deinitialize(count: 1)
            initialDst.deallocate()
            initialSrc.deinitialize(count: 1)
            initialSrc.deallocate()
        }
        var stream = compression_stream(
            dst_ptr: initialDst,
            dst_size: 0,
            src_ptr: UnsafePointer(initialSrc),
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR else {
            throw UdpLibraryError.decompressionFailed
        }
        defer { compression_stream_destroy(&stream) }

        var input = source
        return try input.withUnsafeMutableBytes { inputBuffer in
            guard let base = inputBuffer.baseAddress else {
                throw UdpLibraryError.decompressionFailed
            }
            stream.src_ptr = base.assumingMemoryBound(to: UInt8.self)
            stream.src_size = inputBuffer.count

            var output = Data()
            let bufferSize = 64 * 1024
            var scratch = [UInt8](repeating: 0, count: bufferSize)
            while true {
                let status: compression_status = scratch.withUnsafeMutableBytes { buffer in
                    guard let destination = buffer.baseAddress else {
                        return COMPRESSION_STATUS_ERROR
                    }
                    stream.dst_ptr = destination.assumingMemoryBound(to: UInt8.self)
                    stream.dst_size = buffer.count
                    return compression_stream_process(&stream, 0)
                }
                if status == COMPRESSION_STATUS_ERROR {
                    throw UdpLibraryError.decompressionFailed
                }
                output.append(contentsOf: scratch.prefix(bufferSize - stream.dst_size))
                if status == COMPRESSION_STATUS_END { return output }
                if stream.src_size == 0 && stream.dst_size == bufferSize {
                    throw UdpLibraryError.decompressionFailed
                }
            }
        }
        #else
        _ = source
        throw UdpLibraryError.compressionUnavailable
        #endif
    }
}
