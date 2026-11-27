import Foundation
import XCTest
@testable import OSFRCore

/// Wire-parity tests for behavior that used to be rejected or silently
/// misframed: negotiated CRC widths, both encryption passes, Group coalescing,
/// the shared Multi buffer, and ordered fragment reassembly after wrap.
final class UdpLibraryParityTests: XCTestCase {
    func testAllCRCWidthsRoundTrip() throws {
        for width in 0...4 {
            let config = UdpLibraryConnectionConfig(
                encryptCode: 0x0102_0304,
                crcBytes: width,
                encryptMethod1: 0,
                encryptMethod2: 0,
                maxRawPacketSize: 512
            )
            let cooked = Data([0, 9, 0, 7, 0xAA, 0xBB])
            let wire = UdpLibrary.encodePhysical(cookedBody: cooked, config: config)
            XCTAssertEqual(try UdpLibrary.cook(wire, config: config), cooked, "CRC width \(width)")
        }
    }

    func testCRCWidthMismatchIsReported() {
        let config = UdpLibraryConnectionConfig(
            encryptCode: 0,
            crcBytes: 3,
            encryptMethod1: 0,
            encryptMethod2: 0,
            maxRawPacketSize: 512
        )
        var wire = UdpLibrary.encodePhysical(cookedBody: Data([0, 9, 0, 1, 0xAA]), config: config)
        wire[wire.count - 1] ^= 1
        XCTAssertThrowsError(try UdpLibrary.cook(wire, config: config)) { error in
            guard case .crcMismatch32(_, _, let width) = error as? UdpLibraryError else {
                return XCTFail("expected CRC-3 mismatch, got \(String(describing: error))")
            }
            XCTAssertEqual(width, 3)
        }
    }

    func testXorPassMatchesSanctuaryNativeEndianChaining() throws {
        let config = UdpLibraryConnectionConfig(
            encryptCode: 0x0102_0304,
            crcBytes: 2,
            encryptMethod1: UInt8(UdpLibraryEncryptMethod.xor.rawValue),
            encryptMethod2: 0,
            maxRawPacketSize: 512
        )
        let body = bytes(fromHex: "00112233445566778899aabbccddeeff01")
        let cooked = Data([0, 9, 0, 7]) + body
        let wire = UdpLibrary.encodePhysical(cookedBody: cooked, config: config)
        // C# encrypts everything after [0, type], including the reliable id.
        XCTAssertEqual(
            Data(wire.dropFirst(2).dropLast(2)),
            bytes(fromHex: "04040210263746454040cedceafb02010415eb")
        )
        XCTAssertEqual(try UdpLibrary.cook(wire, config: config), cooked)
    }

    func testXorBufferPassMatchesSanctuaryRandomBuffer() throws {
        let config = UdpLibraryConnectionConfig(
            encryptCode: 0x0102_0304,
            crcBytes: 2,
            encryptMethod1: UInt8(UdpLibraryEncryptMethod.xorBuffer.rawValue),
            encryptMethod2: 0,
            maxRawPacketSize: 512
        )
        let body = bytes(fromHex: "00112233445566778899aabbccddeeff01")
        let cooked = Data([0, 9, 0, 7]) + body
        let wire = UdpLibrary.encodePhysical(cookedBody: cooked, config: config)
        XCTAssertEqual(
            Data(wire.dropFirst(2).dropLast(2)),
            bytes(fromHex: "9fb47439cf6c0c925bc93d20cfd9c765fd4586")
        )
        XCTAssertEqual(try UdpLibrary.cook(wire, config: config), cooked)
    }

    func testBothEncryptPassesAreAppliedInOrder() throws {
        let config = UdpLibraryConnectionConfig(
            encryptCode: 0x0102_0304,
            crcBytes: 2,
            encryptMethod1: UInt8(UdpLibraryEncryptMethod.userSupplied.rawValue),
            encryptMethod2: UInt8(UdpLibraryEncryptMethod.xor.rawValue),
            maxRawPacketSize: 512
        )
        let cooked = Data([0, 9, 0, 7, 0xAA, 0xBB, 0xCC, 0xDD])
        let wire = UdpLibrary.encodePhysical(cookedBody: cooked, config: config)
        XCTAssertEqual(try UdpLibrary.cook(wire, config: config), cooked)
    }

