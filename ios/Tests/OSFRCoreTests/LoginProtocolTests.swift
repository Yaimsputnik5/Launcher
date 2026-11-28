import Foundation
import XCTest
@testable import OSFRCore

/// Pure message/framing tests for the Sanctuary LoginUdp_6 handshake.
/// All buffers are synthetic; no sockets or credentials are involved.
final class LoginProtocolTests: XCTestCase {
    // MARK: Header framing

    func testReliableHeaderAndZeroEscapeRoundTrip() throws {
        let header = LoginFrameHeader(type: .reliable1, reliableID: 0x1234)
        let code: UInt32 = 0xDEAD_BEEF
        let ciphertext = Data([0x00, 0x01, 0x02])

        let wire = LoginFrame.encode(header: header, encryptCode: code, ciphertext: ciphertext)

        // 0x00 marker, 0x09 Reliable1, big-endian id, then one escape byte.
        XCTAssertEqual(Array(wire.prefix(4)), [0x00, 0x09, 0x12, 0x34])
        XCTAssertEqual(Array(wire.dropFirst(4).dropLast(2)), [0x00, 0x00, 0x01, 0x02])
        let expectedCRC = UInt16(truncatingIfNeeded: CRC32.checksum(Data(wire.dropLast(2)), encryptCode: code))
        XCTAssertEqual(Array(wire.suffix(2)), be16(expectedCRC))

        let decoded = try LoginFrame.decode(wire, encryptCode: code)
        XCTAssertEqual(decoded.header, header)
        XCTAssertEqual(decoded.encryptCode, code)
        XCTAssertEqual(decoded.ciphertext, ciphertext)
    }

    func testCiphertextWithoutLeadingZeroIsNotEscaped() throws {
        let header = LoginFrameHeader(type: .reliable2, reliableID: 7)
        let ciphertext = Data([0x81, 0x00, 0x02])
        let wire = LoginFrame.encode(header: header, encryptCode: 0, ciphertext: ciphertext)
        XCTAssertEqual(Array(wire.dropFirst(4).dropLast(2)), Array(ciphertext))
        XCTAssertEqual(try LoginFrame.decode(wire, encryptCode: 0).ciphertext, ciphertext)
    }

    func testShortFrameAndBadHeaderAreRejected() {
        XCTAssertThrowsError(try LoginFrame.decode(Data([0x00, 0x09, 0x00, 0x00, 0x00]), encryptCode: 0)) { error in
            XCTAssertEqual(error as? LoginProtocolError, .frameTooShort(expected: 6, available: 5))
        }

        let wire = LoginFrame.encode(header: LoginFrameHeader(), encryptCode: 0, ciphertext: Data([1]))

        var badMarker = wire
        badMarker[0] = 0x01
        XCTAssertThrowsError(try LoginFrame.decode(badMarker, encryptCode: 0)) { error in
            XCTAssertEqual(error as? LoginProtocolError, .invalidFrameMarker(0x01))
        }

        var badType = wire
        badType[1] = UdpFrameType.connect.rawValue
        XCTAssertThrowsError(try LoginFrame.decode(badType, encryptCode: 0)) { error in
            XCTAssertEqual(error as? LoginProtocolError, .unsupportedFrameType(UdpFrameType.connect.rawValue))
        }
    }

    // MARK: CRC with EncryptCode

    func testFrameCRCIsSeededWithEncryptCode() throws {
        let ciphertext = Data([0xAA, 0xBB, 0xCC])
        let header = LoginFrameHeader(reliableID: 42)

        let framed = LoginFrame.encode(header: header, encryptCode: 0x0102_0304, ciphertext: ciphertext)
        let signed = Data(framed.dropLast(2))
        let seeded = UInt16(truncatingIfNeeded: CRC32.checksum(signed, encryptCode: 0x0102_0304))
        let unseeded = UInt16(truncatingIfNeeded: CRC32.checksum(signed, encryptCode: 0))
        XCTAssertEqual(Array(framed.suffix(2)), be16(seeded))
        XCTAssertNotEqual(seeded, unseeded, "CRC must depend on EncryptCode")

        var corrupted = framed
        let wrong = seeded ^ 0x0001
        corrupted[corrupted.count - 1] = UInt8(truncatingIfNeeded: wrong)
        XCTAssertThrowsError(try LoginFrame.decode(corrupted, encryptCode: 0x0102_0304)) { error in
            guard case .crcMismatch(let expected, let actual) = error as? LoginProtocolError else {
                return XCTFail("Expected crcMismatch, got \(error)")
            }
            XCTAssertEqual(expected, seeded)
            XCTAssertEqual(actual, wrong)
        }
    }

    // MARK: RC4 application boundary

