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
    case invalidZlibHeader
    case zlibChecksumMismatch(expected: UInt32, actual: UInt32)
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
        case .invalidZlibHeader:
            return "Invalid RFC 1950 zlib header."
        case .zlibChecksumMismatch(let expected, let actual):
            return "zlib Adler-32 mismatch: expected 0x\(String(expected, radix: 16)), got 0x\(String(actual, radix: 16))."
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

/// Ack decision and application payloads produced by one inbound reliable
/// frame after Sanctuary-style ordering has been applied.
struct UdpLibraryIncomingAck {
    var type: UInt8
    var reliableID: UInt16
    var applications: [Data]
    var wasDuplicate = false
}

/// Receive-side ordered reliable channels. C# `UdpReliableChannel` buffers
/// packets that arrive ahead of the next expected id, delivers them only when
/// the gap is filled, and suppresses duplicates. This reproduces that part of
/// `ReliablePacket` without implementing the outbound congestion window.
struct UdpLibraryIncomingReliableState {
    private struct Entry {
        let applications: [Data]
    }

    /// Sanctuary's external-client `MaxInstandingPackets` is 32000; 400 is the
    /// default window and is already far beyond the gateway's burst size.
    private static let windowSize = 400

    private var expectedByChannel: [UInt8: UInt16] = [:]
    private var bufferedByChannel: [UInt8: [UInt16: Entry]] = [:]

    mutating func reset() {
        expectedByChannel.removeAll()
        bufferedByChannel.removeAll()
    }

    /// Returns the Ack/AckAll to send plus only the payloads Sanctuary would
    /// deliver now. The first observed stamp seeds the channel because this
    /// client creates a fresh connection for each login/gateway session.
    mutating func receive(
        type: UInt8,
        reliableID: UInt16,
        applications: [Data]
    ) -> UdpLibraryIncomingAck? {
        guard let channel = UdpLibrary.channel(for: type),
              let ackType = UdpLibrary.ackType(for: type),
              let ackAllType = UdpLibrary.ackAllType(for: type)
        else { return nil }

        var expected = expectedByChannel[channel] ?? reliableID
        var buffered = bufferedByChannel[channel] ?? [:]
        var deliver: [Data] = []

        let distance = Int(Int16(bitPattern: reliableID &- expected))
        if distance == 0 {
            deliver.append(contentsOf: applications)
            expected = expected &+ 1

            while let entry = buffered[expected] {
                buffered.removeValue(forKey: expected)
                deliver.append(contentsOf: entry.applications)
                expected = expected &+ 1
            }
        } else if distance > 0, distance < Self.windowSize, buffered[reliableID] == nil {
            buffered[reliableID] = Entry(applications: applications)
        }

        expectedByChannel[channel] = expected
        bufferedByChannel[channel] = buffered

        if UdpLibrary.reliableID(expected, isAheadOf: reliableID) {
            return UdpLibraryIncomingAck(
                type: ackAllType,
                reliableID: expected &- 1,
                applications: deliver,
                wasDuplicate: true
            )
        }
        return UdpLibraryIncomingAck(
            type: ackType,
            reliableID: reliableID,
            applications: deliver
        )
    }
}

/// Negotiated connection facts from a UdpLibrary Confirm packet. The live
/// gateway uses CRC-2, no second encryption pass and a 512-byte raw packet;
/// keeping all four values lets the sender reject unsupported peers and size
/// reliable payloads from the peer's limit instead of our receive buffer.
struct UdpLibraryConnectionConfig: Equatable, Sendable {
    var encryptCode: UInt32
    var crcBytes: Int
    var encryptMethod1: UInt8
    var encryptMethod2: UInt8
    var maxRawPacketSize: Int

    var userSuppliedCompression: Bool { encryptMethod1 == 1 }

    /// `UdpConnection.SetupEncryptModel` counts only user-supplied expansion in
    /// Sanctuary's external-client configuration; Xor/XorBuffer are in-place.
    var encryptExpansionBytes: Int { encryptMethod1 == 1 ? 1 : 0 }