    func testCoalescerWrapsMultiplePacketsAndUnwrapsOne() {
        var coalescer = UdpLibraryOutboundCoalescer(maxReliablePayloadBytes: 64)
        coalescer.enqueue(Data([0xAA]))
        coalescer.enqueue(Data([0xBB, 0xCC]))
        XCTAssertEqual(
            coalescer.drain(maxBytes: 64, maxPackets: 1),
            [Data([0, 25, 1, 0xAA, 2, 0xBB, 0xCC])]
        )
        XCTAssertTrue(coalescer.isEmpty)

        var single = UdpLibraryOutboundCoalescer(maxReliablePayloadBytes: 64)
        single.enqueue(Data([0xAA]))
        XCTAssertEqual(single.drain(maxBytes: 64, maxPackets: 1), [Data([0xAA])])

        var oversized = UdpLibraryOutboundCoalescer(maxReliablePayloadBytes: 16)
        oversized.enqueue(Data(repeating: 0xAA, count: 64))
        XCTAssertEqual(oversized.coalesceCount, 0)
        XCTAssertEqual(oversized.drain(maxBytes: 64, maxPackets: 1), [Data(repeating: 0xAA, count: 64)])
    }

    func testSharedMultiBufferCarriesAcksAndCookedPackets() throws {
        let config = UdpLibraryConnectionConfig(
            encryptCode: 0,
            crcBytes: 2,
            encryptMethod1: 0,
            encryptMethod2: 0,
            maxRawPacketSize: 512
        )
        var buffer = UdpLibraryBufferedAcks()
        buffer.enqueue(type: 17, reliableID: 1, isAckAll: false)
        // A different channel so the AckAll overwrites its own channel's
        // buffered pointer instead of replacing the channel-0 selective ack.
        buffer.enqueue(type: 22, reliableID: 7, isAckAll: true)
        guard let frame = buffer.flush(config: config) else {
            return XCTFail("expected a flushed Multi datagram")
        }
        XCTAssertEqual(Array(frame.prefix(2)), [0, 3])
        let cooked = try UdpLibrary.cook(frame, config: config)
        XCTAssertEqual(UdpLibrary.parse(cooked), [
            .ack(type: 17, reliableID: 1),
            .ackAll(type: 22, reliableID: 7)
        ])
        XCTAssertEqual(buffer.count, 0, "flush must clear every channel's buffered ack pointer")
    }

    func testSharedMultiBufferMixesAckAndApplicationData() throws {
        let config = UdpLibraryConnectionConfig(
            encryptCode: 0,
            crcBytes: 2,
            encryptMethod1: 0,
            encryptMethod2: 0,
            maxRawPacketSize: 512
        )
        var buffer = UdpLibraryBufferedAcks()
        buffer.enqueue(type: 17, reliableID: 3, isAckAll: false)
        XCTAssertEqual(
            buffer.enqueue(
                cooked: Data([0, 9, 0, 4, 0xA9, 0xB7]),
                config: config
            ),
            .buffered
        )
        guard let frame = buffer.flush(config: config) else {
            return XCTFail("expected a flushed Multi datagram")
        }
        let cooked = try UdpLibrary.cook(frame, config: config)
        XCTAssertEqual(UdpLibrary.parse(cooked), [
            .ack(type: 17, reliableID: 3),
            .reliable(type: 9, reliableID: 4, body: Data([0xA9, 0xB7]), applications: [Data([0xA9, 0xB7])])
        ])
    }

    func testSingleBufferedPacketIsSentWithoutMultiHeader() throws {
        let config = UdpLibraryConnectionConfig(
            encryptCode: 0,
            crcBytes: 2,
            encryptMethod1: 0,
            encryptMethod2: 0,
            maxRawPacketSize: 512
        )
        var buffer = UdpLibraryBufferedAcks()
        buffer.enqueue(type: 17, reliableID: 9, isAckAll: false)
        guard let frame = buffer.flush(config: config) else {
            return XCTFail("expected a flushed ACK")
        }
        XCTAssertEqual(Array(frame.prefix(4)), [0, 17, 0, 9])
        XCTAssertEqual(
            try UdpLibrary.cook(frame, config: config),
            Data([0, 17, 0, 9])
        )
    }

