import Foundation
import XCTest
@testable import OSFRCore

/// Exact outbound layouts from Sanctuary's C# packet serializers. These tests
/// intentionally compare against literal bytes instead of rebuilding the
/// expected value with the same writer under test.
final class GatewayOutboundTests: XCTestCase {
    func testMovementPositionJumpAndCameraUseSanctuaryByteLayouts() throws {
        let guid: UInt64 = 0x0102_0304_0506_0708
        let position = GatewayVector3(x: 1, y: 2, z: 3)
        let rotation = GatewayVector3(x: 0, y: 0.5, z: -0.25)

        let movement = WorldPositionUpdate(
            guid: guid,
            position: position,
            rotation: rotation,
            state: 2,
            teleportSequence: 7
        )
        XCTAssertEqual(
            movement.encoded(),
            bytes("""
            7d 00 08 07 06 05 04 03 02 01
            00 00 80 3f 00 00 00 40 00 00 40 40
            00 00 00 00 00 00 00 3f 00 00 80 be
            02 07
            """)
        )
        XCTAssertEqual(try GatewayWorldCodec.decodeAny(movement.encoded()), .positionUpdate(movement))

        let jump = GatewayJumpUpdate(
            guid: guid,
            position: position,
            rotation: rotation,
            state: 2,
            teleportSequence: 7,
            verticalVelocity: 6
        )
        XCTAssertEqual(
            jump.encoded(),
            bytes("""
            a4 00 08 07 06 05 04 03 02 01
            00 00 80 3f 00 00 00 40 00 00 40 40
            00 00 00 00 00 00 00 3f 00 00 80 be
            02 07 00 00 c0 40
            """)
        )

        let camera = GatewayCameraUpdate(position: position, rotation: rotation)
        XCTAssertEqual(
            camera.encoded(),
            bytes("""
            7e 00 00 00 80 3f 00 00 00 40 00 00 40 40
            00 00 00 00 00 00 00 3f 00 00 80 be
            """)
        )
    }

    func testGameTimeSyncRequestUsesFifteenByteC2SLayout() throws {
        let sync = GatewayGameTimeSync(
            time: Int64(bitPattern: 0x0102_0304_0506_0708),
            serverRate: 8,
            useClientTime: false
        )
        let expected = bytes("34 00 08 07 06 05 04 03 02 01 08 00 00 00 00")
        XCTAssertEqual(sync.encoded(), expected)
        XCTAssertEqual(try GatewayGameTimeSync(data: expected), sync)
    }

    func testChatSendUsesExactNameDataAndConditionalAreaNameLayout() throws {
        let chat = GatewayChatMessage(
            channel: .worldSay,
            fromGUID: 0x1122_3344_5566_7788,
            toGUID: 0,
            fromName: GatewayName(
                firstNameID: 1,
                lastNamePrefixID: 2,
                lastNameSuffixID: 3,
                firstName: "Ada",
                lastName: "Lovelace"
            ),
            toName: GatewayName(
                firstNameID: 0,
                lastNamePrefixID: 0,
                lastNameSuffixID: 0,
                firstName: "",
                lastName: ""
            ),
            message: "hi",
            position: GatewayVector4(x: 1, y: 2, z: 3, w: 4),
            guildGUID: 0,
            languageID: 7
        )
        let expected = bytes("""
        0f 00 01 00 00 00 88 77 66 55 44 33 22 11
        00 00 00 00 00 00 00 00
        01 00 00 00 02 00 00 00 03 00 00 00
        03 00 00 00 41 64 61
        08 00 00 00 4c 6f 76 65 6c 61 63 65
        00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
        00 00 00 00
        02 00 00 00 68 69
        00 00 80 3f 00 00 00 40 00 00 40 40 00 00 80 40
        00 00 00 00 00 00 00 00 07 00 00 00
        """)
        XCTAssertEqual(expected.count, 107)
        XCTAssertEqual(chat.encoded(), expected)
        XCTAssertEqual(try GatewayChatMessage(data: expected), chat)

        var areaChat = chat
        areaChat.channel = .worldArea
        areaChat.areaNameID = 11
        let areaData = areaChat.encoded()
        XCTAssertEqual(areaData.count, expected.count + 4)
        XCTAssertEqual(Array(areaData.suffix(4)), [0x0b, 0x00, 0x00, 0x00])
        XCTAssertEqual(try GatewayChatMessage(data: areaData), areaChat)
        XCTAssertThrowsError(try GatewayChatMessage(data: Data(areaData.dropLast(4))))
    }

    func testInitialGatewayPacketsUseCorrectOuterTunnels() throws {
        var localePayload = PacketWriter()
        GatewayWire.appendInt16(88, to: &localePayload.data)
        localePayload.writeString("en_US")
        let locale = GatewayPacketCodec.encode(
            GatewayTunneledWorldPacket(reliable: true, payload: localePayload.data)
        )
        XCTAssertEqual(
            locale,
            bytes("06 00 01 0b 00 00 00 58 00 05 00 00 00 65 6e 5f 55 53")
        )

        var initializationPayload = PacketWriter()
        GatewayWire.appendInt16(169, to: &initializationPayload.data)
        initializationPayload.writeInt32(0)
        let initialization = GatewayPacketCodec.encode(
            GatewayTunneledPacket(reliable: true, payload: initializationPayload.data)
        )
        XCTAssertEqual(
            initialization,
            bytes("05 00 01 06 00 00 00 a9 00 00 00 00 00")
        )

        for (opcode, expected) in [
            (Int16(10), "05 00 01 02 00 00 00 0a 00"),
            (Int16(13), "05 00 01 02 00 00 00 0d 00")
        ] {
            var payload = PacketWriter()
            GatewayWire.appendInt16(opcode, to: &payload.data)
            let wrapped = GatewayPacketCodec.encode(
                GatewayTunneledPacket(reliable: true, payload: payload.data)
            )
            XCTAssertEqual(wrapped, bytes(expected))
        }
    }

    func testMovementWrapsInGameplayTunnelNotWorldTunnel() throws {
        let movement = WorldPositionUpdate(
            guid: 0x0102_0304_0506_0708,
            position: GatewayVector3(x: 1, y: 2, z: 3),
            rotation: GatewayVector3(x: 0, y: 0.5, z: -0.25),
            state: 2,
            teleportSequence: 7
        )
        let wrapped = GatewayPacketCodec.encode(
            GatewayTunneledPacket(reliable: true, payload: movement.encoded())
        )
        XCTAssertEqual(wrapped.count, 43)
        XCTAssertEqual(Array(wrapped.prefix(7)), [0x05, 0x00, 0x01, 0x24, 0x00, 0x00, 0x00])

        var session = GatewaySession(connectCode: 7, encryptCode: 0)
        let events = try session.receiveApplicationData(wrapped)
        XCTAssertTrue(events.contains(.world(.positionUpdate(movement))))
        XCTAssertEqual(events.count, 2) // tunnel wrapper plus its terminal world event
    }

    // MARK: - Literal byte helper

    private func bytes(_ hex: String) -> Data {
        let compact = hex.filter { !$0.isWhitespace }
        var result = Data()
        var index = compact.startIndex
        while index < compact.endIndex {
            let next = compact.index(index, offsetBy: 2)
            let text = String(compact[index..<next])
            guard let byte = UInt8(text, radix: 16) else {
                XCTFail("invalid test byte \(text)")
                return Data()
            }
            result.append(byte)
            index = next
        }
        return result
    }
}