    /// `UdpReliableChannel` constructor: MaxRawPacketSize - reliable header (4)
    /// - CRC bytes - encryption expansion bytes.
    var maxReliablePayloadBytes: Int {
        maxRawPacketSize - 4 - crcBytes - encryptExpansionBytes
    }
}

/// Send-side state for one UdpLibrary reliable channel. This ports the window,
/// RTT, congestion and ACK/AckAll transitions of Sanctuary's
/// `Internal/UdpReliableChannel.cs`; frame encryption and socket writes remain
/// in the session so the same state works for both Login and Gateway UDP.
struct UdpLibraryOutgoingReliableState {
    struct Entry: Equatable, Sendable {
        let id: UInt64
        let channel: UInt8
        let length: Int
        let firstSend: UInt64
        var lastSend: UInt64
        var sendCount: Int
    }

    struct Resend: Equatable, Sendable {
        let id: UInt16
        let channel: UInt8
    }

    struct Tick: Equatable, Sendable {
        var resends: [Resend] = []
        var delay: UInt64 = 0
        var timedOut = false
    }

    private static let maximumOutstandingPackets = 400
    private static let maximumOutstandingBytes = 200 * 1024
    private static let resendDelayPercent: UInt64 = 125
    private static let resendDelayAdjust: UInt64 = 300
    private static let resendDelayCap: UInt64 = 8_000
    private static let oldestUnacknowledgedTimeout: UInt64 = 120_000
    private static let toleranceLossCount = 0

    let config: UdpLibraryConnectionConfig
    private let maximumDataBytes: Int
    private let congestionWindowMinimum: Int
    private let congestionWindowStart: Int
    private let slowStartThreshold: Int

    private var entries: [UInt64: Entry] = [:]
    private var nextID: UInt64 = 0
    private var pendingID: UInt64 = 0
    private var averagePing: UInt64 = 800
    private var congestionWindowSize: Int
    private var lastAcknowledgedSend: UInt64 = 0
    private var windowResetTime: UInt64 = 0
    private var maxxedOutCurrentWindow = false
    private var tolerantLosses = 0

    var outstandingCount: Int { entries.count }
    var outstandingBytes: Int { entries.values.reduce(0) { $0 + $1.length } }

    init(config: UdpLibraryConnectionConfig) {
        self.config = config
        let maximum = max(1, config.maxReliablePayloadBytes)
        self.maximumDataBytes = maximum
        self.congestionWindowMinimum = maximum
        let start = min(4 * maximum, max(2 * maximum, 4380))
        self.congestionWindowStart = max(start, 8 * 1024)
        self.congestionWindowSize = congestionWindowStart
        self.slowStartThreshold = min(
            Self.maximumOutstandingPackets * maximum,
            Self.maximumOutstandingBytes
        )
    }

    mutating func reset() {
        entries.removeAll()
        nextID = 0
        pendingID = 0
        averagePing = 800
        congestionWindowSize = congestionWindowStart
        lastAcknowledgedSend = 0
        windowResetTime = 0
        maxxedOutCurrentWindow = false
        tolerantLosses = 0
    }

    /// Reconstructs the full 64-bit id from a 16-bit wire stamp exactly as
    /// `GetReliableOutgoingId` does for the low word of `ReliableOutgoingId`.
    private func fullID(for stamp: UInt16) -> UInt64 {
        var id = UInt64(stamp) | (nextID & ~0xffff)
        if id > nextID, nextID >= 0x10000 { id -= 0x10000 }
        return id
    }

    /// Registers a frame the session just encoded and sent. Sessions own frame
    /// construction; this state only learns the stamp, channel and byte size.
    mutating func noteSent(
        stamp: UInt16,
        channel: UInt8,
        length: Int,
        now: UInt64
    ) {
        let id = fullID(for: stamp)
        if var entry = entries[id] {
            entry.lastSend = now
            entry.sendCount += 1
            entries[id] = entry
        } else {
            entries[id] = Entry(
                id: id,
                channel: channel,
                length: max(1, length),
                firstSend: now,
                lastSend: now,
                sendCount: 1
            )
        }
        if id >= nextID { nextID = id + 1 }
    }

