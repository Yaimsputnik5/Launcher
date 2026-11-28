import Foundation
import XCTest
@testable import OSFRCore

/// Decoders for Sanctuary.Packet serializers that use only scalar fields.
/// Every fixture is built from the exact field order in the C# source.
final class GatewaySimplePacketTests: XCTestCase {
    func testHitpointsDecoderMatchesSerializerFieldOrder() throws {
        var writer = PacketWriter()
        GatewayWire.appendInt16(GatewayHitpointsUpdate.opcode, to: &writer.data)
        GatewayWire.appendInt16(GatewayHitpointsUpdate.subOpcode, to: &writer.data)
        writer.writeInt32(412)
        writer.writeInt32(900)

        let packet = try GatewayWorldCodec.decodeAny(writer.data)
        guard case .hitpoints(let update) = packet else {
            return XCTFail("Expected hitpoints, got \(packet)")
        }
        XCTAssertEqual(update.current, 412)
        XCTAssertEqual(update.max, 900)

        var observation = GatewayWorldObservation.empty
        observation.apply(packet)
        XCTAssertEqual(observation.hitpointsCurrent, 412)
        XCTAssertEqual(observation.hitpointsMax, 900)
        XCTAssertNil(observation.zoneName)
        XCTAssertTrue(observation.positions.isEmpty)
    }

    func testClientAreaDecoderMatchesSerializerFieldOrder() throws {
        var writer = PacketWriter()
        GatewayWire.appendInt16(GatewayClientAreaUpdate.opcode, to: &writer.data)
        writer.writeInt32(1189)
        writer.writeBool(true)
        writer.writeInt32(2500)

        let packet = try GatewayWorldCodec.decodeAny(writer.data)
        guard case .clientArea(let area) = packet else {
            return XCTFail("Expected client area, got \(packet)")
        }
        XCTAssertEqual(area.areaID, 1189)
        XCTAssertTrue(area.enabled)
        XCTAssertEqual(area.elapsedMilliseconds, 2500)

        var observation = GatewayWorldObservation.empty
        observation.apply(packet)
        XCTAssertEqual(observation.activeClientAreaID, 1189)
        XCTAssertEqual(observation.clientAreaEnabled, true)
        XCTAssertEqual(observation.clientAreaElapsedMilliseconds, 2500)
    }

    func testMessageOfTheDayDecoderMatchesSerializerFieldOrder() throws {
        var writer = PacketWriter()
        GatewayWire.appendInt16(GatewayMessageOfTheDay.opcode, to: &writer.data)
        writer.writeString("Welcome")
        writer.writeString("Second line")

        let packet = try GatewayWorldCodec.decodeAny(writer.data)
        guard case .messageOfTheDay(let motd) = packet else {
            return XCTFail("Expected MOTD, got \(packet)")
        }
        XCTAssertEqual(motd.message, "Welcome")
        XCTAssertEqual(motd.secondary, "Second line")

        var observation = GatewayWorldObservation.empty
        observation.apply(packet)
        XCTAssertEqual(observation.messageOfTheDay, "Welcome")
        XCTAssertEqual(observation.messageOfTheDaySecondary, "Second line")
    }

    func testMalformedSimplePacketsStayErrorsOrUnknownWithoutState() throws {
        var short = PacketWriter()
        GatewayWire.appendInt16(GatewayHitpointsUpdate.opcode, to: &short.data)
        GatewayWire.appendInt16(GatewayHitpointsUpdate.subOpcode, to: &short.data)
        short.writeInt32(1)
        XCTAssertThrowsError(try GatewayWorldCodec.decodeAny(short.data))

        var wrongSub = PacketWriter()
        GatewayWire.appendInt16(GatewayHitpointsUpdate.opcode, to: &wrongSub.data)
        GatewayWire.appendInt16(99, to: &wrongSub.data)
        wrongSub.writeInt32(1)
        wrongSub.writeInt32(2)
        let fallback = try GatewayWorldCodec.decodeAny(wrongSub.data)
        guard case .unknown(let opcode, let payload) = fallback else {
            return XCTFail("Expected raw-preserving unknown fallback, got \(fallback)")
        }
        XCTAssertEqual(opcode, 38)
        XCTAssertEqual(payload, wrongSub.data)

        var observation = GatewayWorldObservation.empty
        observation.apply(fallback)
        XCTAssertNil(observation.hitpointsCurrent)
        XCTAssertNil(observation.hitpointsMax)
    }