    func testFragmentsAreOrderedPerChannelBeforeReassembly() {
        let config = UdpLibraryConnectionConfig(
            encryptCode: 0,
            crcBytes: 2,
            encryptMethod1: 0,
            encryptMethod2: 0,
            maxRawPacketSize: 512
        )
        var incoming = UdpLibraryIncomingReliableState()
        let first = bytes(fromHex: "00000004aabb")
        let second = bytes(fromHex: "ccdd")
        let firstFrame = UdpLibrary.encodeFragment(
            type: 13, reliableID: 0, config: config, body: first
        )
        let secondFrame = UdpLibrary.encodeFragment(
            type: 13, reliableID: 1, config: config, body: second
        )

        let early = deliver(secondFrame, config: config, into: &incoming)
        XCTAssertEqual(early.applications, [])
        XCTAssertEqual(early.type, 17)
        let complete = deliver(firstFrame, config: config, into: &incoming)
        XCTAssertEqual(complete.applications, [bytes(fromHex: "aabbccdd")])
        XCTAssertEqual(complete.type, 21)
        XCTAssertEqual(complete.reliableID, 1)

        // A different channel has its own ordering and assembly state.
        let otherFirst = UdpLibrary.encodeFragment(
            type: 14, reliableID: 0, config: config, body: bytes(fromHex: "00000002ee")
        )
        let otherSecond = UdpLibrary.encodeFragment(
            type: 14, reliableID: 1, config: config, body: bytes(fromHex: "ff")
        )
        XCTAssertEqual(deliver(otherFirst, config: config, into: &incoming).applications, [])
        XCTAssertEqual(deliver(otherSecond, config: config, into: &incoming).applications, [bytes(fromHex: "eeff")])
    }

    func testIncomingStampReconstructionCrosses65536() throws {
        let config = UdpLibraryConnectionConfig(
            encryptCode: 0,
            crcBytes: 2,
            encryptMethod1: 0,
            encryptMethod2: 0,
            maxRawPacketSize: 512
        )
        var incoming = UdpLibraryIncomingReliableState()
        // A fresh connection reconstructs stamp 0xFFFF as id -1 (the previous
        // wrap), so C# cumulatively acknowledges it without delivering it.
        let beforeWrap = UdpLibrary.encodeReliable(
            type: 9, reliableID: 0xFFFF, config: config, payload: Data([0xAA])
        )
        let duplicate = deliver(beforeWrap, config: config, into: &incoming)
        XCTAssertEqual(duplicate.applications, [])
        XCTAssertTrue(duplicate.wasDuplicate)
        XCTAssertEqual(duplicate.reliableID, 0xFFFF)

        let afterWrap = UdpLibrary.encodeReliable(
            type: 9, reliableID: 0, config: config, payload: Data([0xBB])
        )
        let wrapped = deliver(afterWrap, config: config, into: &incoming)
        XCTAssertEqual(wrapped.applications, [Data([0xBB])], "stamp 0 must follow 0xFFFF")
        XCTAssertEqual(wrapped.reliableID, 0)

        let next = UdpLibrary.encodeReliable(
            type: 9, reliableID: 1, config: config, payload: Data([0xCC])
        )
        XCTAssertEqual(deliver(next, config: config, into: &incoming).applications, [Data([0xCC])])
    }

    func testConfirmAcceptsOptionalVersionAndIgnoresTrailingBytes() throws {
        var bytes = Data([0, 2])
        bytes.append(contentsOf: [0, 0, 0, 9]) // connect code
        bytes.append(contentsOf: [1, 2, 3, 4]) // encrypt code
        bytes.append(contentsOf: [2, 1, 0])     // CRC-2, methods 1/0
        bytes.append(contentsOf: [0, 0, 2, 0]) // max raw 512
        XCTAssertNoThrow(try GatewayConfirmPacket(data: bytes))

        bytes.append(contentsOf: [0, 0, 0, 3, 0xAA, 0xBB])
        let withTrailing = try GatewayConfirmPacket(data: bytes)
        XCTAssertEqual(withTrailing.protocolVersion, 3)

        XCTAssertThrowsError(try GatewayConfirmPacket(data: Data(bytes.prefix(19)))) { error in
            guard case .frameTooShort = error as? GatewayProtocolError else {
                return XCTFail("expected frameTooShort, got \(String(describing: error))")
            }
        }
    }

    // MARK: - Helpers

    private func deliver(
        _ frame: Data,
        config: UdpLibraryConnectionConfig,
        into state: inout UdpLibraryIncomingReliableState
    ) -> UdpLibraryIncomingAck {
        let cooked = try! UdpLibrary.cook(frame, config: config)
        let packets = UdpLibrary.parseTransport(cooked)
        XCTAssertEqual(packets.count, 1)
        guard case .frame(let type, let id, let body, let isFragment) = packets[0] else {
            fatalError("expected a transport frame, got \(packets[0])")
        }
        return state.receiveFrame(
            type: type,
            reliableID: id,
            body: body,
            isFragment: isFragment
        )!
    }

    private func bytes(fromHex hex: String) -> Data {
        var result = Data()
        var cursor = hex.startIndex
        while cursor < hex.endIndex {
            let next = hex.index(cursor, offsetBy: 2)
            result.append(UInt8(hex[cursor..<next], radix: 16)!)
            cursor = next
        }
        return result
    }
}
