import Foundation
#if canImport(Compression)
import Compression
#endif

// Receive/send-side port of Sanctuary.UdpLibrary/UdpConnection.cs and
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
// This file carries the complete negotiated wire model: CRC widths 1-4, both
// encryption passes (None, UserSupplied, UserSupplied2, XorBuffer, Xor),
// 16-bit reliable stamps reconstructed into 64-bit ids, per-channel ordering,
// and per-channel fragment reassembly before application delivery.

enum UdpLibraryError: Error, LocalizedError, Equatable {
    case truncated(String)
    case badMarker(UInt8)
    case crcMismatch(expected: UInt16, actual: UInt16)
    case crcMismatch32(expected: UInt32, actual: UInt32, width: Int)
    case unsupportedCompression(UInt8)
    case compressionUnavailable
    case decompressionFailed
    case invalidZlibHeader
    case zlibChecksumMismatch(expected: UInt32, actual: UInt32)
    case fragmentTooLarge(Int)
    case fragmentOverflow
    case unsupportedEncryptMethod(UInt8)
    case unsupportedCRCWidth(Int)

    var errorDescription: String? {
        switch self {
        case .truncated(let what): return "Truncated UdpLibrary packet: \(what)."
        case .badMarker(let value): return "Invalid UdpLibrary marker 0x\(String(value, radix: 16))."
        case .crcMismatch(let expected, let actual):
            return "UdpLibrary CRC mismatch: expected 0x\(String(expected, radix: 16)), got 0x\(String(actual, radix: 16))."
        case .crcMismatch32(let expected, let actual, let width):
            return "UdpLibrary CRC-\(width) mismatch: expected 0x\(String(expected, radix: 16)), got 0x\(String(actual, radix: 16))."
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
        case .unsupportedEncryptMethod(let method):
            return "Unsupported UdpLibrary encrypt method \(method)."
        case .unsupportedCRCWidth(let width):
            return "Unsupported UdpLibrary CRC width \(width)."
        }
    }
}

/// Sanctuary `EncryptMethod` values from `Enumerations/EncryptMethod.cs`.
enum UdpLibraryEncryptMethod: UInt8, Sendable {
    case none = 0
    case userSupplied = 1
    case userSupplied2 = 2
    case xorBuffer = 3
    case xor = 4

    init?(rawMethod: UInt8) { self.init(rawValue: rawMethod) }
}

/// A packet after CRC validation and all negotiated decryption passes.
enum UdpLibraryPacket: Equatable {
    case application(Data)
    /// Ordered transport frame; produced by `parseTransport` before inbound
    /// reliable ordering and fragment reassembly.
    case frame(type: UInt8, reliableID: UInt16, body: Data, isFragment: Bool)
    /// Reassembled reliable frame; produced by the normal `parse` path used by
    /// standalone decoder tests.
    case reliable(type: UInt8, reliableID: UInt16, body: Data, applications: [Data])
    case ack(type: UInt8, reliableID: UInt16)
    case ackAll(type: UInt8, reliableID: UInt16)
    case internalPacket(UInt8)
}

/// Per-channel fragment assembly. Sanctuary reassembles only after a frame has
/// passed reliable ordering, so this state is owned by
/// `UdpLibraryIncomingReliableState` in the live sessions.
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
    var wasCorrupt = false
}

/// Receive-side ordered reliable channels. C# `UdpReliableChannel` buffers
/// packets that arrive ahead of the next expected id, delivers them only when
/// the gap is filled, suppresses duplicates, and reassembles fragments only
/// after ordering. Full ids are reconstructed from 16-bit wire stamps exactly
/// as `GetReliableIncomingId` does.
struct UdpLibraryIncomingReliableState {
    private struct Entry {
        let body: Data
        let applications: [Data]
        let isFragment: Bool
    }

    /// Sanctuary's default `MaxInstandingPackets` / `MaxOutstandingPackets`.
    private static let windowSize = 400
    private static let hardMaxOutstandingPackets = 30_000

    private var expectedByChannel: [UInt8: Int64] = [:]
    private var bufferedByChannel: [UInt8: [Int64: Entry]] = [:]
    private var reassemblyByChannel: [UInt8: UdpLibraryReassemblyState] = [:]

    mutating func reset() {
        expectedByChannel.removeAll()
        bufferedByChannel.removeAll()
        reassemblyByChannel.removeAll()
    }

    /// Convenience path for already-decoded application payloads. Kept for the
    /// decoder tests and for callers that do not use transport frames.
    mutating func receive(
        type: UInt8,
        reliableID: UInt16,
        applications: [Data]
    ) -> UdpLibraryIncomingAck? {
        receiveFrame(
            type: type,
            reliableID: reliableID,
            body: Data(),
            isFragment: false,
            maxReassemblyLength: UdpLibrary.maximumReassemblyLength,
            preDecodedApplications: applications
        )
    }