    func testRC4AppliesOnlyToApplicationBytesAndContinuesAcrossPackets() throws {
        // Known RC4 vector uses a 5-byte key; LoginCipher keeps separate
        // send/receive streams like Sanctuary's CipherRC4.
        var clientCipher = LoginCipher(key: Data("Key".utf8))
        var serverCipher = LoginCipher(key: Data("Key".utf8))

        let first = Data("Plaintext".utf8)
        let firstEncrypted = clientCipher.encryptPacket(first)
        XCTAssertEqual(hex(firstEncrypted), "BBF316E8D940AF0AD3")

        let header = LoginFrameHeader(reliableID: 1)
        let frame = LoginFrame.encode(header: header, encryptCode: 0x1122_3344, ciphertext: firstEncrypted)
        let parsed = try LoginFrame.decode(frame, encryptCode: 0x1122_3344)
        XCTAssertEqual(serverCipher.decryptPacket(parsed.ciphertext), first)

        let second = Data("Second packet".utf8)
        let secondFrame = LoginFrameCodec.encode(
            packet: second,
            header: LoginFrameHeader(reliableID: 2),
            encryptCode: 0x1122_3344,
            cipher: &clientCipher
        )
        let secondPlaintext = try LoginFrameCodec.decode(frame: secondFrame, encryptCode: 0x1122_3344, cipher: &serverCipher)
        XCTAssertEqual(secondPlaintext, second)

        // A fresh decoder cannot skip the first packet's keystream bytes.
        var freshCipher = LoginCipher(key: Data("Key".utf8))
        let wrong = try LoginFrameCodec.decode(frame: secondFrame, encryptCode: 0x1122_3344, cipher: &freshCipher)
        XCTAssertNotEqual(wrong, second)
    }

    // MARK: Login request / session ticket

    func testSessionRequestUsesSessionAndFingerprint() throws {
        let request = LoginProtocol.SessionRequest(
            sessionID: "0123456789ABCDEF0123456789ABCDEF",
            fingerprint: "ios-device"
        )

        var expected = PacketWriter()
        expected.writeUInt8(1)
        expected.writeString(request.sessionID)
        expected.writeString(request.fingerprint)
        XCTAssertEqual(LoginPacket.encode(request), expected.data)

        let decoded = try LoginPacket.decode(LoginProtocol.SessionRequest.self, from: expected.data)
        XCTAssertEqual(decoded, request)

        var trailing = expected.data
        trailing.append(0x00)
        XCTAssertThrowsError(try LoginPacket.decode(LoginProtocol.SessionRequest.self, from: trailing)) { error in
            XCTAssertEqual(error as? LoginProtocolError, .trailingBytes(1))
        }
    }

    func testSessionReplyCarriesAccountInfoPayload() throws {
        let account = LoginProtocol.AccountInfo(isMember: true, maxCharacters: 10, isAdminAccount: false)
        let reply = LoginProtocol.SessionReply(
            loggedIn: true, status: 1, isMember: true, payload: account.encoded()
        )
        let decoded = try LoginPacket.decode(LoginProtocol.SessionReply.self, from: LoginPacket.encode(reply))
        XCTAssertEqual(decoded, reply)
        XCTAssertEqual(try decoded.accountInfo(), account)
    }

    func testForceDisconnectAndCharacterCreateReplyUseExactFieldOrder() throws {
        var disconnect = PacketWriter()
        disconnect.writeUInt8(4)
        disconnect.writeInt32(9)
        let forced = LoginProtocol.ForceDisconnect(reason: 9)
        XCTAssertEqual(LoginPacket.encode(forced), disconnect.data)
        XCTAssertEqual(try LoginPacket.decode(LoginProtocol.ForceDisconnect.self, from: disconnect.data), forced)
        XCTAssertEqual(try LoginPacket.decodeAny(from: disconnect.data), .forceDisconnect(forced))

        var create = PacketWriter()
        create.writeUInt8(6)
        create.writeInt32(4)
        create.writeUInt64(0x1122_3344_5566_7788)
        let reply = LoginProtocol.CharacterCreateReply(result: 4, guid: 0x1122_3344_5566_7788)
        XCTAssertEqual(LoginPacket.encode(reply), create.data)
        XCTAssertEqual(try LoginPacket.decode(LoginProtocol.CharacterCreateReply.self, from: create.data), reply)
        XCTAssertEqual(try LoginPacket.decodeAny(from: create.data), .characterCreateReply(reply))

        var trailing = disconnect.data
        trailing.append(0x00)
        XCTAssertThrowsError(try LoginPacket.decode(LoginProtocol.ForceDisconnect.self, from: trailing)) { error in
            XCTAssertEqual(error as? LoginProtocolError, .trailingBytes(1))
        }
    }

    // MARK: Character list / select