    private var resendDelay: UInt64 {
        min(
            Self.resendDelayCap,
            averagePing * Self.resendDelayPercent / 100 + Self.resendDelayAdjust
        )
    }

    private mutating func acknowledge(id: UInt64, channel: UInt8, now: UInt64) {
        guard id >= pendingID, id < nextID,
              let entry = entries[id], entry.channel == channel
        else { return }

        if maxxedOutCurrentWindow {
            if congestionWindowSize < slowStartThreshold {
                congestionWindowSize += maximumDataBytes
            } else {
                let increase = maximumDataBytes * maximumDataBytes / max(1, congestionWindowSize)
                congestionWindowSize += max(1, increase)
            }
        }
        if entry.sendCount == 1 {
            let sample = now >= entry.firstSend ? now - entry.firstSend : 0
            averagePing = (averagePing * 3 + sample) / 4
        }
        lastAcknowledgedSend = entry.firstSend
        entries.removeValue(forKey: id)
        while pendingID < nextID, entries[pendingID] == nil {
            pendingID += 1
        }
    }

    mutating func acknowledge(type: UInt8, stamp: UInt16, now: UInt64) {
        guard let channel = UdpLibrary.channel(forAckType: type) else { return }
        acknowledge(id: fullID(for: stamp), channel: channel, now: now)
    }

    mutating func acknowledgeAll(type: UInt8, stamp: UInt16, now: UInt64) {
        guard let channel = UdpLibrary.channel(forAckType: type) else { return }
        let id = fullID(for: stamp)
        if pendingID > id {
            averagePing = min(Self.resendDelayCap, averagePing + 400)
        }
        guard id >= pendingID else { return }
        // The wire id is 16-bit but the loop is over full logical ids; cap the
        // work at the outstanding window in case a corrupt stamp is accepted.
        let end = min(id, pendingID + UInt64(Self.maximumOutstandingPackets))
        var cursor = pendingID
        while cursor <= end {
            acknowledge(id: cursor, channel: channel, now: now)
            cursor += 1
        }
    }

    /// Mirrors `GiveTime`: returns the stamps that should be resent now and
    /// how long the caller should wait before asking again.
    mutating func giveTime(now: UInt64) -> Tick {
        let limit = min(Self.maximumOutstandingBytes, congestionWindowSize)
        guard pendingID < nextID, !entries.isEmpty else {
            congestionWindowSize = congestionWindowStart
            return Tick(resends: [], delay: resendDelay)
        }

        let optimalResendDelay = resendDelay
        let oldestResendTime = max(
            now >= optimalResendDelay ? now - optimalResendDelay : 0,
            lastAcknowledgedSend
        )
        var ready: [UInt64] = []
        var outstanding = 0

        for id in pendingID..<nextID {
            guard let entry = entries[id] else { continue }
            if entry.lastSend < oldestResendTime {
                ready.append(id)
            } else {
                outstanding += entry.length
            }
        }

        var allowWindowReset = now >= windowResetTime
            ? now - windowResetTime > averagePing
            : false
        var losses = 0
        var resends: [Resend] = []
        var timedOut = false

        for id in ready {
            guard var entry = entries[id], outstanding < limit else { continue }
            if entry.sendCount > 1 {
                let age = now >= entry.firstSend ? now - entry.firstSend : 0
                if age > Self.oldestUnacknowledgedTimeout {
                    timedOut = true
                    break
                }
                if entry.lastSend < lastAcknowledgedSend {
                    if allowWindowReset, losses > Self.toleranceLossCount {
                        allowWindowReset = false
                        windowResetTime = now
                        congestionWindowSize = max(
                            congestionWindowMinimum,
                            congestionWindowSize * 3 / 4
                        )
                    }
                    losses += 1
                } else if allowWindowReset {
                    allowWindowReset = false
                    windowResetTime = now
                    congestionWindowSize = max(
                        maximumDataBytes * 2,
                        congestionWindowSize / 2
                    )
                    congestionWindowSize = min(congestionWindowSize, slowStartThreshold)
                    averagePing = min(Self.resendDelayCap, averagePing + 100)
                }
            }
            entry.lastSend = now
            entry.sendCount += 1
            entries[id] = entry
            outstanding += entry.length
            resends.append(Resend(id: UInt16(truncatingIfNeeded: id), channel: entry.channel))
        }

        // C# sets `MaxxedOutCurrentWindow` after sending the ready queue; ACKs
        // only grow the congestion window when that flag was true.
        maxxedOutCurrentWindow = outstanding >= limit

        // `GiveTime` returns the time until the next packet becomes due, not a
        // fresh full resend delay. Entries skipped because the window is full
        // already have a negative remaining time and request immediate work.
        var delay = optimalResendDelay
        for entry in entries.values {
            let age = now >= entry.lastSend ? now - entry.lastSend : 0
            delay = min(delay, age >= optimalResendDelay ? 0 : optimalResendDelay - age)
        }

        return Tick(resends: resends, delay: delay, timedOut: timedOut)
    }

