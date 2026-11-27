import Foundation
import XCTest
@testable import OSFRCore

/// Tests the send-side UdpLibrary state against the constants and formulas in
/// Sanctuary's `Internal/UdpReliableChannel.cs`. No sockets or server are used.
final class UdpLibraryOutboundTests: XCTestCase {
    private func config(
        crcBytes: Int = 2,
        method1: UInt8 = 0,
        maxRaw: Int = 512
    ) -> UdpLibraryConnectionConfig {
        UdpLibraryConnectionConfig(
            encryptCode: 0,
            crcBytes: crcBytes,
            encryptMethod1: method1,
            encryptMethod2: 0,
            maxRawPacketSize: maxRaw
        )
    }

    func testNegotiatedConfigSizesReliablePayloadFromPeerLimit() {
        XCTAssertEqual(config().maxReliablePayloadBytes, 506)
        XCTAssertEqual(config(method1: 1).maxReliablePayloadBytes, 505)
        XCTAssertEqual(config(crcBytes: 4).maxReliablePayloadBytes, 504)
        XCTAssertTrue(config(method1: 1).userSuppliedCompression)
    }

    func testFirstAckSamplesRTTAndSetsResendDelay() {
        var state = UdpLibraryOutgoingReliableState(config: config())
        state.noteSent(stamp: 0, channel: 0, length: 10, now: 0)
        state.acknowledge(type: 17, stamp: 0, now: 100)

        // AveragePingTime: (800 * 3 + 100) / 4 = 625.
        // Resend delay: min(8000, 625 * 125 / 100 + 300) = 1081.
        XCTAssertEqual(state.giveTime(now: 100).delay, 1_081)
        XCTAssertEqual(state.outstandingCount, 0)
    }

    func testAckOfResentPacketDoesNotReplaceRTT() {
        var state = UdpLibraryOutgoingReliableState(config: config())
        state.noteSent(stamp: 0, channel: 0, length: 10, now: 0)
        let resend = state.giveTime(now: 1_301)
        XCTAssertEqual(resend.resends.map(\.id), [0])
        state.acknowledge(type: 17, stamp: 0, now: 1_401)

        XCTAssertEqual(state.giveTime(now: 1_401).delay, 1_300)
    }

    func testAckAllOverAlreadyAckedRangeSlowsResendsOnce() {
        var state = UdpLibraryOutgoingReliableState(config: config())
        state.noteSent(stamp: 0, channel: 0, length: 10, now: 0)
        state.noteSent(stamp: 1, channel: 0, length: 10, now: 0)
        state.acknowledge(type: 17, stamp: 0, now: 100)
        state.acknowledge(type: 17, stamp: 1, now: 100)
        state.acknowledgeAll(type: 21, stamp: 1, now: 200)

        // Two first-send ACKs move 800 -> 625 -> 493; the cumulative-ACK
        // penalty adds 400. Delay: min(8000, 893 * 125 / 100 + 300) = 1416.
        XCTAssertEqual(state.giveTime(now: 200).delay, 1_416)
    }

    func testAckOnWrongChannelIsIgnored() {
        var state = UdpLibraryOutgoingReliableState(config: config())
        state.noteSent(stamp: 0, channel: 0, length: 10, now: 0)
        state.acknowledge(type: 18, stamp: 0, now: 100)
        XCTAssertEqual(state.outstandingCount, 1)
        state.acknowledge(type: 17, stamp: 0, now: 100)
        XCTAssertEqual(state.outstandingCount, 0)
    }

    func testAckAllFreesPrefixAndKeepsLaterPackets() {
        var state = UdpLibraryOutgoingReliableState(config: config())
        for stamp in UInt16(0)...2 {
            state.noteSent(stamp: stamp, channel: 0, length: 10, now: 0)
        }
        state.acknowledgeAll(type: 21, stamp: 1, now: 100)
        XCTAssertEqual(state.pendingStamps, [2])
        XCTAssertEqual(state.outstandingBytes, 10)
    }

    func testOldestUnacknowledgedTimeoutIsReported() {
        var state = UdpLibraryOutgoingReliableState(config: config())
        state.noteSent(stamp: 0, channel: 0, length: 10, now: 0)
        XCTAssertTrue(state.giveTime(now: 1_301).timedOut == false)
        XCTAssertTrue(state.giveTime(now: 131_302).timedOut)
    }

    func testWrapAroundKeepsFullIDDistinct() {
        var state = UdpLibraryOutgoingReliableState(config: config())
        state.noteSent(stamp: 0xffff, channel: 0, length: 10, now: 0)
        state.noteSent(stamp: 0, channel: 0, length: 10, now: 1)
        XCTAssertEqual(state.pendingStamps.count, 2)
        state.acknowledge(type: 17, stamp: 0xffff, now: 10)
        XCTAssertEqual(state.pendingStamps, [0])
    }

    func testGiveTimeReturnsRemainingDelayForRecentlySentFrame() {
        var state = UdpLibraryOutgoingReliableState(config: config())
        state.noteSent(stamp: 0, channel: 0, length: 10, now: 0)
        let tick = state.giveTime(now: 100)
        XCTAssertTrue(tick.resends.isEmpty)
        XCTAssertEqual(tick.delay, 1_200)
    }