    func testCharacterSelectListRoundTripWithSyntheticBuffer() throws {
        let guid = GuidHelper.playerGuid(77)
        let details = LoginProtocol.CharacterSelectDetails(
            headshotURL: "headshot.png",
            guid: guid,
            name: "Ada",
            model: 3,
            head: 4,
            hair: 5,
            modelCustomization: "curly",
            facePaint: "none",
            skinTone: "warm",
            eyeTint: 0x1122_3344,
            hairTint: 0x5566_7788,
            attachments: [
                LoginProtocol.CharacterAttachment(
                    modelName: "hat", textureAlias: "hat_tex", tintAlias: "cloth",
                    tintID: 2, compositeEffectID: 9, slot: 6
                )
            ]
        )
        let entity = LoginProtocol.CharacterSelectEntity(
            entityKey: guid, lastServerID: 0, status: 1, applicationData: details.encoded()
        )
        let reply = LoginProtocol.CharacterSelectReply(
            status: 1, canBypassServerLock: false, entities: [entity]
        )

        // Independent layout: opcode 12, status, bool, Int32 count, EntityDetails.
        var expected = PacketWriter()
        expected.writeUInt8(12)
        expected.writeInt32(1)
        expected.writeBool(false)
        expected.writeInt32(1)
        expected.writeUInt64(guid)
        expected.writeInt32(0)
        expected.writeInt32(1)
        expected.writeData(details.encoded())
        XCTAssertEqual(LoginPacket.encode(reply), expected.data)

        let decoded = try LoginPacket.decode(LoginProtocol.CharacterSelectReply.self, from: expected.data)
        XCTAssertEqual(decoded, reply)
        XCTAssertEqual(try decoded.entities.first?.details(), details)
        XCTAssertEqual(try LoginPacket.decodeAny(from: expected.data), .characterSelectReply(reply))
    }

    func testCharacterSelectRequestAndFailureReply() throws {
        let request = LoginProtocol.CharacterSelectRequest()
        XCTAssertEqual(LoginPacket.encode(request), Data([11]))
        XCTAssertEqual(try LoginPacket.decode(LoginProtocol.CharacterSelectRequest.self, from: Data([11])), request)

        let emptyList = LoginProtocol.CharacterSelectReply(status: 2, canBypassServerLock: false, entities: [])
        let decoded = try LoginPacket.decode(
            LoginProtocol.CharacterSelectReply.self,
            from: LoginPacket.encode(emptyList)
        )
        XCTAssertEqual(decoded, emptyList)
    }

    // MARK: Character login ticket

    func testCharacterLoginRequestAndTicketReplyRoundTrip() throws {
        let guid = GuidHelper.playerGuid(1234)
        let clientData = LoginProtocol.ClientLoginData(
            locale: "en_US", localeID: 1033, unknown: false, unknown2: 7, unknown3: -99
        )
        let request = LoginProtocol.CharacterLoginRequest(
            entityKey: guid, serverID: 1, clientLoginData: clientData
        )
        let encodedRequest = LoginPacket.encode(request)
        XCTAssertEqual(Array(encodedRequest.prefix(1)), [7])
        let decodedRequest = try LoginPacket.decode(LoginProtocol.CharacterLoginRequest.self, from: encodedRequest)
        XCTAssertEqual(decodedRequest, request)
        XCTAssertEqual(decodedRequest.characterID, 1234)

        let ticket = LoginProtocol.ClientCharacterData(
            serverAddress: "127.0.0.1:20260",
            serverTicket: "0123456789ABCDEF0123456789ABCDEF",
            cryptoKey: "0123456789ABCDEF0123456789ABCDEF",
            guid: guid,
            unknown: 0,
            unknown2: "",
            unknown3: "",
            unknown4: ""
        )
        let reply = LoginProtocol.CharacterLoginReply(
            entityKey: guid, serverID: 1, status: 1, payload: ticket.encoded()
        )
        let decodedReply = try LoginPacket.decode(LoginProtocol.CharacterLoginReply.self, from: LoginPacket.encode(reply))
        XCTAssertEqual(decodedReply, reply)
        XCTAssertEqual(try decodedReply.clientData(), ticket)

        let failure = LoginProtocol.CharacterLoginReply(entityKey: 0, serverID: 0, status: 6)
        XCTAssertEqual(try LoginPacket.decode(
            LoginProtocol.CharacterLoginReply.self, from: LoginPacket.encode(failure)
        ), failure)
    }

    func testMalformedTicketPayloadIsRejected() throws {
        var truncated = PacketWriter()
        truncated.writeUInt8(7)
        truncated.writeUInt64(GuidHelper.playerGuid(1))
        truncated.writeInt32(1)
        truncated.writeInt32(4)
        truncated.writeUInt8(0) // ClientLoginData needs more than one byte
        XCTAssertThrowsError(try LoginPacket.decode(LoginProtocol.CharacterLoginRequest.self, from: truncated.data))
    }

    // MARK: Strict opcode handling

    func testUnexpectedAndUnsupportedOpcodes() {
        var wrong = PacketWriter()
        wrong.writeUInt8(2)
        wrong.writeString("session")
        XCTAssertThrowsError(try LoginPacket.decode(LoginProtocol.SessionRequest.self, from: wrong.data)) { error in
            XCTAssertEqual(error as? LoginProtocolError, .unexpectedOpcode(expected: 1, actual: 2))
        }
        XCTAssertThrowsError(try LoginPacket.opcode(from: Data([0xFF]))) { error in
            XCTAssertEqual(error as? LoginProtocolError, .unsupportedOpcode(0xFF))
        }
    }

    // MARK: Helpers

    private func be16(_ value: UInt16) -> [UInt8] {
        [UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }
}