    var pendingStamps: [UInt16] {
        entries.keys.sorted().map { UInt16(truncatingIfNeeded: $0) }
    }

    /// Stamp assigned to the next physical frame. Callers must encode and call
    /// `noteSent` before asking again so high-word reconstruction stays aligned.
    var nextStamp: UInt16 { UInt16(truncatingIfNeeded: nextID) }
}

/// One physical reliable frame planned from a logical application packet.
/// `outstandingBytes` is Sanctuary's `bytesToSend`: the four-byte fragment
/// length header is part of the body but not of the congestion-window charge.
struct UdpLibraryOutboundFragment: Equatable, Sendable {
    let type: UInt8
    let body: Data
    let outstandingBytes: Int
}

/// Ports `UdpReliableChannel.PullDown` for a single logical packet: small
/// packets stay whole, larger ones reserve four bytes in the first frame for
/// the big-endian total length and then fill later frames completely.
enum UdpLibraryFragmenter {
    static func split(
        applicationPayload: Data,
        maxPayloadBytes: Int
    ) -> [UdpLibraryOutboundFragment] {
        var logical = applicationPayload
        if logical.first == UdpLibrary.marker {
            logical.insert(UdpLibrary.marker, at: 0)
        }

        if logical.count <= maxPayloadBytes {
            return [UdpLibraryOutboundFragment(
                type: UdpFrameType.reliable1.rawValue,
                body: logical,
                outstandingBytes: logical.count
            )]
        }
        guard maxPayloadBytes > 4 else { return [] }

        let total = UInt32(logical.count)
        var first = Data([
            UInt8(truncatingIfNeeded: total >> 24),
            UInt8(truncatingIfNeeded: total >> 16),
            UInt8(truncatingIfNeeded: total >> 8),
            UInt8(truncatingIfNeeded: total)
        ])
        let firstChunkLength = maxPayloadBytes - 4
        first.append(contentsOf: logical.prefix(firstChunkLength))
        var result = [UdpLibraryOutboundFragment(
            type: UdpFrameType.fragment1.rawValue,
            body: first,
            outstandingBytes: firstChunkLength
        )]

        var offset = firstChunkLength
        while offset < logical.count {
            let length = min(maxPayloadBytes, logical.count - offset)
            result.append(UdpLibraryOutboundFragment(
                type: UdpFrameType.fragment1.rawValue,
                body: Data(logical[offset..<(offset + length)]),
                outstandingBytes: length
            ))
            offset += length
        }
        return result
    }
}

/// Cooked ACK frames waiting for Sanctuary's 50 ms Multi-buffer flush. C#
/// keeps a pointer to the earliest buffered ACK and overwrites it with a later
/// AckAll when deduping is enabled, so the cumulative ACK is processed before
/// any selective ACKs already queued behind it.
struct UdpLibraryBufferedAcks {
    private var packets: [Data] = []
    private var earliestAckIndex: Int?

    var count: Int { packets.count }

