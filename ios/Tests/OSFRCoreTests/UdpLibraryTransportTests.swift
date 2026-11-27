import Foundation
import XCTest
@testable import OSFRCore

/// Regression tests for the UdpLibrary receive path used by both Sanctuary
/// transports. Live probes showed server replies arriving as Multi containers,
/// Group containers, reliable fragments, and AckAll packets; before this port
/// those datagrams were silently ignored and surfaced to the user as timeouts.
final class UdpLibraryTransportTests: XCTestCase {
    func testMultiContainerIsExpandedAndApplicationPayloadRecovered() throws {
        let application = Data([0xA9, 0xB7, 0xB9, 0x43])
        var subpacket = Data([0x00, 0x09, 0x00, 0x07])
        subpacket.append(application)
        XCTAssertEqual(subpacket.count, 8)

        // 0x00 Multi, user-supplied raw flag 0, 8-byte subpacket length.
        var signed = Data([0x00, 0x03, 0x00, UInt8(subpacket.count)])
        signed.append(subpacket)
        let datagram = withCRC(signed, encryptCode: 0x1122_3344)

        let cooked = try UdpLibrary.cook(
            datagram,
            encryptCode: 0x1122_3344,
            userSuppliedCompression: true
        )
        XCTAssertEqual(Array(cooked.prefix(3)), [0x00, 0x03, 0x08])

        var state = UdpLibraryReassemblyState()
        let packets = UdpLibrary.parse(cooked, state: &state)
        XCTAssertEqual(packets.count, 1)
        guard case .reliable(let type, let reliableID, let body, let applications) = packets[0] else {
            return XCTFail("expected a reliable packet, got \(packets[0])")
        }
        XCTAssertEqual(type, UdpFrameType.reliable1.rawValue)
        XCTAssertEqual(reliableID, 7)
        XCTAssertEqual(body, subpacket.dropFirst(4))
        XCTAssertEqual(applications, [application])
        XCTAssertEqual(UdpLibrary.ackType(for: type), 17)
    }

    func testZeroEscapeRoutesPayloadWithLeadingZero() {
        let packets = UdpLibrary.parse(Data([0x00, 0x00, 0x01, 0x02]))
        XCTAssertEqual(packets, [.application(Data([0x00, 0x01, 0x02]))])
    }

    func testGroupContainerExpandsVariableLengthPayloads() {
        // Group (25) with a one-byte length followed by two app packets.
        let cooked = Data([
            0x00, 0x19,
            0x02, 0xA9, 0xB7,
            0x03, 0x01, 0x02, 0x03
        ])
        let packets = UdpLibrary.parse(cooked)
        XCTAssertEqual(packets, [
            .application(Data([0xA9, 0xB7])),
            .application(Data([0x01, 0x02, 0x03]))
        ])
    }

    func testAckAndAckAllIncludeReliableID() {
        let ack = UdpLibrary.parse(Data([0x00, 0x11, 0x12, 0x34]))
        XCTAssertEqual(ack, [.ack(type: 17, reliableID: 0x1234)])

        let ackAll = UdpLibrary.parse(Data([0x00, 0x15, 0x00, 0x07]))
        XCTAssertEqual(ackAll, [.ackAll(type: 21, reliableID: 7)])
    }

    func testEncodedAckIncludesNegotiatedUserSuppliedFlag() throws {
        let compressed = UdpLibrary.encodeAck(
            type: 17,
            reliableID: 0x1234,
            encryptCode: 0,
            userSuppliedCompression: true
        )
        XCTAssertEqual(Array(compressed.prefix(5)), [0x00, 0x11, 0x00, 0x12, 0x34])
        XCTAssertEqual(
            try UdpLibrary.cook(compressed, encryptCode: 0, userSuppliedCompression: true),
            Data([0x00, 0x11, 0x12, 0x34])
        )

        let raw = UdpLibrary.encodeAck(
            type: 17,
            reliableID: 7,
            encryptCode: 0,
            userSuppliedCompression: false
        )
        XCTAssertEqual(Array(raw.prefix(4)), [0x00, 0x11, 0x00, 0x07])
    }

    func testReliableFragmentsAreReassembledBeforeRouting() throws {
        let application = Data([0xA9, 0xB7, 0xB9, 0x43])
        let total = UInt32(application.count)
        let firstChunk = application.prefix(2)
        let secondChunk = application.dropFirst(2)

        // Sanctuary writes the total fragment length big-endian.
        var firstBody = Data([
            UInt8(truncatingIfNeeded: total >> 24),
            UInt8(truncatingIfNeeded: total >> 16),
            UInt8(truncatingIfNeeded: total >> 8),
            UInt8(truncatingIfNeeded: total)
        ])
        firstBody.append(firstChunk)
        let first = withCRC(Data([0x00, 0x0D, 0x00, 0x01]) + firstBody, encryptCode: 0)
        let second = withCRC(
            Data([0x00, 0x0D, 0x00, 0x02]) + secondChunk,
            encryptCode: 0
        )

        var state = UdpLibraryReassemblyState()
        let firstPackets = UdpLibrary.parse(
            try UdpLibrary.cook(first, encryptCode: 0, userSuppliedCompression: false),
            state: &state
        )
        XCTAssertTrue(firstPackets.isEmpty, "fragments must not be delivered early")

        let secondPackets = UdpLibrary.parse(
            try UdpLibrary.cook(second, encryptCode: 0, userSuppliedCompression: false),
            state: &state
        )
        XCTAssertEqual(secondPackets.count, 1)
        guard case .reliable(let type, let reliableID, let body, let applications) = secondPackets[0] else {
            return XCTFail("expected a reassembled reliable packet, got \(secondPackets[0])")
        }
        XCTAssertEqual(type, 0x0D)
        XCTAssertEqual(reliableID, 2)
        XCTAssertEqual(body, application)
        XCTAssertEqual(applications, [application])
        XCTAssertNil(state.fragment)
    }

    func testNonEncryptedPacketsSkipCRCAndBadCRCIsRejected() throws {
        let connect = Data([0x00, 0x01, 0, 0, 0, 3])
        XCTAssertEqual(
            try UdpLibrary.cook(connect, encryptCode: 0xFFFF_FFFF, userSuppliedCompression: true),
            connect
        )

        let signed = withCRC(Data([0x00, 0x09, 0x00, 0x01, 0xA9]), encryptCode: 0x0102_0304)
        var corrupted = signed
        corrupted[corrupted.count - 1] ^= 1
        XCTAssertThrowsError(
            try UdpLibrary.cook(corrupted, encryptCode: 0x0102_0304, userSuppliedCompression: false)
        ) { error in
            guard case .crcMismatch = error as? UdpLibraryError else {
                return XCTFail("expected CRC mismatch, got \(String(describing: error))")
            }
        }
    }

    // MARK: - Helpers

    private func withCRC(_ data: Data, encryptCode: UInt32) -> Data {
        var result = data
        let crc = UInt16(truncatingIfNeeded: CRC32.checksum(result, encryptCode: encryptCode))
        result.append(UInt8(truncatingIfNeeded: crc >> 8))
        result.append(UInt8(truncatingIfNeeded: crc))
        return result
    }
}
