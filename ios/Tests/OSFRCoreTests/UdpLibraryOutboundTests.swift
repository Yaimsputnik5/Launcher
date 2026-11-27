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
}