    /// Length of the cooked Multi datagram, excluding flag and CRC. An empty
    /// buffer has no two-byte Multi header yet.
    var cookedLength: Int {
        guard !packets.isEmpty else { return 0 }
        return 2 + packets.reduce(0) { $0 + 1 + $1.count }
    }

    mutating func enqueue(
        type: UInt8,
        reliableID: UInt16,
        isAckAll: Bool,
        deduping: Bool = true
    ) {
        let body = UdpLibrary.encodeAckBody(type: type, reliableID: reliableID)
        if isAckAll, deduping, let index = earliestAckIndex {
            packets[index] = body
            return
        }
        if packets.isEmpty { earliestAckIndex = 0 }
        packets.append(body)
    }

    mutating func flush(
        encryptCode: UInt32,
        userSuppliedCompression: Bool
    ) -> Data? {
        guard !packets.isEmpty else { return nil }
        defer { reset() }

        if packets.count == 1 {
            return UdpLibrary.encodePhysical(
                cookedBody: packets[0],
                encryptCode: encryptCode,
                userSuppliedCompression: userSuppliedCompression
            )
        }

        var cooked = Data([UdpLibrary.marker, 3])
        for packet in packets {
            cooked.append(UInt8(truncatingIfNeeded: packet.count))
            cooked.append(contentsOf: packet)
        }
        return UdpLibrary.encodePhysical(
            cookedBody: cooked,
            encryptCode: encryptCode,
            userSuppliedCompression: userSuppliedCompression
        )
    }

    mutating func reset() {
        packets.removeAll()
        earliestAckIndex = nil
    }
}

enum UdpLibrary {
    static let marker: UInt8 = 0
    static let crcByteCount = 2
    static let maximumReassemblyLength = 4 * 1024 * 1024