    func testFragmenterKeepsPayloadAtNegotiatedLimitWhole() {
        let payload = Data(repeating: 0x41, count: 506)
        let fragments = UdpLibraryFragmenter.split(
            applicationPayload: payload,
            maxPayloadBytes: 506
        )
        XCTAssertEqual(fragments.count, 1)
        XCTAssertEqual(fragments[0].type, 9)
        XCTAssertEqual(fragments[0].body, payload)
        XCTAssertEqual(fragments[0].outstandingBytes, 506)
    }

    func testFragmenterReservesFourBytesInFirstFragment() {
        let payload = Data(repeating: 0x42, count: 700)
        let fragments = UdpLibraryFragmenter.split(
            applicationPayload: payload,
            maxPayloadBytes: 506
        )
        XCTAssertEqual(fragments.count, 2)
        XCTAssertEqual(fragments[0].type, 13)
        XCTAssertEqual(fragments[0].body.count, 506)
        XCTAssertEqual(Array(fragments[0].body.prefix(4)), [0, 0, 0x02, 0xbc])
        XCTAssertEqual(fragments[0].outstandingBytes, 502)
        XCTAssertEqual(fragments[1].body.count, 198)
        XCTAssertEqual(fragments[1].outstandingBytes, 198)
        XCTAssertEqual(fragments.map(\.outstandingBytes).reduce(0, +), 700)
    }

    func testFragmenterEscapesLeadingZeroOnce() {
        let payload = Data([0, 1, 2])
        let fragments = UdpLibraryFragmenter.split(
            applicationPayload: payload,
            maxPayloadBytes: 506
        )
        XCTAssertEqual(fragments.count, 1)
        XCTAssertEqual(Array(fragments[0].body.prefix(3)), [0, 0, 1])
    }

    func testEncodedFragmentsReassembleThroughSharedParser() throws {
        let payload = Data((0..<700).map { UInt8(truncatingIfNeeded: $0) })
        let fragments = UdpLibraryFragmenter.split(
            applicationPayload: payload,
            maxPayloadBytes: 506
        )
        XCTAssertEqual(fragments.count, 2)

        var state = UdpLibraryReassemblyState()
        var delivered: UdpLibraryPacket?
        for (index, fragment) in fragments.enumerated() {
            let wire = UdpLibrary.encodeFragment(
                type: fragment.type,
                reliableID: UInt16(index),
                encryptCode: 0,
                userSuppliedCompression: false,
                body: fragment.body
            )
            let cooked = try UdpLibrary.cook(
                wire,
                encryptCode: 0,
                userSuppliedCompression: false
            )
            for packet in UdpLibrary.parse(cooked, state: &state) {
                if case .reliable = packet { delivered = packet }
            }
        }

        guard case .reliable(_, _, let body, _) = delivered else {
            return XCTFail("expected reassembled reliable packet")
        }
        var expected = payload
        if expected.first == UdpLibrary.marker { expected.insert(UdpLibrary.marker, at: 0) }
        XCTAssertEqual(body, expected)
    }

    func testBufferedAckReplacesEarliestSelectiveAckWithAckAll() throws {
        var buffer = UdpLibraryBufferedAcks()
        buffer.enqueue(type: 17, reliableID: 3, isAckAll: false)
        buffer.enqueue(type: 17, reliableID: 5, isAckAll: false)
        buffer.enqueue(type: 21, reliableID: 7, isAckAll: true)
        XCTAssertEqual(buffer.cookedLength, 2 + 2 * 5)

        let wire = try XCTUnwrap(buffer.flush(encryptCode: 0, userSuppliedCompression: false))
        XCTAssertEqual(buffer.count, 0)
        let cooked = try UdpLibrary.cook(
            wire,
            encryptCode: 0,
            userSuppliedCompression: false
        )
        let packets = UdpLibrary.parse(cooked)
        XCTAssertEqual(packets.count, 2)
        guard case .ackAll(let firstType, let firstID) = packets[0] else {
            return XCTFail("expected AckAll first")
        }
        guard case .ack(let secondType, let secondID) = packets[1] else {
            return XCTFail("expected selective ACK second")
        }
        XCTAssertEqual(firstType, 21)
        XCTAssertEqual(firstID, 7)
        XCTAssertEqual(secondType, 17)
        XCTAssertEqual(secondID, 5)
    }

    func testBufferedAckSingleEntryFlushesAsStandaloneFrame() throws {
        var buffer = UdpLibraryBufferedAcks()
        buffer.enqueue(type: 18, reliableID: 9, isAckAll: false)
        let wire = try XCTUnwrap(buffer.flush(encryptCode: 0, userSuppliedCompression: true))
        let cooked = try UdpLibrary.cook(
            wire,
            encryptCode: 0,
            userSuppliedCompression: true
        )
        XCTAssertEqual(Array(cooked), [0, 18, 0, 9])
    }
}