    /// Live-session path. `body` is the bytes after the four-byte reliable
    /// header; for a fragment it includes the big-endian total length on the
    /// first fragment only.
    mutating func receiveFrame(
        type: UInt8,
        reliableID: UInt16,
        body: Data,
        isFragment: Bool,
        maxReassemblyLength: Int = UdpLibrary.maximumReassemblyLength,
        preDecodedApplications: [Data]? = nil
    ) -> UdpLibraryIncomingAck? {
        guard let channel = UdpLibrary.channel(for: type),
              let ackType = UdpLibrary.ackType(for: type),
              let ackAllType = UdpLibrary.ackAllType(for: type)
        else { return nil }

        let expected = expectedByChannel[channel] ?? 0
        let id = Self.fullID(for: reliableID, expected: expected)
        var buffered = bufferedByChannel[channel] ?? [:]
        var deliver: [Data] = []
        var corrupt = false

        // Packets beyond the reconstruction tolerance are deliberately ignored
        // so a stale/corrupt stamp cannot poison the ring slots.
        guard id < expected + Int64(Self.windowSize) else {
            return UdpLibraryIncomingAck(
                type: ackType,
                reliableID: reliableID,
                applications: [],
                wasCorrupt: true
            )
        }

        if id == expected {
            let outcome = consume(
                channel: channel,
                body: body,
                isFragment: isFragment,
                preDecodedApplications: preDecodedApplications,
                maxReassemblyLength: maxReassemblyLength
            )
            deliver = outcome.applications
            corrupt = outcome.corrupt
            var next = expected + 1
            while let entry = buffered[next] {
                buffered.removeValue(forKey: next)
                let drained = consume(
                    channel: channel,
                    body: entry.body,
                    isFragment: entry.isFragment,
                    preDecodedApplications: entry.applications.isEmpty ? nil : entry.applications,
                    maxReassemblyLength: maxReassemblyLength
                )
                deliver.append(contentsOf: drained.applications)
                corrupt = corrupt || drained.corrupt
                next += 1
            }
            expectedByChannel[channel] = next
            bufferedByChannel[channel] = buffered
            return UdpLibraryIncomingAck(
                type: ackAllType,
                reliableID: UInt16(truncatingIfNeeded: next - 1),
                applications: deliver,
                wasCorrupt: corrupt
            )
        }

        if id > expected {
            if buffered[id] == nil {
                buffered[id] = Entry(
                    body: body,
                    applications: preDecodedApplications ?? [],
                    isFragment: isFragment
                )
            }
            bufferedByChannel[channel] = buffered
            return UdpLibraryIncomingAck(
                type: ackType,
                reliableID: reliableID,
                applications: []
            )
        }

        // A retransmission below the head is cumulative-acknowledged without
        // being delivered or reassembled a second time.
        return UdpLibraryIncomingAck(
            type: ackAllType,
            reliableID: UInt16(truncatingIfNeeded: expected - 1),
            applications: [],
            wasDuplicate: true
        )
    }

    private static func fullID(for stamp: UInt16, expected: Int64) -> Int64 {
        // C# reconstructs a signed 64-bit id from the 16-bit stamp and the high
        // word of the in-order head. A stamp just before zero reconstructs to
        // -1 and is correctly treated as a duplicate, not a future packet.
        let high = expected & ~0xffff
        var id = Int64(stamp) | high
        let hard = Int64(hardMaxOutstandingPackets)
        if id < expected - hard { id += 0x1_0000 }
        if id > expected + hard { id -= 0x1_0000 }
        return id
    }

    private mutating func consume(
        channel: UInt8,
        body: Data,
        isFragment: Bool,
        preDecodedApplications: [Data]?,
        maxReassemblyLength: Int
    ) -> (applications: [Data], corrupt: Bool) {
        guard isFragment else {
            if let reassembly = reassemblyByChannel[channel], reassembly.fragment != nil {
                // Sanctuary disconnects on FragmentExpected; the live session
                // reports corruption and drops the packet.
                return ([], true)
            }
            if let preDecodedApplications { return (preDecodedApplications, false) }
            // The live parse path deliberately returns transport frames before
            // application decoding. Decode only after ordering so out-of-order
            // packets cannot deliver data early.
            var scratch = UdpLibraryReassemblyState()
            let applications = UdpLibrary.parse(Data(body), state: &scratch).compactMap { packet -> Data? in
                guard case .application(let data) = packet else { return nil }
                return data
            }
            return (applications, false)
        }

        var state = reassemblyByChannel[channel] ?? UdpLibraryReassemblyState()
        var chunk = body
        if state.fragment == nil {
            guard chunk.count >= 4 else { return ([], true) }
            let length = UdpLibrary.readBE32(Array(chunk), offset: 0)
            guard length > 0, length <= UInt64(maxReassemblyLength) else { return ([], true) }
            state.targetLength = Int(length)
            state.fragment = Data()
            chunk = Data(chunk.dropFirst(4))
        }
        guard let fragment = state.fragment else { return ([], true) }
        guard fragment.count + chunk.count <= state.targetLength else {
            state.reset()
            reassemblyByChannel[channel] = state
            return ([], true)
        }
        state.fragment!.append(chunk)
        guard state.fragment!.count == state.targetLength else {
            reassemblyByChannel[channel] = state
            return ([], false)
        }
        let complete = state.fragment!
        state.reset()
        reassemblyByChannel[channel] = state
        let applications = UdpLibrary.parse(complete).compactMap { packet -> Data? in
            guard case .application(let data) = packet else { return nil }
            return data
        }
        return (applications, false)
    }
}

/// Negotiated connection facts from a UdpLibrary Confirm packet. All five
/// encryption methods and CRC widths 1-4 are represented because a peer may
/// negotiate them even though the public Sanctuary gateway uses CRC-2, method
/// 1 (UserSupplied) and method 0.
struct UdpLibraryConnectionConfig: Equatable, Sendable {
    var encryptCode: UInt32
    var crcBytes: Int
    var encryptMethod1: UInt8
    var encryptMethod2: UInt8
    var maxRawPacketSize: Int

    /// Sanctuary's externally configured expansion bytes. The login and
    /// gateway servers set `UserSuppliedEncryptExpansionBytes = 1`; the second
    /// pass defaults to zero.
    var userSuppliedEncryptExpansionBytes = 1
    var userSuppliedEncryptExpansionBytes2 = 0

    var userSuppliedCompression: Bool { encryptMethod1 == UInt8(UdpLibraryEncryptMethod.userSupplied.rawValue) }

    var encryptMethods: [UInt8] { [encryptMethod1, encryptMethod2] }