    /// `UdpConnection.IsNonEncryptPacket` in the authoritative Sanctuary
    /// source: Connect, Confirm, UnreachableConnection, RequestRemap, Unknown,
    /// and ServerStatus. Ordered2 (27) and PortAlive (28) are raw-sent only in
    /// the manager's pre-connection dispatch, not by this connection check.
    static func isNonEncrypted(_ type: UInt8) -> Bool {
        type == 1 || // Connect
        type == 2 || // Confirm
        type == 29 || // UnreachableConnection
        type == 30 || // RequestRemap
        type == 31 || // Unknown
        type == 32 // ServerStatus
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
            result.append(try inflateZlib(Data(cookedBytes.dropFirst(3))))
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
    /// `UdpConnection.Send` prepends a zero-escape byte when an application
    /// packet starts with zero; this helper applies that boundary for whole
    /// logical packets. Fragment planners apply it before splitting instead.
    static func encodeReliable(
        type: UInt8,
        reliableID: UInt16,
        encryptCode: UInt32,
        userSuppliedCompression: Bool,
        payload: Data
    ) -> Data {
        var body = payload
        if body.first == marker {
            body.insert(marker, at: 0)
        }
        return encodeReliableBody(
            type: type,
            reliableID: reliableID,
            encryptCode: encryptCode,
            userSuppliedCompression: userSuppliedCompression,
            body: body
        )
    }

    /// Encodes an already prepared logical body. This is used for fragments,
    /// whose four-byte total-length header must not receive a second escape.
    static func encodeReliableBody(
        type: UInt8,
        reliableID: UInt16,
        encryptCode: UInt32,
        userSuppliedCompression: Bool,
        body: Data
    ) -> Data {
        var data = Data([marker, type])
        if userSuppliedCompression {
            data.append(0) // raw; this client never compresses outbound packets
        }
        data.append(UInt8(truncatingIfNeeded: reliableID >> 8))
        data.append(UInt8(truncatingIfNeeded: reliableID))
        data.append(contentsOf: body)

        let crc = UInt16(truncatingIfNeeded: CRC32.checksum(data, encryptCode: encryptCode))
        data.append(UInt8(truncatingIfNeeded: crc >> 8))
        data.append(UInt8(truncatingIfNeeded: crc))
        return data
    }

    /// `UdpReliableChannel` uses Fragment1-4 for the same four channels as
    /// Reliable1-4. The first fragment's body includes the big-endian total
    /// logical length before its chunk.
    static func encodeFragment(
        type: UInt8,
        reliableID: UInt16,
        encryptCode: UInt32,
        userSuppliedCompression: Bool,
        body: Data
    ) -> Data {
        encodeReliableBody(
            type: type,
            reliableID: reliableID,
            encryptCode: encryptCode,
            userSuppliedCompression: userSuppliedCompression,
            body: body
        )
    }

    /// Cooked four-byte ACK body from `UdpReliableChannel`: marker, Ack type,
    /// big-endian reliable id. This is also the Multi subpacket representation.
    static func encodeAckBody(type: UInt8, reliableID: UInt16) -> Data {
        var data = Data([marker, type])
        appendBE16(reliableID, to: &data)
        return data
    }

    /// Applies the negotiated user-supplied flag and CRC to an already cooked
    /// internal datagram. `BufferedSend`/`PhysicalSend` do this once for the
    /// whole Multi container, not once per buffered ACK.
    static func encodePhysical(
        cookedBody: Data,
        encryptCode: UInt32,
        userSuppliedCompression: Bool
    ) -> Data {
        var data = cookedBody
        if userSuppliedCompression {
            data.insert(0, at: 2) // raw; this client never compresses outbound packets
        }
        let crc = UInt16(truncatingIfNeeded: CRC32.checksum(data, encryptCode: encryptCode))
        appendBE16(crc, to: &data)
        return data
    }

    /// Build the ACK frame Sanctuary emits from `UdpReliableChannel`. The
    /// user-supplied pass applies to ACKs too: it inserts its 0/1 flag at byte 2,
    /// so the reliable id moves to bytes 3-4 whenever compression is negotiated.
    static func encodeAck(
        type: UInt8,
        reliableID: UInt16,
        encryptCode: UInt32,
        userSuppliedCompression: Bool
    ) -> Data {
        encodePhysical(
            cookedBody: encodeAckBody(type: type, reliableID: reliableID),
            encryptCode: encryptCode,
            userSuppliedCompression: userSuppliedCompression
        )
    }

    /// Build the two-byte `KeepAlive` internal frame. Sanctuary still applies
    /// its negotiated user-supplied and CRC passes, so the additional flag is
    /// inserted after the internal header and the CRC covers all preceding
    /// bytes (`UdpConnection.cs:1328-1348` and `PhysicalSend`).
    static func encodeKeepAlive(
        encryptCode: UInt32,
        userSuppliedCompression: Bool
    ) -> Data {
        var data = Data([marker, UdpFrameType.keepAlive.rawValue])
        if userSuppliedCompression {
            data.append(0) // raw; the empty body is never smaller compressed
        }
        let crc = UInt16(truncatingIfNeeded: CRC32.checksum(data, encryptCode: encryptCode))
        appendBE16(crc, to: &data)
        return data
    }

    /// Ack channel for a reliable or fragment packet type.
    static func ackType(for reliableType: UInt8) -> UInt8? {
        guard channel(for: reliableType) != nil else { return nil }
        return 17 + ((reliableType - 9) % 4)
    }

    /// Cumulative AckAll channel. `UdpReliableChannel.ReliablePacket` emits
    /// AckAll when a retransmitted id is older than the next id it expects.
    static func ackAllType(for reliableType: UInt8) -> UInt8? {
        guard channel(for: reliableType) != nil else { return nil }
        return 21 + ((reliableType - 9) % 4)
    }

    /// Zero-based reliable channel used by Reliable1-4 and Fragment1-4.
    static func channel(for reliableType: UInt8) -> UInt8? {
        guard reliableType >= 9, reliableType <= 16 else { return nil }
        return (reliableType - 9) % 4
    }

    /// Ack1-4 and AckAll1-4 are routed to the same channel as their reliable
    /// frames (`UdpConnection.ProcessIncomingPacket`).
    static func channel(forAckType type: UInt8) -> UInt8? {
        if type >= 17, type <= 20 { return type - 17 }
        if type >= 21, type <= 24 { return type - 21 }
        return nil
    }

    /// Wrap-safe ordering for 16-bit reliable stamps, matching C#'s
    /// `GetReliableIncomingId` window rather than plain integer comparison.
    static func reliableID(_ lhs: UInt16, isAheadOf rhs: UInt16) -> Bool {
        let delta = lhs &- rhs
        return delta != 0 && delta < 0x8000
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
            guard pointer + length <= bytes.count else { break }
            // Sanctuary processes every slice, including a zero-length slice,
            // then advances. Empty entries must not truncate the container.
            if length > 0 {
                result.append(contentsOf: parse(Data(bytes[pointer..<(pointer + length)]), state: &state))
            }
            pointer += length
        }
        return result
    }

