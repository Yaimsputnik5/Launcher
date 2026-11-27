import Foundation
import XCTest
@testable import OSFRCore

/// Pure codec/session tests for the Sanctuary `CGAPI_527` gateway protocol.
/// Every buffer is synthetic: no sockets, no credentials, no captured traffic.
///
/// Source-backed behavior is cited at each test. Sanctuary ships no AES/CCM
/// known-answer vector, so the crypto vectors below are the public FIPS-197
/// AES vectors plus a CCM vector derived with an independent AESCCM
/// implementation using Sanctuary's 13-byte nonce layout.
final class GatewayProtocolTests: XCTestCase {
    // MARK: - Crypto

    /// FIPS-197 Appendix B/C known-answer vectors. Sanctuary delegates AES to
    /// `System.Security.Cryptography.AesCcm` in
    /// `Sanctuary.Core/Cryptography/CipherCCM.cs`; this file reimplements that
    /// primitive in Foundation-only Swift so the vectors must still match.
    func testAESKnownAnswerVectors() throws {
        let plaintext = bytes("00112233445566778899aabbccddeeff")

        let aes128 = try AESBlock(key: bytes("000102030405060708090a0b0c0d0e0f"))
        XCTAssertEqual(
            hex(Data(aes128.encryptBlock(Array(plaintext)))),
            "69C4E0D86A7B0430D8CDB78070B4C55A"
        )
        XCTAssertEqual(
            Data(aes128.decryptBlock(aes128.encryptBlock(Array(plaintext)))),
            plaintext
        )

        let aes256 = try AESBlock(
            key: bytes("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
        )
        XCTAssertEqual(
            hex(Data(aes256.encryptBlock(Array(plaintext)))),
            "8EA2B7CA516745BFEAFC49904B496089"
        )
        XCTAssertEqual(
            Data(aes256.decryptBlock(aes256.encryptBlock(Array(plaintext)))),
            plaintext
        )
    }

    /// Independent CCM vector with the 13-byte nonce / 16-byte tag parameters
    /// from `Sanctuary.Core/Cryptography/CipherCCM.cs`. Not captured traffic.
    func testCCMReferenceVectorAndTamperRejection() throws {
        let key = bytes("404142434445464748494a4b4c4d4e4f")
        let nonce = bytes("101112131415161718191a1b1c")
        let plaintext = bytes("20212223")
        let ccm = try AESCCM(key: key)

        let sealed = try ccm.encrypt(nonce: nonce, plaintext: plaintext)
        XCTAssertEqual(hex(sealed.ciphertext), "69915DAD")
        XCTAssertEqual(hex(sealed.tag), "81E1E0AC4539B4B397FCF0F8DD6B97AC")
        XCTAssertEqual(try ccm.decrypt(nonce: nonce, ciphertext: sealed.ciphertext, tag: sealed.tag), plaintext)

        var badTag = Array(sealed.tag)
        badTag[0] ^= 1
        XCTAssertThrowsError(
            try ccm.decrypt(nonce: nonce, ciphertext: sealed.ciphertext, tag: Data(badTag))
        ) { error in
            XCTAssertEqual(error as? GatewayProtocolError, .authenticationFailed)
        }

        var badCiphertext = Array(sealed.ciphertext)
        badCiphertext[0] ^= 1
        XCTAssertThrowsError(
            try ccm.decrypt(nonce: nonce, ciphertext: Data(badCiphertext), tag: sealed.tag)
        ) { error in
            XCTAssertEqual(error as? GatewayProtocolError, .authenticationFailed)
        }
    }

    /// `CipherCCM.cs` uses no AAD for gateway packets; the AAD branch exists to
    /// exercise the B0 Adata flag and the SP 800-38C construction.
    func testCCMRoundTripWithAndWithoutAAD() throws {
        let ccm = try AESCCM(key: bytes("000102030405060708090a0b0c0d0e0f"))
        let nonce = bytes("0102030405060708090a0b0c0d")
        let plaintext = Data("Sanctuary CCM round trip".utf8)

        let plainResult = try ccm.encrypt(nonce: nonce, plaintext: plaintext)
        XCTAssertEqual(
            try ccm.decrypt(nonce: nonce, ciphertext: plainResult.ciphertext, tag: plainResult.tag),
            plaintext
        )

        let aad = bytes("0001020304050607")
        let aadResult = try ccm.encrypt(nonce: nonce, plaintext: plaintext, aad: aad)
        XCTAssertNotEqual(aadResult.tag, plainResult.tag)
        XCTAssertEqual(
            try ccm.decrypt(nonce: nonce, ciphertext: aadResult.ciphertext, tag: aadResult.tag, aad: aad),
            plaintext
        )
        XCTAssertThrowsError(
            try ccm.decrypt(nonce: nonce, ciphertext: aadResult.ciphertext, tag: aadResult.tag)
        ) { error in
            XCTAssertEqual(error as? GatewayProtocolError, .authenticationFailed)
        }
    }

    /// `Sanctuary.Core/Cryptography/CipherCCM.cs`: ciphertext || tag || nonce,
    /// increasing 8-byte little-endian counter, and zero-buffer rejection.
    func testCipherCCMWrapperTrailerAndReplayProtection() throws {
        let key = Data("00112233445566778899aabbccddeeff".utf8)
        var sender = try GatewayCipher(key: key)
        var receiver = try GatewayCipher(key: key)
        let message = Data("gateway payload".utf8)
        let suffix = bytes("0102030405")

        let framed = try sender.encrypt(message, nonceSuffix: suffix)
        XCTAssertEqual(framed.count, message.count + AESCCM.tagLength + AESCCM.nonceLength)
        XCTAssertEqual(Array(framed.suffix(5)), Array(suffix))
        XCTAssertEqual(Array(framed.suffix(AESCCM.nonceLength).prefix(8)), [1, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(try receiver.decrypt(framed), message)
        XCTAssertEqual(sender.encryptCounter, 1)
        XCTAssertEqual(receiver.decryptCounter, 1)

        // Same counter with a flipped ciphertext byte is a replay, not a fresh
        // packet; the wrapper must reject it before touching the cipher.
        var replay = framed
        replay[0] ^= 1
        XCTAssertThrowsError(try receiver.decrypt(replay)) { error in
            guard case .replayRejected(let counter, let last) = error as? GatewayProtocolError else {
                return XCTFail("expected replay rejection, got \(String(describing: error))")
            }
            XCTAssertEqual(counter, 1)
            XCTAssertEqual(last, 1)
        }

        let zeroNonce = Data(repeating: 0, count: AESCCM.tagLength + AESCCM.nonceLength)
        XCTAssertThrowsError(try receiver.decrypt(zeroNonce)) { error in
            XCTAssertEqual(error as? GatewayProtocolError, .invalidCipherTrailer)
        }
    }

    // MARK: - Physical framing

    /// `Sanctuary.UdpLibrary/UdpConnection.cs` + `Internal/UdpReliableChannel.cs`:
    /// 0x00 marker, packet type, big-endian UInt16 reliable id, zero-escaped
    /// body, big-endian CRC-32 seeded with EncryptCode. `GatewayConnection`
    /// inserts a one-byte compression flag (0 == raw) before the reliable id,
    /// because `PhysicalSend` encrypts everything after the first two bytes.
    func testFrameRoundTripAndZeroEscape() throws {
        let header = LoginFrameHeader(type: .reliable1, reliableID: 0x1234)
        let frame = GatewayFrame(header: header, compressionEnabled: true, payload: Data([0x00, 0x01, 0x02]))
        let wire = GatewayFrameCodec.encode(frame, encryptCode: 0xDEAD_BEEF)

        XCTAssertEqual(Array(wire.prefix(5)), [0x00, 0x09, 0x00, 0x12, 0x34])
        // Escape byte, then payload.
        XCTAssertEqual(Array(wire.dropFirst(5).dropLast(2)), [0x00, 0x00, 0x01, 0x02])

        let decoded = try GatewayFrameCodec.decode(wire, encryptCode: 0xDEAD_BEEF)
        XCTAssertEqual(decoded.header, header)
        XCTAssertEqual(decoded.payload, frame.payload)

        let raw = GatewayFrame(reliableID: 9, compressionEnabled: false, payload: Data([1, 2, 3]))
        let rawWire = GatewayFrameCodec.encode(raw, encryptCode: 0)
        XCTAssertEqual(Array(rawWire.prefix(4)), [0x00, 0x09, 0x00, 0x09])
        XCTAssertEqual(
            try GatewayFrameCodec.decode(rawWire, encryptCode: 0, compressionEnabled: false).payload,
            raw.payload
        )
    }

    func testTruncatedAndMalformedFramesAreRejected() throws {
        XCTAssertThrowsError(try GatewayFrameCodec.decode(Data([0x00]), encryptCode: 0)) { error in
            guard case .physicalFrame(.frameTooShort) = error as? GatewayProtocolError else {
                return XCTFail("expected truncation, got \(String(describing: error))")
            }
        }

        let wire = GatewayFrameCodec.encode(
            GatewayFrame(reliableID: 1, payload: Data([0x01])), encryptCode: 0
        )
        var badMarker = wire
        badMarker[0] = 0x01
        XCTAssertThrowsError(try GatewayFrameCodec.decode(badMarker, encryptCode: 0)) { error in
            guard case .physicalFrame(.invalidFrameMarker(0x01)) = error as? GatewayProtocolError else {
                return XCTFail("expected bad marker, got \(String(describing: error))")
            }
        }

        var badCRC = wire
        badCRC[badCRC.count - 1] ^= 1
        XCTAssertThrowsError(try GatewayFrameCodec.decode(badCRC, encryptCode: 0)) { error in
            guard case .physicalFrame(.crcMismatch) = error as? GatewayProtocolError else {
                return XCTFail("expected CRC mismatch, got \(String(describing: error))")
            }
        }

        // The compression flag is byte 2, not part of the reliable id. A
        // nonzero flag must carry a valid RFC 1950 zlib stream; arbitrary bytes
        // are rejected instead of being parsed as a reliable frame.
        var signed = Data([0x00, 0x09, 0x01, 0, 0, 0, 0, 0, 0, 0, 0])
        let crc = UInt16(truncatingIfNeeded: CRC32.checksum(signed, encryptCode: 0))
        signed.append(UInt8(truncatingIfNeeded: crc >> 8))
        signed.append(UInt8(truncatingIfNeeded: crc))
        XCTAssertThrowsError(try GatewayFrameCodec.decode(signed, encryptCode: 0)) { error in
            guard case .malformedFrame = error as? GatewayProtocolError else {
                return XCTFail("expected inflate failure, got \(String(describing: error))")
            }
        }
    }

    // MARK: - Application wrapper

    /// `Sanctuary.Core/IO/PacketUtils.cs`: flag 1 + LE magic 0xF3D4A5C9.
    func testSecureWrapperRoundTripAndTrailerValidation() throws {
        let key = Data("00112233445566778899aabbccddeeff".utf8)
        var senderCipher = try GatewayCipher(key: key)
        var receiverCipher: GatewayCipher? = try GatewayCipher(key: key)
        let packet = GatewayPacketCodec.encode(GatewayLoginReply(success: true))

        let wrapped = try GatewayPayloadCodec.wrapSecure(
            packet, cipher: &senderCipher, nonceSuffix: bytes("0102030405")
        )
        XCTAssertEqual(Array(wrapped.suffix(4)), [0xC9, 0xA5, 0xD4, 0xF3])
        XCTAssertEqual(wrapped[wrapped.count - 5], 1)
        XCTAssertEqual(try GatewayPayloadCodec.unwrap(wrapped, cipher: &receiverCipher), packet)

        var badMagic = wrapped
        badMagic[badMagic.count - 1] ^= 0xFF
        XCTAssertEqual(try GatewayPayloadCodec.unwrap(badMagic, cipher: &receiverCipher), badMagic)

        var badFlag = wrapped
        badFlag[badFlag.count - 5] = 0
        XCTAssertThrowsError(try GatewayPayloadCodec.unwrap(badFlag, cipher: &receiverCipher)) { error in
            XCTAssertEqual(error as? GatewayProtocolError, .invalidEncryptionFlag(0))
        }

        var noCipher: GatewayCipher?
        XCTAssertThrowsError(try GatewayPayloadCodec.unwrap(wrapped, cipher: &noCipher)) { error in
            XCTAssertEqual(error as? GatewayProtocolError, .cipherNotInitialized)
        }
    }

    // MARK: - Client-facing gateway packets

    /// `Sanctuary.Packet/ClientGateway/PacketLogin.cs` (opcode 1) and
    /// `PacketLoginReply.cs` (opcode 2).
    func testSessionHelloAndLoginReplyRoundTrip() throws {
        let hello = GatewaySessionHello(
            ticket: "00112233445566778899aabbccddeeff",
            guid: 0x1234,
            version: "1.910.1.530630",
            unknown: ""
        )
        XCTAssertEqual(try GatewayPacketCodec.decode(GatewaySessionHello.self, from: GatewayPacketCodec.encode(hello)), hello)

        let reply = GatewayLoginReply(success: true)
        XCTAssertEqual(try GatewayPacketCodec.decode(GatewayLoginReply.self, from: GatewayPacketCodec.encode(reply)), reply)
        XCTAssertEqual(try GatewayPacketCodec.opcode(from: GatewayPacketCodec.encode(reply)), .loginReply)

        var wrongOpcode = GatewayPacketCodec.encode(reply)
        wrongOpcode[0] = 1
        XCTAssertThrowsError(try GatewayPacketCodec.decode(GatewayLoginReply.self, from: wrongOpcode)) { error in
            XCTAssertEqual(error as? GatewayProtocolError, .unexpectedOpcode(expected: 2, actual: 1))
        }
    }

    /// `Sanctuary.Packet/ClientGateway/PacketTunneledClientPacket.cs` (opcode 5).
    func testTunneledPacketRoundTrip() throws {
        let payload = Data([0x7D, 0x00, 0x01, 0x02])
        let message = GatewayTunneledPacket(reliable: true, payload: payload)
        let decoded = try GatewayPacketCodec.decode(GatewayTunneledPacket.self, from: GatewayPacketCodec.encode(message))
        XCTAssertEqual(decoded, message)
    }

    // MARK: - Gateway <-> Login packets

    /// `Sanctuary.Packet/Custom/GatewayCharacterLogin.cs` (opcode 102):
    /// `ulong Id`, `ulong Session`, both little-endian.
    func testCharacterLoginPacketRoundTrip() throws {
        let login = GatewayCharacterLogin(id: 0x1122_3344_5566_7788, session: 0xDEAD_BEEF_CAFE_F00D)
        let wire = GatewayInternalCodec.encode(login)
        XCTAssertEqual(Array(wire.prefix(1)), [102])
        XCTAssertEqual(try GatewayInternalCodec.decode(GatewayCharacterLogin.self, from: wire), login)
        XCTAssertEqual(try GatewayInternalCodec.opcode(from: wire), .characterLogin)

        var truncated = wire
        truncated.removeLast()
        XCTAssertThrowsError(try GatewayInternalCodec.decode(GatewayCharacterLogin.self, from: truncated)) { error in
            guard case .wire = error as? GatewayProtocolError else {
                return XCTFail("expected truncated read, got \(String(describing: error))")
            }
        }

        let reply = GatewayCharacterReleaseReply(requestID: 7, released: true)
        XCTAssertEqual(
            try GatewayInternalCodec.decode(GatewayCharacterReleaseReply.self, from: GatewayInternalCodec.encode(reply)),
            reply
        )
    }

    // MARK: - World packets and session flow

    func testWorldPacketRoundTrips() throws {
        let position = WorldPositionUpdate(
            guid: 0x1234,
            position: GatewayVector3(x: 1, y: 2, z: 3),
            rotation: GatewayVector3(x: 0, y: 0, z: 0.5),
            state: 2,
            teleportSequence: 3
        )
        XCTAssertEqual(try GatewayWorldCodec.decodeAny(position.encoded()), .positionUpdate(position))

        let chat = GatewayChatMessage(
            channel: .worldArea,
            fromGUID: 1,
            toGUID: 2,
            fromName: GatewayName(firstNameID: 3, lastNamePrefixID: 4, lastNameSuffixID: 5, firstName: "A", lastName: "B"),
            toName: GatewayName(firstNameID: 6, lastNamePrefixID: 7, lastNameSuffixID: 8, firstName: "C", lastName: "D"),
            message: "hello",
            position: GatewayVector4(x: 1, y: 2, z: 3, w: 4),
            guildGUID: 9,
            languageID: 10,
            areaNameID: 11
        )
        XCTAssertEqual(try GatewayChatMessage(data: chat.encoded()), chat)
        XCTAssertEqual(try GatewayWorldCodec.decodeAny(chat.encoded()), .chat(chat))
    }

    /// `BasePlayerUpdatePacket` spawn prefixes (sub 1 = PC, sub 2 = NPC) are
    /// enough to place markers; trailing appearance fields are intentionally
    /// not decoded. Source: Sanctuary's PlayerUpdatePacketAddPc/AddNpc.cs.
    func testPlayerSpawnPrefixDecodesForPacketBackedMarkers() throws {
        var pc = PacketWriter()
        GatewayWire.appendInt16(35, to: &pc.data)
        GatewayWire.appendInt16(1, to: &pc.data)
        pc.writeUInt64(0x1234)
        GatewayName(
            firstNameID: 3,
            lastNamePrefixID: 4,
            lastNameSuffixID: 5,
            firstName: "Ada",
            lastName: "Lovelace"
        ).append(to: &pc)
        pc.writeInt32(7) // model
        pc.writeInt32(1) // chat bubble foreground
        pc.writeInt32(2) // chat bubble background
        pc.writeInt32(3) // chat bubble size
        pc.writeFloat(10) // position x/y/z/w
        pc.writeFloat(20)
        pc.writeFloat(30)
        pc.writeFloat(1)
        pc.writeFloat(0.1) // rotation x/y/z/w
        pc.writeFloat(0.2)
        pc.writeFloat(0.3)
        pc.writeFloat(0.4)

        let decodedPC = try GatewayWorldCodec.decodeAny(pc.data)
        guard case .entityAdded(let addition) = decodedPC else {
            return XCTFail("expected an entity spawn, got \(decodedPC)")
        }
        XCTAssertFalse(addition.isNPC)
        XCTAssertEqual(addition.guid, 0x1234)
        XCTAssertEqual(addition.name, "Ada Lovelace")
        XCTAssertEqual(addition.modelID, 7)
        XCTAssertEqual(addition.position, GatewayVector4(x: 10, y: 20, z: 30, w: 1))

        var observation = GatewayWorldObservation.empty
        observation.apply(decodedPC)
        XCTAssertEqual(observation.positionCount, 1)
        XCTAssertEqual(observation.names[0x1234], "Ada Lovelace")

        var npc = PacketWriter()
        GatewayWire.appendInt16(35, to: &npc.data)
        GatewayWire.appendInt16(2, to: &npc.data)
        npc.writeUInt64(0xABCD)
        npc.writeInt32(99) // name id
        npc.writeInt32(42) // model id
        npc.writeBool(false)
        npc.writeInt32(1) // chat bubble foreground
        npc.writeInt32(2) // chat bubble background
        npc.writeInt32(3) // chat bubble size
        npc.writeFloat(1.5) // scale
        npc.writeFloat(-4)
        npc.writeFloat(5)
        npc.writeFloat(6)
        npc.writeFloat(1)
        npc.writeFloat(0)
        npc.writeFloat(0)
        npc.writeFloat(0)
        npc.writeFloat(1)

        let decodedNPC = try GatewayWorldCodec.decodeAny(npc.data)
        guard case .entityAdded(let npcAddition) = decodedNPC else {
            return XCTFail("expected an entity spawn, got \(decodedNPC)")
        }
        XCTAssertTrue(npcAddition.isNPC)
        XCTAssertEqual(npcAddition.name, "NPC 99")
        XCTAssertEqual(npcAddition.position, GatewayVector4(x: -4, y: 5, z: 6, w: 1))
    }

    /// PacketSendSelfToClient (12) wraps a length-prefixed raw ClientPcData.
    /// Source: Sanctuary.Packet.PacketSendSelfToClient.cs and ClientPcData.cs.
    func testSendSelfWrapperDecodesRawClientPcData() throws {
        var player = PacketWriter()
        player.writeUInt64(0x1122_3344_5566_7788) // LaunchTicket
        player.writeUInt64(77) // Guid
        player.writeInt32(5) // Model
        player.writeString("Head")
        player.writeString("Hair")
        player.writeInt32(11) // HairColor
        player.writeInt32(12) // EyeColor
        player.writeString("Skin")
        player.writeString("Face")
        player.writeString("Custom")
        player.writeInt32(1) // HeadId
        player.writeInt32(2) // HairId
        player.writeInt32(3) // SkinToneId
        player.writeInt32(4) // FacePaintId
        player.writeInt32(6) // ModelCustomizationId
        player.writeFloat(1)
        player.writeFloat(2)
        player.writeFloat(3)
        player.writeFloat(1)
        player.writeFloat(0)
        player.writeFloat(0)
        player.writeFloat(0)
        player.writeFloat(1)
        GatewayName(
            firstNameID: 1,
            lastNamePrefixID: 2,
            lastNameSuffixID: 3,
            firstName: "Ada",
            lastName: "Test"
        ).append(to: &player)

        var wrapped = PacketWriter()
        GatewayWire.appendInt16(12, to: &wrapped.data)
        wrapped.writeData(player.data)

        guard case .sendSelf(let packet) = try GatewayWorldCodec.decodeAny(wrapped.data) else {
            return XCTFail("expected PacketSendSelfToClient")
        }
        XCTAssertEqual(packet.payload, player.data)
        XCTAssertEqual(packet.client.guid, 77)
        XCTAssertEqual(packet.client.position, GatewayVector4(x: 1, y: 2, z: 3, w: 1))

        var observation = GatewayWorldObservation.empty
        observation.apply(.sendSelf(packet))
        XCTAssertEqual(observation.playerGUID, 77)
        XCTAssertEqual(observation.names[77], "Ada Test")

        var session = GatewaySession(connectCode: 1, encryptCode: 0)
        let events = try session.receiveApplicationData(
            GatewayPacketCodec.encode(GatewayTunneledWorldPacket(payload: wrapped.data))
        )
        XCTAssertTrue(events.contains(.world(.sendSelf(packet))))
        XCTAssertEqual(events.count, 2) // tunneled packet plus its terminal world event
    }

    /// End-to-end synthetic flow: unencrypted `PacketLogin`, login reply,
    /// then an encrypted tunneled world packet.
    func testSessionLoginThenEncryptedWorldPacket() throws {
        let ticket = "00112233445566778899aabbccddeeff"
        var client = GatewaySession(connectCode: 7, encryptCode: 0xDEAD_BEEF)
        var server = GatewaySession(connectCode: 7, encryptCode: 0xDEAD_BEEF)
        try client.setCipher(ticket: ticket)
        try server.setCipher(ticket: ticket)

        let hello = GatewaySessionHello(ticket: ticket, guid: 1, version: "1.910.1.530630", unknown: "")
        let loginEvents = server.receive(frame: try client.beginLogin(hello))
        XCTAssertTrue(loginEvents.contains(.packet(.login(hello))))

        let reply = try server.makeFrame(
            packet: GatewayPacketCodec.encode(GatewayLoginReply(success: true)), secure: false
        )
        let replyEvents = client.receive(frame: reply)
        XCTAssertTrue(replyEvents.contains(.stateChanged(.authenticated)))

        let position = WorldPositionUpdate(
            guid: 1,
            position: GatewayVector3(x: 1, y: 2, z: 3),
            rotation: GatewayVector3(x: 0, y: 0, z: 0),
            state: 0,
            teleportSequence: 0
        )
        let tunnel = GatewayTunneledPacket(reliable: true, payload: position.encoded())
        let worldEvents = server.receive(frame: try client.send(tunnel, nonceSuffix: bytes("0102030405")))
        XCTAssertTrue(worldEvents.contains(.packet(.tunneled(tunnel))))
        XCTAssertTrue(worldEvents.contains(.world(.positionUpdate(position))))
    }

    /// `Sanctuary.UdpLibrary/Internal/UdpReliableChannel.cs` initializes
    /// `ReliableIncomingId` to 0 and delivers only the packet carrying the next
    /// expected id. Starting at 1 would have the server acknowledge the frame
    /// but never route `PacketLogin` to its handler.
    func testGatewayReliableIDsStartAtZeroThenIncrement() throws {
        var session = GatewaySession(connectCode: 7, encryptCode: 0xDEAD_BEEF)
        try session.setCipher(ticket: "00112233445566778899aabbccddeeff")

        let hello = GatewaySessionHello(
            ticket: "00112233445566778899aabbccddeeff",
            guid: 1,
            version: "1.910.1.530630",
            unknown: ""
        )
        let login = try session.beginLogin(hello)
        XCTAssertEqual(
            try GatewayFrameCodec.decode(login, encryptCode: 0xDEAD_BEEF).header.reliableID,
            0
        )

        let followUp = try session.makeFrame(packet: Data([0x01, 0x00]), secure: false)
        XCTAssertEqual(
            try GatewayFrameCodec.decode(followUp, encryptCode: 0xDEAD_BEEF).header.reliableID,
            1
        )

        let next = try session.makeFrame(packet: Data([0x02, 0x00]), secure: false)
        XCTAssertEqual(
            try GatewayFrameCodec.decode(next, encryptCode: 0xDEAD_BEEF).header.reliableID,
            2
        )
    }

    // MARK: - Connect / confirm

    /// `Sanctuary.UdpLibrary/UdpConnection.cs`: connect fields are big-endian.
    /// Confirm has 17 mandatory bytes and an optional version at offset 17;
    /// the live public gateway sends the full 21-byte form.
    func testConnectAndConfirmPacketRoundTrip() throws {
        let connect = GatewayConnectPacket(connectCode: 0x7F)
        let connectWire = try connect.encoded()
        XCTAssertEqual(Array(connectWire.prefix(14)), [
            0x00, 0x01, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x7F, 0x00, 0x00, 0x20, 0x00
        ])
        XCTAssertEqual(try GatewayConnectPacket(data: connectWire), connect)

        let confirm = GatewayConfirmPacket(
            connectCode: 0x7F,
            encryptCode: Int32(bitPattern: 0xDEAD_BEEF),
            crcBytes: 2,
            encryptMethod1: 1,
            encryptMethod2: 0,
            maxRawPacketSize: 0x2000,
            protocolVersion: 3
        )
        let confirmWire = confirm.encoded()
        XCTAssertEqual(confirmWire.count, 21)
        XCTAssertEqual(try GatewayConfirmPacket(data: confirmWire), confirm)

        let optionalVersionWire = confirmWire.prefix(17)
        let withoutVersion = try GatewayConfirmPacket(data: optionalVersionWire)
        XCTAssertNil(withoutVersion.protocolVersion)
        XCTAssertEqual(withoutVersion.connectCode, confirm.connectCode)
        XCTAssertEqual(withoutVersion.encryptCode, confirm.encryptCode)
        XCTAssertEqual(withoutVersion.maxRawPacketSize, confirm.maxRawPacketSize)
    }

    // MARK: Helpers

    private func bytes(_ hex: String) -> Data {
        var out = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            out.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return out
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }
}