    var encryptExpansionBytes: Int {
        var expansion = 0
        if encryptMethod1 == UInt8(UdpLibraryEncryptMethod.userSupplied.rawValue) {
            expansion += userSuppliedEncryptExpansionBytes
        } else if encryptMethod1 == UInt8(UdpLibraryEncryptMethod.userSupplied2.rawValue) {
            expansion += userSuppliedEncryptExpansionBytes2
        }
        if encryptMethod2 == UInt8(UdpLibraryEncryptMethod.userSupplied.rawValue) {
            expansion += userSuppliedEncryptExpansionBytes
        } else if encryptMethod2 == UInt8(UdpLibraryEncryptMethod.userSupplied2.rawValue) {
            expansion += userSuppliedEncryptExpansionBytes2
        }
        return expansion
    }

    var isValid: Bool {
        guard (0...4).contains(crcBytes), maxRawPacketSize > 0 else { return false }
        return encryptMethods.allSatisfy { UdpLibraryEncryptMethod(rawValue: $0) != nil }
    }

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
    private var slowStartThreshold: Int

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
    var availableWindowBytes: Int { max(0, min(Self.maximumOutstandingBytes, congestionWindowSize) - outstandingBytes) }
    var availableWindowPackets: Int { max(0, Self.maximumOutstandingPackets - entries.count) }
    var hasWindowSpace: Bool { availableWindowBytes > 0 && availableWindowPackets > 0 }

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
        slowStartThreshold = min(
            Self.maximumOutstandingPackets * maximumDataBytes,
            Self.maximumOutstandingBytes
        )
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
    /// construction; this state only learns the stamp, channel and body byte
    /// count (Sanctuary's congestion window excludes headers and CRC).
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
            // C# resets the window when the pipe is empty.
            congestionWindowSize = congestionWindowStart
            slowStartThreshold = min(
                Self.maximumOutstandingPackets * maximumDataBytes,
                Self.maximumOutstandingBytes
            )
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
                        // Accelerated reset: window *= 3/4, floored at minimum.
                        congestionWindowSize = max(
                            congestionWindowMinimum,
                            congestionWindowSize * 3 / 4
                        )
                        slowStartThreshold = congestionWindowSize
                    }
                    losses += 1
                } else if allowWindowReset {
                    allowWindowReset = false
                    windowResetTime = now
                    // Timeout reset: threshold = max(2*MaxDataBytes, window/2),
                    // then window returns to CongestionWindowStart.
                    slowStartThreshold = max(maximumDataBytes * 2, congestionWindowSize / 2)
                    congestionWindowSize = congestionWindowStart
                    averagePing = min(Self.resendDelayCap, averagePing + 100)
                }
            }
            entry.lastSend = now
            entry.sendCount += 1
            entries[id] = entry
            outstanding += entry.length
            resends.append(Resend(id: UInt16(truncatingIfNeeded: id), channel: entry.channel))
        }

        maxxedOutCurrentWindow = outstanding >= limit

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

    /// Channel-aware identities so sessions can prune retransmission buffers
    /// after an AckAll without discarding a different channel's frame that
    /// happens to carry the same 16-bit stamp.
    struct PendingIdentity: Hashable, Sendable {
        let channel: UInt8
        let stamp: UInt16
    }

    var pendingIdentities: Set<PendingIdentity> {
        Set(entries.values.map {
            PendingIdentity(channel: $0.channel, stamp: UInt16(truncatingIfNeeded: $0.id))
        })
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

/// Ports `UdpMisc.PutVariableValue` for outbound Group containers.
enum UdpLibraryGroupCodec {
    static func encode(_ payloads: [Data]) -> Data {
        var data = Data([UdpLibrary.marker, 25])
        for payload in payloads {
            appendVariableValue(payload.count, to: &data)
            data.append(payload)
        }
        return data
    }

    static func appendVariableValue(_ value: Int, to data: inout Data) {
        if value < 254 {
            data.append(UInt8(truncatingIfNeeded: value))
        } else if value < 0xffff {
            data.append(contentsOf: [0xff, UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
        } else {
            data.append(contentsOf: [
                0xff, 0xff, 0xff,
                UInt8(truncatingIfNeeded: value >> 24),
                UInt8(truncatingIfNeeded: value >> 16),
                UInt8(truncatingIfNeeded: value >> 8),
                UInt8(truncatingIfNeeded: value)
            ])
        }
    }
}

/// Per-connection queue for `UdpReliableChannel.SendCoalesce`. Small logical
/// packets are combined into one Group frame; a single item is unwrapped back
/// to a plain logical packet in `FlushCoalesce`.
struct UdpLibraryOutboundCoalescer {
    private(set) var coalesceBody: Data?
    private(set) var coalesceCount = 0
    private var queued: [Data] = []
    let maxCoalesceAttemptBytes: Int

    init(maxReliablePayloadBytes: Int) {
        maxCoalesceAttemptBytes = maxReliablePayloadBytes - 5
    }

    var isEmpty: Bool { queued.isEmpty && coalesceBody == nil }

    mutating func enqueue(_ logicalPacket: Data) {
        guard !logicalPacket.isEmpty,
              logicalPacket.count <= maxCoalesceAttemptBytes,
              maxCoalesceAttemptBytes > 0
        else {
            // Oversized packets bypass coalescing and wait for window space.
            queued.append(logicalPacket)
            return
        }
        if coalesceBody == nil {
            var header = Data([UdpLibrary.marker, 25])
            UdpLibraryGroupCodec.appendVariableValue(logicalPacket.count, to: &header)
            header.append(logicalPacket)
            coalesceBody = header
        } else {
            UdpLibraryGroupCodec.appendVariableValue(logicalPacket.count, to: &coalesceBody!)
            coalesceBody!.append(logicalPacket)
        }
        coalesceCount += 1
    }

    /// Returns logical frame bodies ready for reliable framing, in send order.
    mutating func drain(maxBytes: Int, maxPackets: Int) -> [Data] {
        flushCoalesce()
        guard maxBytes > 0, maxPackets > 0 else { return [] }
        var result: [Data] = []
        while !queued.isEmpty, result.count < maxPackets {
            let packet = queued[0]
            let used = result.reduce(0) { $0 + $1.count }
            guard packet.count <= maxBytes - used else { break }
            result.append(packet)
            queued.removeFirst()
        }
        return result
    }

    mutating func flushCoalesce() {
        guard var body = coalesceBody else { return }
        if coalesceCount == 1 {
            let lengthBytes = UdpLibrary.variableValueLength(Array(body), offset: 2)
            let firstLength = UdpLibrary.readVariableValue(Array(body), offset: 2)
            body = Data(body[(2 + lengthBytes)..<(2 + lengthBytes + firstLength)])
        }
        queued.insert(body, at: 0)
        coalesceBody = nil
        coalesceCount = 0
    }
}

/// A cooked reliable frame that is ready to enter the shared Multi buffer.
/// Sessions keep the cooked form so retransmissions can be re-encrypted with
/// the current negotiated configuration instead of replaying a stale datagram.
struct UdpLibraryPreparedReliableFrame: Equatable, Sendable {
    let type: UInt8
    let stamp: UInt16
    let channel: UInt8
    let cooked: Data
    let outstandingBytes: Int
}

struct UdpLibraryOutboundPump: Equatable, Sendable {
    var newFrames: [UdpLibraryPreparedReliableFrame] = []
    var tick: UdpLibraryOutgoingReliableState.Tick
}

/// Send-side queue that ports `UdpReliableChannel.Send`/`GiveTime`/`PullDown`.
/// Logical packets are coalesced when small, fragmented at the negotiated
/// payload limit when large, and only assigned reliable ids when the congestion
/// window has room. This is what prevents the initial reliable sends from
/// bypassing Sanctuary's flow-control gate.
struct UdpLibraryOutboundQueue {
    let config: UdpLibraryConnectionConfig
    var coalescer: UdpLibraryOutboundCoalescer
    var reliable: UdpLibraryOutgoingReliableState
    private var fragments: [UdpLibraryOutboundFragment] = []

    init(config: UdpLibraryConnectionConfig) {
        self.config = config
        self.coalescer = UdpLibraryOutboundCoalescer(
            maxReliablePayloadBytes: config.maxReliablePayloadBytes
        )
        self.reliable = UdpLibraryOutgoingReliableState(config: config)
    }

    var hasPendingWork: Bool {
        !fragments.isEmpty || !coalescer.isEmpty || reliable.outstandingCount > 0
    }

    mutating func enqueue(_ logicalPacket: Data) {
        coalescer.enqueue(logicalPacket)
    }

    /// Reserves an id allocated by the gateway codec itself (the plaintext
    /// login frame) so queued gameplay packets cannot reuse its stamp.
    mutating func noteExternalSend(
        stamp: UInt16,
        channel: UInt8,
        length: Int,
        now: UInt64
    ) {
        reliable.noteSent(stamp: stamp, channel: channel, length: length, now: now)
    }

    mutating func pump(now: UInt64) -> UdpLibraryOutboundPump {
        let logicalPackets = coalescer.drain(maxBytes: Int.max, maxPackets: Int.max)
        for logical in logicalPackets {
            fragments.append(contentsOf: UdpLibraryFragmenter.split(
                applicationPayload: logical,
                maxPayloadBytes: config.maxReliablePayloadBytes
            ))
        }

        var result = UdpLibraryOutboundPump(tick: reliable.giveTime(now: now))
        while let fragment = fragments.first,
              reliable.availableWindowPackets > 0,
              fragment.outstandingBytes <= reliable.availableWindowBytes {
            fragments.removeFirst()
            let stamp = reliable.nextStamp
            let channel = UdpLibrary.channel(for: fragment.type) ?? 0
            let cooked = UdpLibrary.encodeReliableCookedBody(
                type: fragment.type,
                reliableID: stamp,
                body: fragment.body
            )
            reliable.noteSent(
                stamp: stamp,
                channel: channel,
                length: fragment.outstandingBytes,
                now: now
            )
            result.newFrames.append(UdpLibraryPreparedReliableFrame(
                type: fragment.type,
                stamp: stamp,
                channel: channel,
                cooked: cooked,
                outstandingBytes: fragment.outstandingBytes
            ))
        }
        return result
    }
}

/// Result of offering one cooked packet to the shared Multi buffer.
enum UdpLibraryBufferResult: Equatable {
    case buffered
    case flushed(Data)
    case unbuffered
}

/// Shared Multi buffer for ACKs and small cooked packets. C# keeps one
/// `MultiBufferData` and a per-channel `BufferedAckPtr`; flushing the buffer
/// sends one CRC-protected datagram and clears every channel's pointer.
struct UdpLibraryBufferedAcks {
    private var packets: [Data] = []
    private var earliestAckByChannel: [UInt8: Int] = [:]

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
        deduping: Bool = true,
        channel: UInt8? = nil
    ) {
        let body = UdpLibrary.encodeAckBody(type: type, reliableID: reliableID)
        let ackChannel = channel ?? UdpLibrary.channel(forAckType: type) ?? 0
        if isAckAll, deduping, let index = earliestAckByChannel[ackChannel] {
            packets[index] = body
            return
        }
        if packets.isEmpty { earliestAckByChannel[ackChannel] = 0 }
        packets.append(body)
    }

    /// Mirrors `UdpConnection.BufferedSend`. The caller sends the returned
    /// frame immediately for `.flushed` and `.unbuffered` results.
    /// Offers one cooked packet to the shared Multi buffer and returns every
    /// physical datagram that must be sent immediately. C# flushes the old
    /// buffer before an oversized or capacity-exceeding packet; dropping the
    /// flushed datagram would silently lose ACKs and reliable frames.
    mutating func offer(
        cooked: Data,
        config: UdpLibraryConnectionConfig
    ) -> [Data] {
        var sends: [Data] = []
        // C# `MaxDataHoldSize` is a separate UdpManager parameter; external
        // client configuration sets it equal to MaxRawPacketSize.
        let actualMaxHoldSize = config.maxRawPacketSize
        let total = cooked.count
        guard total <= 255, total + 3 <= actualMaxHoldSize else {
            if let frame = flush(config: config) { sends.append(frame) }
            sends.append(UdpLibrary.encodePhysical(cookedBody: cooked, config: config))
            return sends
        }

        let capacity = config.maxReliablePayloadBytes
        if cookedLength + total + 1 > capacity, let frame = flush(config: config) {
            sends.append(frame)
        }

        packets.append(cooked)
        if cookedLength >= actualMaxHoldSize, let frame = flush(config: config) {
            sends.append(frame)
        }
        return sends
    }

    mutating func enqueue(
        cooked: Data,
        config: UdpLibraryConnectionConfig
    ) -> UdpLibraryBufferResult {
        let sends = offer(cooked: cooked, config: config)
        if let first = sends.first { return .flushed(first) }
        return .buffered
    }

    mutating func flush(
        encryptCode: UInt32,
        userSuppliedCompression: Bool
    ) -> Data? {
        let config = UdpLibraryConnectionConfig(
            encryptCode: encryptCode,
            crcBytes: 2,
            encryptMethod1: userSuppliedCompression ? 1 : 0,
            encryptMethod2: 0,
            maxRawPacketSize: 512
        )
        return flush(config: config)
    }

    mutating func flush(config: UdpLibraryConnectionConfig) -> Data? {
        guard !packets.isEmpty else { return nil }
        defer { reset() }

        let cookedBody: Data
        if packets.count == 1 {
            cookedBody = packets[0]
        } else {
            var cooked = Data([UdpLibrary.marker, 3])
            for packet in packets {
                cooked.append(UInt8(truncatingIfNeeded: packet.count))
                cooked.append(contentsOf: packet)
            }
            cookedBody = cooked
        }
        return UdpLibrary.encodePhysical(cookedBody: cookedBody, config: config)
    }

    mutating func reset() {
        packets.removeAll()
        earliestAckByChannel.removeAll()
    }
}

/// Exact port of Sanctuary's two encryption passes and CRC widths.
enum UdpLibraryCrypto {
    static func encrypt(_ cooked: Data, config: UdpLibraryConnectionConfig) -> Data? {
        var current = cooked
        for method in config.encryptMethods {
            guard let next = transform(current, method: method, config: config, encrypt: true) else {
                return nil
            }
            current = next
        }
        return current
    }

    static func decrypt(_ encrypted: Data, config: UdpLibraryConnectionConfig) throws -> Data {
        var current = encrypted
        for method in config.encryptMethods.reversed() {
            guard let next = transform(current, method: method, config: config, encrypt: false) else {
                throw UdpLibraryError.decompressionFailed
            }
            current = next
        }
        return current
    }

    private static func transform(
        _ packet: Data,
        method: UInt8,
        config: UdpLibraryConnectionConfig,
        encrypt: Bool
    ) -> Data? {
        guard UdpLibraryEncryptMethod(rawValue: method) != nil else { return nil }
        // PhysicalSend preserves byte 0 and, for internal packets, byte 1.
        let prefixLength = packet.first == UdpLibrary.marker ? 2 : 1
        guard packet.count >= prefixLength else { return nil }
        let body = Data(packet.dropFirst(prefixLength))

        let transformed: Data
        switch UdpLibraryEncryptMethod(rawValue: method)! {
        case .none, .userSupplied2:
            transformed = body
        case .userSupplied:
            if encrypt {
                transformed = Data([0]) + body
            } else {
                guard let flag = body.first else { return nil }
                if flag == 1 {
                    guard let inflated = try? UdpLibrary.inflateZlib(Data(body.dropFirst())) else { return nil }
                    transformed = inflated
                } else {
                    transformed = Data(body.dropFirst())
                }
            }
        case .xorBuffer:
            let buffer = xorBuffer(config: config)
            transformed = xor(body, previousWord: config.encryptCode, buffer: buffer, encrypt: encrypt)
        case .xor:
            transformed = xor(body, previousWord: config.encryptCode, buffer: nil, encrypt: encrypt)
        }

        return Data(packet.prefix(prefixLength)) + transformed
    }

    private static func xor(
        _ body: Data,
        previousWord: UInt32,
        buffer: [UInt8]?,
        encrypt: Bool
    ) -> Data {
        var result = Data(repeating: 0, count: body.count)
        let bytes = Array(body)
        var previous = Int32(bitPattern: previousWord)
        var offset = 0

        while offset + 4 <= bytes.count {
            let hold = UdpLibrary.readLE32(bytes, offset: offset)
            let key: UInt32
            if let buffer {
                key = UdpLibrary.readLE32(buffer, offset: offset)
            } else {
                key = 0
            }
            let value = UInt32(bitPattern: previous) ^ hold ^ key
            UdpLibrary.writeLE32(value, to: &result, offset: offset)
            previous = Int32(bitPattern: encrypt ? value : hold)
            offset += 4
        }
        while offset < bytes.count {
            let key = buffer?[offset] ?? UInt8(truncatingIfNeeded: previous)
            result[offset] = bytes[offset] ^ key
            offset += 1
        }
        return result
    }

    private static func xorBuffer(config: UdpLibraryConnectionConfig) -> [UInt8] {
        let length = ((config.maxRawPacketSize + 1) / 4) * 4
        var seed = Int32(bitPattern: config.encryptCode)
        var result = [UInt8](repeating: 0, count: length)
        for index in 0..<length {
            let hi = seed / 127_773
            let lo = seed % 127_773
            let t = lo &* 16_807 &- hi &* 2_836 &+ 123
            seed = t > 0 ? t : t &+ Int32.max
            result[index] = UInt8(truncatingIfNeeded: seed)
        }
        return result
    }
}

enum UdpLibrary {
    static let marker: UInt8 = 0
    static let crcByteCount = 2
    static let maximumReassemblyLength = 20 * 1024 * 1024

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

    /// Validate the negotiated CRC and undo every negotiated encryption pass.
    static func cook(
        _ datagram: Data,
        config: UdpLibraryConnectionConfig
    ) throws -> Data {
        let bytes = Array(datagram)
        guard bytes.count >= 2 else { throw UdpLibraryError.truncated("datagram") }
        guard bytes[0] == marker else { throw UdpLibraryError.badMarker(bytes[0]) }
        guard config.isValid else {
            throw UdpLibraryError.unsupportedCRCWidth(config.crcBytes)
        }

        if isNonEncrypted(bytes[1]) {
            return datagram
        }

        guard config.crcBytes > 0 else {
            return try UdpLibraryCrypto.decrypt(datagram, config: config)
        }
        guard bytes.count > config.crcBytes else {
            throw UdpLibraryError.truncated("CRC")
        }
        let signed = Data(bytes.dropLast(config.crcBytes))
        let actualCRC = UInt32(truncatingIfNeeded: CRC32.checksum(signed, encryptCode: config.encryptCode))
        let wantCRC = readCRC(bytes, offset: bytes.count - config.crcBytes, width: config.crcBytes)
        let mask: UInt32 = config.crcBytes >= 4 ? 0xffff_ffff : (1 << UInt32(config.crcBytes * 8)) - 1
        guard wantCRC == (actualCRC & mask) else {
            if config.crcBytes == 2 {
                throw UdpLibraryError.crcMismatch(
                    expected: UInt16(truncatingIfNeeded: wantCRC),
                    actual: UInt16(truncatingIfNeeded: actualCRC)
                )
            }
            throw UdpLibraryError.crcMismatch32(
                expected: wantCRC,
                actual: actualCRC & mask,
                width: config.crcBytes
            )
        }

        return try UdpLibraryCrypto.decrypt(signed, config: config)
    }

    /// Backward-compatible decoder for callers without a full config.
    static func cook(
        _ datagram: Data,
        encryptCode: UInt32,
        userSuppliedCompression: Bool
    ) throws -> Data {
        let config = UdpLibraryConnectionConfig(
            encryptCode: encryptCode,
            crcBytes: crcByteCount,
            encryptMethod1: userSuppliedCompression ? 1 : 0,
            encryptMethod2: 0,
            maxRawPacketSize: 512
        )
        return try cook(datagram, config: config)
    }

    /// Parse a cooked packet into application payloads and transport events.
    /// Multi (3) and Group (25) containers are expanded recursively and
    /// fragments are reassembled immediately, matching the convenience path
    /// used by decoder tests.
    static func parse(
        _ cooked: Data,
        state: inout UdpLibraryReassemblyState
    ) -> [UdpLibraryPacket] {
        parse(cooked, state: &state, reassemble: true)
    }

    /// Live-session parse path. Reliable and fragment frames are returned
    /// unreassembled so `UdpLibraryIncomingReliableState` can order them first.
    static func parseTransport(_ cooked: Data) -> [UdpLibraryPacket] {
        var state = UdpLibraryReassemblyState()
        return parse(cooked, state: &state, reassemble: false)
    }

    /// Convenience overload for callers without a live connection.
    static func parse(_ cooked: Data) -> [UdpLibraryPacket] {
        var state = UdpLibraryReassemblyState()
        return parse(cooked, state: &state)
    }

    private static func parse(
        _ cooked: Data,
        state: inout UdpLibraryReassemblyState,
        reassemble: Bool
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
            return parseContainers(bytes, lengthSize: 1, offset: 2, state: &state, reassemble: reassemble)

        case 9...12: // Reliable1-4
            return parseReliable(bytes, state: &state, reassemble: reassemble)

        case 13...16: // Fragment1-4
            return parseFragment(bytes, state: &state, reassemble: reassemble)

        case 17...20: // Ack1-4
            guard bytes.count >= 4 else { return [] }
            return [.ack(type: bytes[1], reliableID: readBE16(bytes, offset: 2))]

        case 21...24: // AckAll1-4
            guard bytes.count >= 4 else { return [] }
            return [.ackAll(type: bytes[1], reliableID: readBE16(bytes, offset: 2))]

        case 25: // Group: variable-length application packets
            return parseContainers(bytes, lengthSize: 0, offset: 2, state: &state, reassemble: reassemble)

        default:
            return [.internalPacket(bytes[1])]
        }
    }

    /// Build a reliable frame exactly as `UdpConnection.PhysicalSend` does.
    static func encodeReliable(
        type: UInt8,
        reliableID: UInt16,
        config: UdpLibraryConnectionConfig,
        payload: Data
    ) -> Data {
        var body = payload
        if body.first == marker { body.insert(marker, at: 0) }
        return encodeReliableBody(
            type: type,
            reliableID: reliableID,
            config: config,
            body: body
        )
    }

    /// Backward-compatible helper for callers without a full config.
    static func encodeReliable(
        type: UInt8,
        reliableID: UInt16,
        encryptCode: UInt32,
        userSuppliedCompression: Bool,
        payload: Data
    ) -> Data {
        let config = UdpLibraryConnectionConfig(
            encryptCode: encryptCode,
            crcBytes: crcByteCount,
            encryptMethod1: userSuppliedCompression ? 1 : 0,
            encryptMethod2: 0,
            maxRawPacketSize: 512
        )
        return encodeReliable(
            type: type,
            reliableID: reliableID,
            config: config,
            payload: payload
        )
    }

    /// Encodes an already prepared logical body. This is used for fragments,
    /// whose four-byte total-length header must not receive a second escape.
    static func encodeReliableBody(
        type: UInt8,
        reliableID: UInt16,
        config: UdpLibraryConnectionConfig,
        body: Data
    ) -> Data {
        encodePhysical(
            cookedBody: encodeReliableCookedBody(type: type, reliableID: reliableID, body: body),
            config: config
        )
    }

    /// Reliable header only, before negotiated encryption and CRC. Sessions
    /// retain this form so the shared Multi buffer can coalesce it and so a
    /// retransmission can reapply the current wire configuration.
    static func encodeReliableCookedBody(
        type: UInt8,
        reliableID: UInt16,
        body: Data
    ) -> Data {
        var data = Data([marker, type])
        appendBE16(reliableID, to: &data)
        data.append(contentsOf: body)
        return data
    }

    static func encodeReliableBody(
        type: UInt8,
        reliableID: UInt16,
        encryptCode: UInt32,
        userSuppliedCompression: Bool,
        body: Data
    ) -> Data {
        let config = UdpLibraryConnectionConfig(
            encryptCode: encryptCode,
            crcBytes: crcByteCount,
            encryptMethod1: userSuppliedCompression ? 1 : 0,
            encryptMethod2: 0,
            maxRawPacketSize: 512
        )
        return encodeReliableBody(type: type, reliableID: reliableID, config: config, body: body)
    }

    /// Fragment1-4 reuse the four reliable channels. The first fragment's body
    /// includes the big-endian total logical length before its chunk.
    static func encodeFragment(
        type: UInt8,
        reliableID: UInt16,
        config: UdpLibraryConnectionConfig,
        body: Data
    ) -> Data {
        encodeReliableBody(type: type, reliableID: reliableID, config: config, body: body)
    }

    static func encodeFragment(
        type: UInt8,
        reliableID: UInt16,
        encryptCode: UInt32,
        userSuppliedCompression: Bool,
        body: Data
    ) -> Data {
        let config = UdpLibraryConnectionConfig(
            encryptCode: encryptCode,
            crcBytes: crcByteCount,
            encryptMethod1: userSuppliedCompression ? 1 : 0,
            encryptMethod2: 0,
            maxRawPacketSize: 512
        )
        return encodeFragment(type: type, reliableID: reliableID, config: config, body: body)
    }

    /// Cooked four-byte ACK body from `UdpReliableChannel`: marker, Ack type,
    /// big-endian reliable id. This is also the Multi subpacket representation.
    static func encodeAckBody(type: UInt8, reliableID: UInt16) -> Data {
        var data = Data([marker, type])
        appendBE16(reliableID, to: &data)
        return data
    }

    /// Applies every negotiated encryption pass and the negotiated CRC to an
    /// already cooked datagram.
    static func encodePhysical(
        cookedBody: Data,
        config: UdpLibraryConnectionConfig
    ) -> Data {
        guard let encrypted = UdpLibraryCrypto.encrypt(cookedBody, config: config) else {
            return cookedBody
        }
        var data = encrypted
        appendCRC(to: &data, config: config)
        return data
    }

    static func encodePhysical(
        cookedBody: Data,
        encryptCode: UInt32,
        userSuppliedCompression: Bool
    ) -> Data {
        let config = UdpLibraryConnectionConfig(
            encryptCode: encryptCode,
            crcBytes: crcByteCount,
            encryptMethod1: userSuppliedCompression ? 1 : 0,
            encryptMethod2: 0,
            maxRawPacketSize: 512
        )
        return encodePhysical(cookedBody: cookedBody, config: config)
    }

    static func encodeAck(
        type: UInt8,
        reliableID: UInt16,
        config: UdpLibraryConnectionConfig
    ) -> Data {
        encodePhysical(cookedBody: encodeAckBody(type: type, reliableID: reliableID), config: config)
    }

    static func encodeAck(
        type: UInt8,
        reliableID: UInt16,
        encryptCode: UInt32,
        userSuppliedCompression: Bool
    ) -> Data {
        let config = UdpLibraryConnectionConfig(
            encryptCode: encryptCode,
            crcBytes: crcByteCount,
            encryptMethod1: userSuppliedCompression ? 1 : 0,
            encryptMethod2: 0,
            maxRawPacketSize: 512
        )
        return encodeAck(type: type, reliableID: reliableID, config: config)
    }

    static func encodeKeepAlive(config: UdpLibraryConnectionConfig) -> Data {
        let cooked = Data([marker, UdpFrameType.keepAlive.rawValue])
        return encodePhysical(cookedBody: cooked, config: config)
    }

    static func encodeKeepAlive(
        encryptCode: UInt32,
        userSuppliedCompression: Bool
    ) -> Data {
        let config = UdpLibraryConnectionConfig(
            encryptCode: encryptCode,
            crcBytes: crcByteCount,
            encryptMethod1: userSuppliedCompression ? 1 : 0,
            encryptMethod2: 0,
            maxRawPacketSize: 512
        )
        return encodeKeepAlive(config: config)
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

    /// Wrap-safe ordering for 16-bit reliable stamps.
    static func reliableID(_ lhs: UInt16, isAheadOf rhs: UInt16) -> Bool {
        let delta = lhs &- rhs
        return delta != 0 && delta < 0x8000
    }

    // MARK: - Private

    private static func parseReliable(
        _ bytes: [UInt8],
        state: inout UdpLibraryReassemblyState,
        reassemble: Bool
    ) -> [UdpLibraryPacket] {
        guard bytes.count >= 4 else { return [] }
        let reliableID = readBE16(bytes, offset: 2)
        let body = Data(bytes.dropFirst(4))
        if !reassemble {
            guard state.fragment == nil else { return [] }
            return [.frame(type: bytes[1], reliableID: reliableID, body: body, isFragment: false)]
        }
        guard state.fragment == nil else { return [] } // FragmentExpected
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
        state: inout UdpLibraryReassemblyState,
        reassemble: Bool
    ) -> [UdpLibraryPacket] {
        guard bytes.count >= 4 else { return [] }
        let reliableID = readBE16(bytes, offset: 2)
        let body = Data(bytes.dropFirst(4))
        if !reassemble {
            return [.frame(type: bytes[1], reliableID: reliableID, body: body, isFragment: true)]
        }

        var chunk = body
        if state.fragment == nil {
            guard chunk.count >= 4 else { return [] }
            let length = readBE32(Array(chunk), offset: 0)
            guard length > 0, length <= UInt64(maximumReassemblyLength) else { return [] }
            state.targetLength = Int(length)
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

    private static func parseContainers(
        _ bytes: [UInt8],
        lengthSize: Int,
        offset: Int,
        state: inout UdpLibraryReassemblyState,
        reassemble: Bool
    ) -> [UdpLibraryPacket] {
        var result: [UdpLibraryPacket] = []
        var pointer = offset
        while pointer < bytes.count {
            let decoded = readLength(bytes, pointer: &pointer, lengthSize: lengthSize)
            guard let length = decoded else { break }
            guard pointer + length <= bytes.count else { break }
            if length > 0 {
                result.append(contentsOf: parse(
                    Data(bytes[pointer..<(pointer + length)]),
                    state: &state,
                    reassemble: reassemble
                ))
            }
            pointer += length
        }
        return result
    }

    private static func readLength(_ bytes: [UInt8], pointer: inout Int, lengthSize: Int) -> Int? {
        if lengthSize == 1 {
            guard pointer < bytes.count else { return nil }
            let value = Int(bytes[pointer]); pointer += 1
            return value
        }
        guard pointer < bytes.count else { return nil }
        if bytes[pointer] == 0xff {
            guard pointer + 3 <= bytes.count else { return nil }
            if bytes[pointer + 1] == 0xff && bytes[pointer + 2] == 0xff {
                guard pointer + 7 <= bytes.count else { return nil }
                let value = (Int(bytes[pointer + 3]) << 24) |
                    (Int(bytes[pointer + 4]) << 16) |
                    (Int(bytes[pointer + 5]) << 8) |
                    Int(bytes[pointer + 6])
                pointer += 7
                return value
            }
            let value = (Int(bytes[pointer + 1]) << 8) | Int(bytes[pointer + 2])
            pointer += 3
            return value
        }
        let value = Int(bytes[pointer]); pointer += 1
        return value
    }

    static func variableValueLength(_ bytes: [UInt8], offset: Int) -> Int {
        guard offset < bytes.count else { return 0 }
        if bytes[offset] != 0xff { return 1 }
        guard offset + 2 < bytes.count else { return 0 }
        if bytes[offset + 1] == 0xff && bytes[offset + 2] == 0xff { return 7 }
        return 3
    }

    static func readVariableValue(_ bytes: [UInt8], offset: Int) -> Int {
        let length = variableValueLength(bytes, offset: offset)
        switch length {
        case 1: return Int(bytes[offset])
        case 3: return (Int(bytes[offset + 1]) << 8) | Int(bytes[offset + 2])
        case 7:
            return (Int(bytes[offset + 3]) << 24) |
                (Int(bytes[offset + 4]) << 16) |
                (Int(bytes[offset + 5]) << 8) |
                Int(bytes[offset + 6])
        default: return 0
        }
    }

    static func readCRC(_ bytes: [UInt8], offset: Int, width: Int) -> UInt32 {
        switch width {
        case 1: return UInt32(bytes[offset])
        case 2: return (UInt32(bytes[offset]) << 8) | UInt32(bytes[offset + 1])
        case 3:
            return (UInt32(bytes[offset]) << 16) |
                (UInt32(bytes[offset + 1]) << 8) |
                UInt32(bytes[offset + 2])
        case 4: return readBE32(bytes, offset: offset)
        default: return 0
        }
    }

    private static func appendCRC(to data: inout Data, config: UdpLibraryConnectionConfig) {
        guard config.crcBytes > 0 else { return }
        let crc = CRC32.checksum(data, encryptCode: config.encryptCode)
        switch config.crcBytes {
        case 1:
            data.append(UInt8(truncatingIfNeeded: crc))
        case 2:
            appendBE16(UInt16(truncatingIfNeeded: crc), to: &data)
        case 3:
            data.append(UInt8(truncatingIfNeeded: crc >> 16))
            data.append(UInt8(truncatingIfNeeded: crc >> 8))
            data.append(UInt8(truncatingIfNeeded: crc))
        case 4:
            data.append(UInt8(truncatingIfNeeded: crc >> 24))
            data.append(UInt8(truncatingIfNeeded: crc >> 16))
            data.append(UInt8(truncatingIfNeeded: crc >> 8))
            data.append(UInt8(truncatingIfNeeded: crc))
        default:
            break
        }
    }

    static func appendBE16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }

    static func readBE16(_ bytes: [UInt8], offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    static func readBE32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24) |
            (UInt32(bytes[offset + 1]) << 16) |
            (UInt32(bytes[offset + 2]) << 8) |
            UInt32(bytes[offset + 3])
    }

    static func readLE32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        (UInt32(bytes[offset])) |
            (UInt32(bytes[offset + 1]) << 8) |
            (UInt32(bytes[offset + 2]) << 16) |
            (UInt32(bytes[offset + 3]) << 24)
    }

    static func writeLE32(_ value: UInt32, to data: inout Data, offset: Int) {
        data[offset] = UInt8(truncatingIfNeeded: value)
        data[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        data[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        data[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }

    /// Sanctuary's `ZLib.Decompress` consumes an RFC 1950 zlib stream: a
    /// two-byte CMF/FLG header, raw DEFLATE data, and a four-byte Adler-32
    /// trailer. Apple's `COMPRESSION_ZLIB` decoder implements raw RFC 1951
    /// DEFLATE, so the wrapper is stripped and the checksum verified here.
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
        guard cmf & 0x0f == 8,
              flg & 0x20 == 0,
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
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        return (b << 16) | a
    }

    /// Decompresses an RFC 1950 zlib stream and verifies its Adler-32 trailer.
    /// Also used by the native chunk reader for shipped `GCNK` archives.
    static func inflateZlib(_ source: Data) throws -> Data {
        let zlib = try splitZlibStream(source)
        #if canImport(Compression)
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