    private static func appendBE16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }

    private static func readBE16(_ bytes: [UInt8], offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private static func readBE32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24) |
            (UInt32(bytes[offset + 1]) << 16) |
            (UInt32(bytes[offset + 2]) << 8) |
            UInt32(bytes[offset + 3])
    }

    /// Sanctuary's `ZLib.Decompress` consumes an RFC 1950 zlib stream: a
    /// two-byte CMF/FLG header, raw DEFLATE data, and a four-byte Adler-32
    /// trailer. Apple's `COMPRESSION_ZLIB` decoder is misleadingly named: the
    /// SDK implements raw RFC 1951 DEFLATE (`deflateInit2(..., -15, ...)`).
    /// Feeding it the zlib wrapper produced `decompressionFailed` on device
    /// for every valid gateway reply. Strip the wrapper here and verify the
    /// checksum ourselves. Sanctuary's optional `A1B2C3D4` length prefix is
    /// handled too, although the gateway does not emit it.
    static func splitZlibStream(_ source: Data) throws -> (deflate: Data, checksum: UInt32) {
        let bytes = Array(source)
        var offset = 0
        if bytes.count > 8, readBE32(bytes, offset: 0) == 0xA1B2_C3D4 {
            offset = 8
        }
        guard bytes.count >= offset + 6 else {
            throw UdpLibraryError.truncated("zlib stream")
        }

        let cmf = bytes[offset]
        let flg = bytes[offset + 1]
        guard cmf & 0x0f == 8, // DEFLATE method
              flg & 0x20 == 0, // no preset dictionary
              (UInt32(cmf) << 8 | UInt32(flg)) % 31 == 0
        else {
            throw UdpLibraryError.invalidZlibHeader
        }

        let deflate = Data(bytes[(offset + 2)..<(bytes.count - 4)])
        return (deflate, readBE32(bytes, offset: bytes.count - 4))
    }

    private static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return (b << 16) | a
    }

    /// Decompresses an RFC 1950 zlib stream and verifies its Adler-32 trailer.
    /// Also used by the native chunk reader for shipped `GCNK` archives.
    static func inflateZlib(_ source: Data) throws -> Data {
        let zlib = try splitZlibStream(source)
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

        let input = zlib.deflate
        return try input.withUnsafeBytes { inputBuffer in
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
                    // All input is available in one datagram, so finalize the
                    // raw DEFLATE stream on every call. The C flag's numeric
                    // value is 1; the SDK imports it as a flag type, not Int32.
                    return compression_stream_process(&stream, 1)
                }
                guard status == COMPRESSION_STATUS_OK || status == COMPRESSION_STATUS_END else {
                    throw UdpLibraryError.decompressionFailed
                }
                let produced = bufferSize - stream.dst_size
                output.append(contentsOf: scratch.prefix(produced))
                if status == COMPRESSION_STATUS_END { break }
                if stream.src_size == 0 && produced == 0 {
                    throw UdpLibraryError.decompressionFailed
                }
            }

            let actual = adler32(output)
            guard actual == zlib.checksum else {
                throw UdpLibraryError.zlibChecksumMismatch(
                    expected: zlib.checksum,
                    actual: actual
                )
            }
            return output
        }
        #else
        _ = zlib
        throw UdpLibraryError.compressionUnavailable
        #endif
    }
}