    func testManaDecoderMatchesSerializerFieldOrder() throws {
        var writer = PacketWriter()
        GatewayWire.appendInt16(GatewayManaUpdate.opcode, to: &writer.data)
        GatewayWire.appendInt16(GatewayManaUpdate.subOpcode, to: &writer.data)
        writer.writeInt32(180)
        writer.writeInt32(300)
        writer.writeBool(true)

        let packet = try GatewayWorldCodec.decodeAny(writer.data)
        guard case .mana(let update) = packet else {
            return XCTFail("Expected mana, got \(packet)")
        }
        XCTAssertEqual(update.current, 180)
        XCTAssertEqual(update.max, 300)
        XCTAssertTrue(update.showOverHead)

        var observation = GatewayWorldObservation.empty
        observation.apply(packet)
        XCTAssertEqual(observation.manaCurrent, 180)
        XCTAssertEqual(observation.manaMax, 300)
        XCTAssertEqual(observation.showManaOverHead, true)
        XCTAssertNil(observation.hitpointsCurrent)
        XCTAssertTrue(observation.completedQuestIDs.isEmpty)
    }

    func testRemoveEffectTagDecoderMatchesSerializerFieldOrder() throws {
        var writer = PacketWriter()
        GatewayWire.appendInt16(GatewayEffectTagRemoval.opcode, to: &writer.data)
        GatewayWire.appendInt16(GatewayEffectTagRemoval.subOpcode, to: &writer.data)
        writer.writeInt32(90412)

        let packet = try GatewayWorldCodec.decodeAny(writer.data)
        guard case .removeEffectTag(let removal) = packet else {
            return XCTFail("Expected effect tag removal, got \(packet)")
        }
        XCTAssertEqual(removal.tagID, 90412)

        var observation = GatewayWorldObservation.empty
        observation.apply(packet)
        XCTAssertEqual(observation.lastRemovedEffectTagID, 90412)
        XCTAssertTrue(observation.positions.isEmpty)
    }

    func testQuestPacketsUseIntSubOpcodesAndOnlySetQuestState() throws {
        func questPacket(_ sub: Int32, _ value: Int32) throws -> GatewayWorldPacket {
            var writer = PacketWriter()
            GatewayWire.appendInt16(GatewayQuestComplete.opcode, to: &writer.data)
            writer.writeInt32(sub)
            writer.writeInt32(value)
            return try GatewayWorldCodec.decodeAny(writer.data)
        }

        var observation = GatewayWorldObservation.empty
        let complete = try questPacket(GatewayQuestComplete.subOpcode, 1201)
        guard case .questComplete(let quest) = complete else {
            return XCTFail("Expected quest complete, got \(complete)")
        }
        XCTAssertEqual(quest.questID, 1201)
        observation.apply(complete)

        let failed = try questPacket(GatewayQuestFailed.subOpcode, 1202)
        guard case .questFailed(let quest) = failed else {
            return XCTFail("Expected quest failed, got \(failed)")
        }
        XCTAssertEqual(quest.questID, 1202)
        observation.apply(failed)

        let count = try questPacket(GatewayCompletedQuestCount.subOpcode, 37)
        guard case .completedQuestCount(let update) = count else {
            return XCTFail("Expected completed quest count, got \(count)")
        }
        XCTAssertEqual(update.count, 37)
        observation.apply(count)

        XCTAssertEqual(observation.completedQuestIDs, [1201])
        XCTAssertEqual(observation.failedQuestIDs, [1202])
        XCTAssertEqual(observation.completedQuestCount, 37)
        XCTAssertNil(observation.manaCurrent)
        XCTAssertNil(observation.hitpointsMax)
    }

    func testPetPacketsUseByteSubOpcodesAndOnlySetPetState() throws {
        var statusWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayPetStatus.opcode, to: &statusWriter.data)
        statusWriter.writeUInt8(GatewayPetStatus.subOpcode)
        statusWriter.writeInt32(77)
        statusWriter.writeFloat(0.25)
        statusWriter.writeFloat(0.5)
        statusWriter.writeFloat(0.75)
        statusWriter.writeFloat(1)

        let statusPacket = try GatewayWorldCodec.decodeAny(statusWriter.data)
        guard case .petStatus(let status) = statusPacket else {
            return XCTFail("Expected pet status, got \(statusPacket)")
        }
        XCTAssertEqual(status.petID, 77)
        XCTAssertEqual(status.hunger, 0.25)
        XCTAssertEqual(status.mood, 1)

        var activeWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayPetActive.opcode, to: &activeWriter.data)
        activeWriter.writeUInt8(GatewayPetActive.subOpcode)
        activeWriter.writeInt32(77)
        activeWriter.writeUInt64(0x1122_3344_5566_7788)

        let activePacket = try GatewayWorldCodec.decodeAny(activeWriter.data)
        guard case .petActive(let active) = activePacket else {
            return XCTFail("Expected pet active, got \(activePacket)")
        }
        XCTAssertEqual(active.petGUID, 0x1122_3344_5566_7788)

        var observation = GatewayWorldObservation.empty
        observation.apply(statusPacket)
        observation.apply(activePacket)
        XCTAssertEqual(observation.lastPetStatus?.petID, 77)
        XCTAssertEqual(observation.activePetGUIDs[77], 0x1122_3344_5566_7788)
        XCTAssertNil(observation.membershipInfo)
    }

    func testTradePacketsUseByteSubOpcodesAndOnlySetTradeState() throws {
        var coinWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayTradeCoinCount.opcode, to: &coinWriter.data)
        coinWriter.writeUInt8(GatewayTradeCoinCount.subOpcode)
        coinWriter.writeInt32(501)
        coinWriter.writeInt32(2)
        coinWriter.writeBool(true)
        coinWriter.writeInt32(999)

        let coinPacket = try GatewayWorldCodec.decodeAny(coinWriter.data)
        guard case .tradeCoinCount(let update) = coinPacket else {
            return XCTFail("Expected trade coin count, got \(coinPacket)")
        }
        XCTAssertEqual(update.sessionID, 501)
        XCTAssertTrue(update.isMine)
        XCTAssertEqual(update.offeredCoins, 999)

        var messageWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayTradeMessage.opcode, to: &messageWriter.data)
        messageWriter.writeUInt8(GatewayTradeMessage.subOpcode)
        messageWriter.writeUInt8(2)
        messageWriter.writeUInt8(6)
        messageWriter.writeUInt8(9)

        let messagePacket = try GatewayWorldCodec.decodeAny(messageWriter.data)
        guard case .tradeMessage(let message) = messagePacket else {
            return XCTFail("Expected trade message, got \(messagePacket)")
        }
        XCTAssertTrue(message.partnerDisconnected)
        XCTAssertTrue(message.completed)
        XCTAssertEqual(message.messageCode, 9)

        var observation = GatewayWorldObservation.empty
        observation.apply(coinPacket)
        observation.apply(messagePacket)
        XCTAssertEqual(observation.tradeCoinCounts[501]?.offeredCoins, 999)
        XCTAssertEqual(observation.lastTradeMessage?.messageCode, 9)
        XCTAssertTrue(observation.completedQuestIDs.isEmpty)
    }

    func testMembershipDecoderMatchesSerializerFieldOrder() throws {
        var writer = PacketWriter()
        GatewayWire.appendInt16(GatewayMembershipInfo.opcode, to: &writer.data)
        writer.writeBool(true)
        writer.writeBool(false)

        let packet = try GatewayWorldCodec.decodeAny(writer.data)
        guard case .membership(let info) = packet else {
            return XCTFail("Expected membership, got \(packet)")
        }
        XCTAssertTrue(info.isMember)
        XCTAssertFalse(info.isReferee)

        var observation = GatewayWorldObservation.empty
        observation.apply(packet)
        XCTAssertEqual(observation.membershipInfo?.isMember, true)
        XCTAssertEqual(observation.membershipInfo?.isReferee, false)
        XCTAssertNil(observation.lastPetStatus)
    }
}
