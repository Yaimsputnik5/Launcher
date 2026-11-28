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

    func testPlayerUpdateDecodersUseShortSubOpcodes() throws {
        func packet(
            _ opcode: Int16,
            _ subOpcode: Int16,
            _ body: (inout PacketWriter) -> Void
        ) throws -> GatewayWorldPacket {
            var writer = PacketWriter()
            GatewayWire.appendInt16(opcode, to: &writer.data)
            GatewayWire.appendInt16(subOpcode, to: &writer.data)
            body(&writer)
            return try GatewayWorldCodec.decodeAny(writer.data)
        }

        let look = try packet(
            GatewayLookAtTarget.opcode,
            GatewayLookAtTarget.subOpcode
        ) { writer in
            writer.writeUInt64(0x1111_2222_3333_4444)
            writer.writeUInt64(0xAAAA_BBBB_CCCC_DDDD)
        }
        guard case .lookAtTarget(let lookAt) = look else {
            return XCTFail("Expected look-at target, got \(look)")
        }
        XCTAssertEqual(lookAt.guid, 0x1111_2222_3333_4444)
        XCTAssertEqual(lookAt.targetGUID, 0xAAAA_BBBB_CCCC_DDDD)

        let speed = try packet(
            GatewayExpectedSpeed.opcode,
            GatewayExpectedSpeed.subOpcode
        ) { writer in
            writer.writeUInt64(0x1111_2222_3333_4444)
            writer.writeFloat(6.25)
        }
        guard case .expectedSpeed(let expected) = speed else {
            return XCTFail("Expected expected speed, got \(speed)")
        }
        XCTAssertEqual(expected.expectedSpeed, 6.25)

        let bubble = try packet(
            GatewayThoughtBubble.opcode,
            GatewayThoughtBubble.subOpcode
        ) { writer in
            writer.writeUInt64(0x1111_2222_3333_4444)
            writer.writeInt32(7)
            writer.writeInt32(12)
            writer.writeBool(false)
        }
        guard case .thoughtBubble(let thought) = bubble else {
            return XCTFail("Expected thought bubble, got \(bubble)")
        }
        XCTAssertEqual(thought.iconID, 7)
        XCTAssertEqual(thought.durationSeconds, 12)
        XCTAssertFalse(thought.clear)

        let collidable = try packet(
            GatewayCollidableUpdate.opcode,
            GatewayCollidableUpdate.subOpcode
        ) { writer in
            writer.writeUInt64(0x1111_2222_3333_4444)
            writer.writeBool(true)
        }
        guard case .collidable(let update) = collidable else {
            return XCTFail("Expected collidable update, got \(collidable)")
        }
        XCTAssertTrue(update.collidable)

        var observation = GatewayWorldObservation.empty
        for packet in [look, speed, bubble, collidable] {
            observation.apply(packet)
        }
        XCTAssertEqual(
            observation.lookTargets[0x1111_2222_3333_4444],
            0xAAAA_BBBB_CCCC_DDDD
        )
        XCTAssertEqual(observation.expectedSpeeds[0x1111_2222_3333_4444], 6.25)
        XCTAssertEqual(observation.thoughtBubbles[0x1111_2222_3333_4444]?.iconID, 7)
        XCTAssertEqual(observation.collidableByGUID[0x1111_2222_3333_4444], true)
        XCTAssertNil(observation.mountStates[0x1111_2222_3333_4444])
    }

    func testThoughtBubbleClearRemovesPacketBackedState() throws {
        var writer = PacketWriter()
        GatewayWire.appendInt16(GatewayThoughtBubble.opcode, to: &writer.data)
        GatewayWire.appendInt16(GatewayThoughtBubble.subOpcode, to: &writer.data)
        writer.writeUInt64(99)
        writer.writeInt32(0)
        writer.writeInt32(0)
        writer.writeBool(true)
        let packet = try GatewayWorldCodec.decodeAny(writer.data)

        var observation = GatewayWorldObservation.empty
        observation.apply(packet)
        XCTAssertTrue(observation.thoughtBubbles.isEmpty)
        XCTAssertEqual(observation.lastEvent, "Thought bubble · 99 · icon 0")
    }

    func testFriendOnlineUsesByteSubOpcodeAndLengthPrefixedName() throws {
        var writer = PacketWriter()
        GatewayWire.appendInt16(GatewayFriendOnline.opcode, to: &writer.data)
        writer.writeUInt8(GatewayFriendOnline.subOpcode)
        writer.writeString("Astra")
        writer.writeUInt64(0x0123_4567_89AB_CDEF)
        writer.writeBool(false)

        let packet = try GatewayWorldCodec.decodeAny(writer.data)
        guard case .friendOnline(let friend) = packet else {
            return XCTFail("Expected friend online, got \(packet)")
        }
        XCTAssertEqual(friend.name, "Astra")
        XCTAssertEqual(friend.guid, 0x0123_4567_89AB_CDEF)
        XCTAssertFalse(friend.isLocal)

        var observation = GatewayWorldObservation.empty
        observation.apply(packet)
        XCTAssertEqual(observation.friendPresence[friend.guid]?.name, "Astra")
        XCTAssertEqual(observation.friendPresence[friend.guid]?.isLocal, false)
        XCTAssertNil(observation.lastPetTrickNotification)
    }

    func testMountDecodersUseByteSubOpcodes() throws {
        var mountWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayMountState.opcode, to: &mountWriter.data)
        mountWriter.writeUInt8(GatewayMountState.subOpcode)
        mountWriter.writeUInt64(101)
        mountWriter.writeUInt64(202)
        mountWriter.writeInt32(3)
        mountWriter.writeInt32(2)
        mountWriter.writeInt32(77)
        mountWriter.writeInt32(9012)
        mountWriter.writeFloat(0.375)

        let mountPacket = try GatewayWorldCodec.decodeAny(mountWriter.data)
        guard case .mountState(let mount) = mountPacket else {
            return XCTFail("Expected mount state, got \(mountPacket)")
        }
        XCTAssertEqual(mount.riderGUID, 101)
        XCTAssertEqual(mount.mountGUID, 202)
        XCTAssertEqual(mount.seat, 3)
        XCTAssertEqual(mount.queuePosition, 2)
        XCTAssertEqual(mount.unknown, 77)
        XCTAssertEqual(mount.compositeEffectID, 9012)
        XCTAssertEqual(mount.nameVerticalOffset, 0.375)

        var dismountWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayDismount.opcode, to: &dismountWriter.data)
        dismountWriter.writeUInt8(GatewayDismount.subOpcode)
        dismountWriter.writeUInt64(101)
        dismountWriter.writeInt32(9012)
        let dismountPacket = try GatewayWorldCodec.decodeAny(dismountWriter.data)
        guard case .dismount(let dismount) = dismountPacket else {
            return XCTFail("Expected dismount, got \(dismountPacket)")
        }
        XCTAssertEqual(dismount.riderGUID, 101)
        XCTAssertEqual(dismount.compositeEffectID, 9012)

        var observation = GatewayWorldObservation.empty
        observation.apply(mountPacket)
        XCTAssertEqual(observation.mountStates[101]?.mountGUID, 202)
        observation.apply(dismountPacket)
        XCTAssertNil(observation.mountStates[101])
        XCTAssertEqual(observation.lastDismount?.compositeEffectID, 9012)
    }

    func testAdditionalQuestObjectiveDecodersUseIntSubOpcodes() throws {
        func questPacket(_ sub: Int32, _ body: (inout PacketWriter) -> Void) throws -> GatewayWorldPacket {
            var writer = PacketWriter()
            GatewayWire.appendInt16(GatewayQuestObjectiveActivated.opcode, to: &writer.data)
            writer.writeInt32(sub)
            body(&writer)
            return try GatewayWorldCodec.decodeAny(writer.data)
        }

        let activated = try questPacket(GatewayQuestObjectiveActivated.subOpcode) { writer in
            writer.writeInt32(1201)
            writer.writeInt32(3)
            writer.writeInt32(10)
            writer.writeBool(false)
        }
        guard case .questObjectiveActivated(let update) = activated else {
            return XCTFail("Expected objective activation, got \(activated)")
        }
        XCTAssertEqual(update.requiredCount, 10)

        let progress = try questPacket(GatewayQuestObjectiveUpdate.subOpcode) { writer in
            writer.writeInt32(1201)
            writer.writeInt32(3)
            writer.writeInt32(6)
            writer.writeFloat(0.6)
            writer.writeBool(true)
            writer.writeInt32(51)
        }
        guard case .questObjectiveUpdate(let update) = progress else {
            return XCTFail("Expected objective update, got \(progress)")
        }
        XCTAssertEqual(update.currentCount, 6)
        XCTAssertEqual(update.completedPercentage, 0.6)
        XCTAssertTrue(update.silent)
        XCTAssertEqual(update.unknown6, 51)

        let complete = try questPacket(GatewayQuestObjectiveComplete.subOpcode) { writer in
            writer.writeInt32(1201)
            writer.writeInt32(3)
            writer.writeFloat(1)
            writer.writeInt32(8123)
            writer.writeBool(false)
        }
        guard case .questObjectiveComplete(let update) = complete else {
            return XCTFail("Expected objective completion, got \(complete)")
        }
        XCTAssertEqual(update.compositeEffectID, 8123)

        let failed = try questPacket(GatewayQuestObjectiveFailed.subOpcode) { writer in
            writer.writeInt32(1202)
            writer.writeInt32(4)
        }
        guard case .questObjectiveFailed(let update) = failed else {
            return XCTFail("Expected objective failure, got \(failed)")
        }
        XCTAssertEqual(update.objectiveID, 4)

        var observation = GatewayWorldObservation.empty
        for packet in [activated, progress, complete, failed] {
            observation.apply(packet)
        }
        let key = GatewayWorldObservation.QuestObjectiveKey(questID: 1201, objectiveID: 3)
        XCTAssertEqual(observation.questObjectiveRequirements[key], 10)
        XCTAssertEqual(observation.questObjectiveProgress[key]?.currentCount, 6)
        XCTAssertTrue(observation.completedQuestObjectiveIDs.contains(key))
        XCTAssertTrue(
            observation.failedQuestObjectiveIDs.contains(
                GatewayWorldObservation.QuestObjectiveKey(questID: 1202, objectiveID: 4)
            )
        )
        XCTAssertNil(observation.manaCurrent)
    }

    func testPetTrickNotificationUsesByteSubOpcode() throws {
        var writer = PacketWriter()
        GatewayWire.appendInt16(GatewayPetTrickNotification.opcode, to: &writer.data)
        writer.writeUInt8(GatewayPetTrickNotification.subOpcode)
        writer.writeInt32(77)
        writer.writeInt32(2)
        writer.writeInt32(515)
        writer.writeInt32(9200)
        writer.writeInt32(0)

        let packet = try GatewayWorldCodec.decodeAny(writer.data)
        guard case .petTrickNotification(let notification) = packet else {
            return XCTFail("Expected pet trick notification, got \(packet)")
        }
        XCTAssertEqual(notification.petID, 77)
        XCTAssertEqual(notification.notificationType, 2)
        XCTAssertEqual(notification.trickID, 515)
        XCTAssertEqual(notification.nameID, 9200)

        var observation = GatewayWorldObservation.empty
        observation.apply(packet)
        XCTAssertEqual(observation.lastPetTrickNotification?.trickID, 515)
        XCTAssertNil(observation.membershipInfo)
    }

    func testTopLevelScalarPacketsUseExactFieldOrder() throws {
        var shutdownWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayWorldShutdownNotice.opcode, to: &shutdownWriter.data)
        shutdownWriter.writeInt32(45)
        shutdownWriter.writeString("Maintenance")
        shutdownWriter.writeInt32(7)
        let shutdown = try GatewayWorldCodec.decodeAny(shutdownWriter.data)
        guard case .worldShutdownNotice(let notice) = shutdown else {
            return XCTFail("Expected shutdown notice, got \(shutdown)")
        }
        XCTAssertEqual(notice.timeRemaining, 45)
        XCTAssertEqual(notice.reason, "Maintenance")
        XCTAssertEqual(notice.reasonID, 7)

        var poiWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayPOIChange.opcode, to: &poiWriter.data)
        poiWriter.writeInt32(10)
        poiWriter.writeInt32(20)
        poiWriter.writeInt32(30)
        let poi = try GatewayWorldCodec.decodeAny(poiWriter.data)
        guard case .poiChange(let change) = poi else {
            return XCTFail("Expected POI change, got \(poi)")
        }
        XCTAssertEqual(change.nameID, 10)
        XCTAssertEqual(change.zoneID, 20)
        XCTAssertEqual(change.areaID, 30)

        var observation = GatewayWorldObservation.empty
        observation.apply(shutdown)
        observation.apply(poi)
        XCTAssertEqual(observation.worldShutdownNotice?.reasonID, 7)
        XCTAssertEqual(observation.lastPOIChange?.areaID, 30)
    }

    func testClientUpdateScalarPacketsUseShortSubOpcodes() throws {
        func clientPacket(
            _ subOpcode: Int16,
            _ body: (inout PacketWriter) -> Void
        ) throws -> GatewayWorldPacket {
            var writer = PacketWriter()
            GatewayWire.appendInt16(GatewayCoinCount.opcode, to: &writer.data)
            GatewayWire.appendInt16(subOpcode, to: &writer.data)
            body(&writer)
            return try GatewayWorldCodec.decodeAny(writer.data)
        }

        let coins = try clientPacket(GatewayCoinCount.subOpcode) { $0.writeInt32(12345) }
        guard case .coinCount(let count) = coins else {
            return XCTFail("Expected coin count, got \(coins)")
        }
        XCTAssertEqual(count.coins, 12345)

        let deletion = try clientPacket(GatewayItemDelete.subOpcode) { $0.writeInt32(77) }
        guard case .itemDelete(let deleted) = deletion else {
            return XCTFail("Expected item delete, got \(deletion)")
        }
        XCTAssertEqual(deleted.itemGUID, 77)

        let unequip = try clientPacket(GatewaySlotUnequip.subOpcode) { writer in
            writer.writeInt32(2)
            writer.writeInt32(3)
        }
        guard case .slotUnequipped(let slot) = unequip else {
            return XCTFail("Expected slot unequip, got \(unequip)")
        }
        XCTAssertEqual(slot.slot, 2)
        XCTAssertEqual(slot.profileID, 3)

        let itemUpdate = try clientPacket(GatewayItemUpdate.subOpcode) { writer in
            writer.writeInt32(1)
            writer.writeInt32(5)
            writer.writeInt32(-1)
            writer.writeInt32(2)
            writer.writeInt32(4)
            writer.writeInt64(999)
        }
        guard case .itemUpdate(let update) = itemUpdate else {
            return XCTFail("Expected item update, got \(itemUpdate)")
        }
        XCTAssertEqual(update.actionBarID, -1)
        XCTAssertEqual(update.rentalExpirationTime, 999)

        let activation = try clientPacket(GatewayImmediateActivationCheck.subOpcode) { writer in
            writer.writeInt32(1)
            writer.writeInt32(2)
            writer.writeInt32(3)
            writer.writeInt32(4)
            writer.writeInt32(5)
            writer.writeBool(true)
        }
        guard case .immediateActivationCheck(let check) = activation else {
            return XCTFail("Expected activation check, got \(activation)")
        }
        XCTAssertTrue(check.success)

        var observation = GatewayWorldObservation.empty
        for packet in [coins, deletion, unequip, itemUpdate, activation] {
            observation.apply(packet)
        }
        XCTAssertEqual(observation.coinCount, 12345)
        XCTAssertNil(observation.inventoryItemCounts[77])
        XCTAssertEqual(observation.inventoryItemCounts[1], 5)
        XCTAssertEqual(observation.lastUnequippedSlot?.profileID, 3)
        XCTAssertTrue(observation.lastImmediateActivationCheck?.success == true)
    }

    func testQuestScalarPacketsUseIntSubOpcodes() throws {
        func questPacket(
            _ subOpcode: Int32,
            _ body: (inout PacketWriter) -> Void
        ) throws -> GatewayWorldPacket {
            var writer = PacketWriter()
            GatewayWire.appendInt16(GatewayQuestAbandoned.opcode, to: &writer.data)
            writer.writeInt32(subOpcode)
            body(&writer)
            return try GatewayWorldCodec.decodeAny(writer.data)
        }

        let abandoned = try questPacket(GatewayQuestAbandoned.subOpcode) { writer in
            writer.writeInt32(1002)
            writer.writeBool(false)
        }
        guard case .questAbandoned(let quest) = abandoned else {
            return XCTFail("Expected quest abandoned, got \(abandoned)")
        }
        XCTAssertFalse(quest.literalFalse)

        let blocked = try questPacket(GatewayQuestEndBlocked.subOpcode) { writer in
            writer.writeUInt64(99)
            writer.writeInt32(1003)
            writer.writeInt32(88)
        }
        guard case .questEndBlocked(let questBlock) = blocked else {
            return XCTFail("Expected blocked quest end, got \(blocked)")
        }
        XCTAssertEqual(questBlock.textID, 88)

        var observation = GatewayWorldObservation.empty
        for packet in [abandoned, blocked] {
            observation.apply(packet)
        }
        XCTAssertTrue(observation.abandonedQuestIDs.contains(1002))
        XCTAssertEqual(observation.blockedQuestEndsByID[1003]?.textID, 88)
    }

    func testFriendScalarPacketsUseByteSubOpcodes() throws {
        func friendPacket(
            _ subOpcode: UInt8,
            _ body: (inout PacketWriter) -> Void
        ) throws -> GatewayWorldPacket {
            var writer = PacketWriter()
            GatewayWire.appendInt16(GatewayFriendOnline.opcode, to: &writer.data)
            writer.writeUInt8(subOpcode)
            body(&writer)
            return try GatewayWorldCodec.decodeAny(writer.data)
        }

        var onlineWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayFriendOnline.opcode, to: &onlineWriter.data)
        onlineWriter.writeUInt8(GatewayFriendOnline.subOpcode)
        onlineWriter.writeString("Old")
        onlineWriter.writeUInt64(1)
        onlineWriter.writeBool(true)
        let online = try GatewayWorldCodec.decodeAny(onlineWriter.data)

        let offline = try friendPacket(GatewayFriendOffline.subOpcode) {
            $0.writeUInt64(1)
        }
        guard case .friendOffline(let update) = offline else {
            return XCTFail("Expected friend offline, got \(offline)")
        }
        XCTAssertEqual(update.guid, 1)

        let remove = try friendPacket(GatewayFriendRemove.subOpcode) {
            $0.writeUInt64(2)
        }
        guard case .friendRemove(let update) = remove else {
            return XCTFail("Expected friend remove, got \(remove)")
        }
        XCTAssertEqual(update.guid, 2)

        let rename = try friendPacket(GatewayFriendRename.subOpcode) { writer in
            writer.writeString("Iris")
            writer.writeUInt64(3)
        }
        guard case .friendRename(let update) = rename else {
            return XCTFail("Expected friend rename, got \(rename)")
        }
        XCTAssertEqual(update.name, "Iris")

        var observation = GatewayWorldObservation.empty
        for packet in [online, rename, offline, remove] {
            observation.apply(packet)
        }
        XCTAssertNil(observation.friendPresence[1])
        XCTAssertEqual(observation.friendNames[3], "Iris")
    }

    func testChatAndAbilityScalarPacketsUseExactFieldOrder() throws {
        var areaWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayChatEnterArea.opcode, to: &areaWriter.data)
        GatewayWire.appendInt16(GatewayChatEnterArea.subOpcode, to: &areaWriter.data)
        areaWriter.writeInt32(55)
        let area = try GatewayWorldCodec.decodeAny(areaWriter.data)
        guard case .chatEnterArea(let entered) = area else {
            return XCTFail("Expected chat enter area, got \(area)")
        }
        XCTAssertEqual(entered.areaNameID, 55)

        var localizedWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayChatFromStringID.opcode, to: &localizedWriter.data)
        GatewayWire.appendInt16(GatewayChatFromStringID.subOpcode, to: &localizedWriter.data)
        localizedWriter.writeUInt64(0x1111_2222_3333_4444)
        localizedWriter.writeInt32(9001)
        localizedWriter.writeBool(false)
        localizedWriter.writeBool(true)
        localizedWriter.writeBool(true)
        localizedWriter.writeInt32(4)
        localizedWriter.writeUInt64(5)
        localizedWriter.writeUInt64(6)
        localizedWriter.writeInt32(7)
        let localized = try GatewayWorldCodec.decodeAny(localizedWriter.data)
        guard case .chatFromStringID(let chat) = localized else {
            return XCTFail("Expected localized chat, got \(localized)")
        }
        XCTAssertEqual(chat.stringID, 9001)
        XCTAssertEqual(chat.targetGUID, 5)
        XCTAssertEqual(chat.elapsedTime, 7)

        func abilityPacket(
            _ subOpcode: Int16,
            _ body: (inout PacketWriter) -> Void
        ) throws -> GatewayWorldPacket {
            var writer = PacketWriter()
            GatewayWire.appendInt16(GatewayAbilityFailed.opcode, to: &writer.data)
            GatewayWire.appendInt16(subOpcode, to: &writer.data)
            body(&writer)
            return try GatewayWorldCodec.decodeAny(writer.data)
        }

        let failure = try abilityPacket(GatewayAbilityFailed.subOpcode) { $0.writeInt32(9) }
        guard case .abilityFailed(let failed) = failure else {
            return XCTFail("Expected ability failure, got \(failure)")
        }
        XCTAssertEqual(failed.stringID, 9)

        let casting = try abilityPacket(GatewayAbilityStartCasting.subOpcode) { writer in
            writer.writeUInt64(101)
            writer.writeUInt64(0)
            writer.writeInt32(700)
            writer.writeInt32(8)
            writer.writeInt32(42)
            writer.writeFloat(1.25)
            writer.writeBool(true)
        }
        guard case .abilityStartCasting(let cast) = casting else {
            return XCTFail("Expected ability start casting, got \(casting)")
        }
        XCTAssertEqual(cast.abilityID, 42)
        XCTAssertEqual(cast.actionTime, 1.25)
        XCTAssertTrue(cast.hasActionProgress)

        var observation = GatewayWorldObservation.empty
        for packet in [area, localized, failure, casting] {
            observation.apply(packet)
        }
        XCTAssertEqual(observation.lastEnteredAreaNameID, 55)
        XCTAssertEqual(observation.lastChatFromStringID?.stringID, 9001)
        XCTAssertEqual(observation.lastAbilityFailure?.stringID, 9)
        XCTAssertEqual(observation.castingAbilities[101]?.abilityID, 42)
    }

    func testScalarPlayerUpdatePacketsUseShortSubOpcodes() throws {
        func playerPacket(
            _ subOpcode: Int16,
            _ body: (inout PacketWriter) -> Void
        ) throws -> GatewayWorldPacket {
            var writer = PacketWriter()
            GatewayWire.appendInt16(GatewayWalkAnimationUpdate.opcode, to: &writer.data)
            GatewayWire.appendInt16(subOpcode, to: &writer.data)
            body(&writer)
            return try GatewayWorldCodec.decodeAny(writer.data)
        }

        let walk = try playerPacket(GatewayWalkAnimationUpdate.subOpcode) { writer in
            writer.writeUInt64(11)
            writer.writeInt32(700)
        }
        guard case .walkAnimation(let update) = walk else {
            return XCTFail("Expected walk animation, got \(walk)")
        }
        XCTAssertEqual(update.animation, 700)

        let idle = try playerPacket(GatewayIdleAnimationUpdate.subOpcode) { writer in
            writer.writeUInt64(11)
            writer.writeInt32(701)
        }
        guard case .idleAnimation(let update) = idle else {
            return XCTFail("Expected idle animation, got \(idle)")
        }
        XCTAssertEqual(update.animationID, 701)

        let queued = try playerPacket(GatewayQueuedAnimation.subOpcode) { writer in
            writer.writeUInt64(11)
            writer.writeInt32(22)
            writer.writeInt32(2)
            writer.writeFloat(1.5)
            writer.writeFloat(0.25)
            writer.writeFloat(3.75)
            writer.writeBool(true)
            writer.writeBool(false)
            writer.writeBool(true)
        }
        guard case .queuedAnimation(let update) = queued else {
            return XCTFail("Expected queued animation, got \(queued)")
        }
        XCTAssertEqual(update.loopCount, 2)
        XCTAssertTrue(update.useAnimationPriority)

        let animation = try playerPacket(GatewaySetAnimation.subOpcode) { writer in
            writer.writeUInt64(12)
            writer.writeInt32(31)
            writer.writeInt32(-2)
            writer.writeUInt8(7)
        }
        guard case .setAnimation(let update) = animation else {
            return XCTFail("Expected set animation, got \(animation)")
        }
        XCTAssertEqual(update.unknown, -2)
        XCTAssertEqual(update.flags, 7)

        let addTag = try playerPacket(GatewayAddCompositeEffectTag.subOpcode) { writer in
            writer.writeUInt64(13)
            writer.writeInt32(8)
            writer.writeInt32(900)
            writer.writeUInt64(14)
            writer.writeInt32(-1)
            writer.writeInt32(-2)
        }
        guard case .addCompositeEffectTag(let update) = addTag else {
            return XCTFail("Expected composite tag addition, got \(addTag)")
        }
        XCTAssertEqual(update.sourceGUID, 14)
        XCTAssertEqual(update.unknown2, -2)

        let removeTag = try playerPacket(GatewayRemoveCompositeEffectTag.subOpcode) { writer in
            writer.writeUInt64(13)
            writer.writeInt32(8)
        }
        guard case .removeCompositeEffectTag(let update) = removeTag else {
            return XCTFail("Expected composite tag removal, got \(removeTag)")
        }
        XCTAssertEqual(update.tagID, 8)

        let enable = try playerPacket(GatewayCompositeEffectsEnabled.subOpcode) {
            $0.writeBool(true)
        }
        guard case .compositeEffectsEnabled(let update) = enable else {
            return XCTFail("Expected composite effects toggle, got \(enable)")
        }
        XCTAssertTrue(update.enabled)

        var observation = GatewayWorldObservation.empty
        for packet in [walk, idle, queued, animation, addTag, removeTag, enable] {
            observation.apply(packet)
        }
        XCTAssertEqual(observation.walkAnimations[11], 700)
        XCTAssertEqual(observation.idleAnimations[11], 701)
        XCTAssertEqual(observation.queuedAnimations[11]?.endTime, 3.75)
        XCTAssertEqual(observation.setAnimations[12]?.flags, 7)
        XCTAssertTrue(observation.compositeEffectTags[13]?.isEmpty == true)
        XCTAssertEqual(observation.compositeEffectsEnabled, true)
    }

    /// Packets whose C# `Serialize()` delegates to nested codecs are not decoded
    /// until those nested codecs exist. They must still preserve their bytes and
    /// must never populate decoded observation state.
    func testNestedSerializerPacketsRemainRawAndSetNoDecodedState() throws {
        func rawPacket(_ opcode: Int16, _ build: (inout PacketWriter) -> Void) -> Data {
            var writer = PacketWriter()
            GatewayWire.appendInt16(opcode, to: &writer.data)
            build(&writer)
            return writer.data
        }

        let cases: [(String, Data)] = [
            ("38/16", rawPacket(38) { writer in
                GatewayWire.appendInt16(16, to: &writer.data)
                writer.writeInt32(9)
            }),
            ("49/1", rawPacket(49) { writer in
                writer.writeInt32(1)
                writer.writeInt32(1001)
            }),
            ("49/7", rawPacket(49) { writer in
                writer.writeInt32(7)
                writer.writeInt32(1001)
            }),
            ("49/3", rawPacket(49) { writer in
                writer.writeInt32(3)
                writer.writeBool(true)
            }),
            ("49/13", rawPacket(49) { writer in
                writer.writeInt32(13)
                writer.writeUInt64(99)
            }),
            ("74/9", rawPacket(74) { writer in
                writer.writeUInt8(9)
                writer.writeString("Bloom")
                writer.writeUInt64(3)
            }),
            ("36/5", rawPacket(36) { writer in
                GatewayWire.appendInt16(5, to: &writer.data)
                writer.writeInt32(2)
            })
        ]

        for (route, data) in cases {
            let packet = try GatewayWorldCodec.decodeAny(data)
            guard case .mapped(_, let subOpcode, let names, let payload) = packet else {
                return XCTFail("Expected raw-preserving mapped packet for \(route), got \(packet)")
            }
            XCTAssertFalse(names.isEmpty, "Expected catalog route for \(route)")
            XCTAssertEqual(payload, data)
            XCTAssertNotNil(subOpcode)

            var observation = GatewayWorldObservation.empty
            observation.apply(packet)
            XCTAssertEqual(observation.lastMappedPayload, data)
            XCTAssertFalse(observation.mappedPacketCounts.isEmpty)
            XCTAssertTrue(observation.effectTags.isEmpty)
            XCTAssertTrue(observation.abandonedQuestIDs.isEmpty)
            XCTAssertTrue(observation.blockedQuestEndsByID.isEmpty)
            XCTAssertTrue(observation.friendNames.isEmpty)
            XCTAssertTrue(observation.castingAbilities.isEmpty)
            XCTAssertTrue(observation.walkAnimations.isEmpty)
            XCTAssertTrue(observation.setAnimations.isEmpty)
        }
    }

    func testAdditionalScalarOnlyPacketsUseExactFieldOrder() throws {
        var petWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayPetUtilityNotification.opcode, to: &petWriter.data)
        petWriter.writeUInt8(GatewayPetUtilityNotification.subOpcode)
        petWriter.writeInt32(201)
        petWriter.writeInt32(4)
        petWriter.writeInt32(12)
        petWriter.writeInt32(1)
        petWriter.writeInt32(2)
        petWriter.writeInt32(3)
        let pet = try GatewayWorldCodec.decodeAny(petWriter.data)
        guard case .petUtilityNotification(let notification) = pet else {
            return XCTFail("Expected pet utility notification, got \(pet)")
        }
        XCTAssertEqual(notification.petID, 201)
        XCTAssertEqual(notification.notificationType, 4)
        XCTAssertEqual(notification.groomDurationSeconds, 12)
        XCTAssertEqual(notification.unknown4, 1)
        XCTAssertEqual(notification.unknown5, 2)
        XCTAssertEqual(notification.unknown6, 3)

        var sourcesWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayInGamePurchasePaymentSources.opcode, to: &sourcesWriter.data)
        GatewayWire.appendInt16(GatewayInGamePurchasePaymentSources.subOpcode, to: &sourcesWriter.data)
        sourcesWriter.writeBool(true)
        sourcesWriter.writeBool(false)
        let sources = try GatewayWorldCodec.decodeAny(sourcesWriter.data)
        guard case .inGamePurchasePaymentSources(let payment) = sources else {
            return XCTFail("Expected payment sources, got \(sources)")
        }
        XCTAssertTrue(payment.sms)
        XCTAssertFalse(payment.paypal)

        var marketWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayInGamePurchaseMarketplace.opcode, to: &marketWriter.data)
        GatewayWire.appendInt16(GatewayInGamePurchaseMarketplace.subOpcode, to: &marketWriter.data)
        marketWriter.writeBool(true)
        let market = try GatewayWorldCodec.decodeAny(marketWriter.data)
        guard case .inGamePurchaseMarketplace(let marketplace) = market else {
            return XCTFail("Expected marketplace packet, got \(market)")
        }
        XCTAssertTrue(marketplace.enabled)

        var targetWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayObjectiveTargetUpdate.opcode, to: &targetWriter.data)
        targetWriter.writeUInt8(GatewayObjectiveTargetUpdate.subOpcode)
        targetWriter.writeBool(true)
        targetWriter.writeUInt64(5001)
        targetWriter.writeInt32(2)
        targetWriter.writeUInt64(88)
        targetWriter.writeInt32(900)
        targetWriter.writeFloat(1.25)
        targetWriter.writeFloat(2.5)
        targetWriter.writeFloat(3.75)
        targetWriter.writeFloat(1)
        targetWriter.writeInt32(2)
        let target = try GatewayWorldCodec.decodeAny(targetWriter.data)
        guard case .objectiveTargetUpdate(let update) = target else {
            return XCTFail("Expected objective target update, got \(target)")
        }
        XCTAssertTrue(update.active)
        XCTAssertEqual(update.taskID ?? 0, 5001)
        XCTAssertEqual(update.guid ?? 0, 88)
        XCTAssertEqual(update.nameID ?? 0, 900)
        XCTAssertEqual(update.positionX ?? 0, 1.25)
        XCTAssertEqual(update.positionW ?? 0, 1)

        var inactiveWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayObjectiveTargetUpdate.opcode, to: &inactiveWriter.data)
        inactiveWriter.writeUInt8(GatewayObjectiveTargetUpdate.subOpcode)
        inactiveWriter.writeBool(false)
        let inactive = try GatewayWorldCodec.decodeAny(inactiveWriter.data)
        guard case .objectiveTargetUpdate(let clearedTarget) = inactive else {
            return XCTFail("Expected inactive objective target, got \(inactive)")
        }
        XCTAssertFalse(clearedTarget.active)
        XCTAssertNil(clearedTarget.taskID)
        XCTAssertNil(clearedTarget.targetType)

        var clearWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayObjectiveClientClear.opcode, to: &clearWriter.data)
        clearWriter.writeUInt8(GatewayObjectiveClientClear.subOpcode)
        clearWriter.writeInt32(-7)
        let clear = try GatewayWorldCodec.decodeAny(clearWriter.data)
        guard case .objectiveClientClear(let cleared) = clear else {
            return XCTFail("Expected objective client clear, got \(clear)")
        }
        XCTAssertEqual(cleared.unknown, -7)

        var observation = GatewayWorldObservation.empty
        for packet in [pet, sources, market, inactive, target, clear] {
            observation.apply(packet)
        }
        XCTAssertEqual(observation.lastPetUtilityNotification?.petID, 201)
        XCTAssertTrue(observation.inGamePurchasePaymentSources?.sms == true)
        XCTAssertEqual(observation.inGamePurchaseMarketplaceEnabled, true)
        XCTAssertEqual(observation.objectiveTargetUpdate?.guid ?? 0, 88)
        XCTAssertEqual(observation.lastClearedObjectiveUnknown, -7)
    }

    func testAdditionalTradePacketsUseExactCSharpFieldOrder() throws {
        func writeHeader(_ sub: UInt8, to writer: inout PacketWriter) {
            GatewayWire.appendInt16(GatewayTradeCoinCount.opcode, to: &writer.data)
            writer.writeUInt8(sub)
        }

        var endWriter = PacketWriter()
        writeHeader(GatewayTradeEndSession.subOpcode, to: &endWriter)
        endWriter.writeInt32(701)
        let end = try GatewayWorldCodec.decodeAny(endWriter.data)
        guard case .tradeEndSession(let ended) = end else {
            return XCTFail("Expected trade end session, got \(end)")
        }
        XCTAssertEqual(ended.sessionID, 701)

        var addWriter = PacketWriter()
        writeHeader(GatewayTradeAddItem.subOpcode, to: &addWriter)
        addWriter.writeInt32(702)
        addWriter.writeInt32(4)
        addWriter.writeBool(true)
        addWriter.writeInt32(9001)
        addWriter.writeInt32(17)
        addWriter.writeInt32(44)
        addWriter.writeInt32(5)
        addWriter.writeInt32(6)
        addWriter.writeInt32(Int32.max)
        addWriter.writeBool(false)
        addWriter.writeInt32(2)
        let add = try GatewayWorldCodec.decodeAny(addWriter.data)
        guard case .tradeAddItem(let added) = add else {
            return XCTFail("Expected trade add item, got \(add)")
        }
        XCTAssertEqual(added.sessionID, 702)
        XCTAssertEqual(added.revision, 4)
        XCTAssertTrue(added.isMine)
        XCTAssertEqual(added.item.definition, 9001)
        XCTAssertEqual(added.item.tint, 17)
        XCTAssertEqual(added.item.id, 44)
        XCTAssertEqual(added.item.count, 5)
        XCTAssertEqual(added.item.consumedCount, 6)
        XCTAssertEqual(added.item.lastCastTime, Int32.max)
        XCTAssertFalse(added.item.rentalPlaceholder)
        XCTAssertEqual(added.item.abilityCount, 2)

        var countWriter = PacketWriter()
        writeHeader(GatewayTradeItemCount.subOpcode, to: &countWriter)
        countWriter.writeInt32(703)
        countWriter.writeInt32(8)
        countWriter.writeBool(false)
        countWriter.writeInt32(55)
        countWriter.writeInt32(12)
        let count = try GatewayWorldCodec.decodeAny(countWriter.data)
        guard case .tradeItemCount(let counted) = count else {
            return XCTFail("Expected trade item count, got \(count)")
        }
        XCTAssertEqual(counted.sessionID, 703)
        XCTAssertEqual(counted.itemInstanceID, 55)
        XCTAssertEqual(counted.offeredTotal, 12)

        var lockWriter = PacketWriter()
        writeHeader(GatewayTradeLock.subOpcode, to: &lockWriter)
        lockWriter.writeInt32(704)
        lockWriter.writeBool(true)
        let lock = try GatewayWorldCodec.decodeAny(lockWriter.data)
        guard case .tradeLock(let locked) = lock else {
            return XCTFail("Expected trade lock, got \(lock)")
        }
        XCTAssertEqual(locked.sessionID, 704)
        XCTAssertTrue(locked.locked)

        var confirmWriter = PacketWriter()
        writeHeader(GatewayTradeConfirm.subOpcode, to: &confirmWriter)
        confirmWriter.writeInt32(705)
        let confirm = try GatewayWorldCodec.decodeAny(confirmWriter.data)
        guard case .tradeConfirm(let confirmed) = confirm else {
            return XCTFail("Expected trade confirm, got \(confirm)")
        }
        XCTAssertEqual(confirmed.sessionID, 705)

        var observation = GatewayWorldObservation.empty
        for packet in [end, add, count, lock, confirm] {
            observation.apply(packet)
        }
        XCTAssertEqual(observation.lastEndedTradeSessionID, 701)
        XCTAssertEqual(observation.lastTradeAddItem?.item.definition, 9001)
        XCTAssertEqual(observation.lastTradeItemCount?.offeredTotal, 12)
        XCTAssertEqual(observation.lastTradeLock?.sessionID, 704)
        XCTAssertTrue(observation.confirmedTradeSessionIDs.contains(705))
        XCTAssertTrue(observation.positions.isEmpty)
        XCTAssertTrue(observation.chatMessages.isEmpty)
        XCTAssertNil(observation.hitpointsCurrent)
    }

    func testTradeHandshakePacketsUseVerifiedNameDataOrder() throws {
        let inviter = GatewayName(
            firstNameID: 11, lastNamePrefixID: 12, lastNameSuffixID: 13,
            firstName: "Ada", lastName: "Meridian"
        )
        let partner = GatewayName(
            firstNameID: 21, lastNamePrefixID: 22, lastNameSuffixID: 23,
            firstName: "Lin", lastName: ""
        )
        let rejecter = GatewayName(
            firstNameID: 31, lastNamePrefixID: 32, lastNameSuffixID: 33,
            firstName: "Rin", lastName: "Vale"
        )

        func header(_ sub: UInt8, to writer: inout PacketWriter) {
            GatewayWire.appendInt16(GatewayTradeInvite.opcode, to: &writer.data)
            writer.writeUInt8(sub)
        }

        var inviteWriter = PacketWriter()
        header(GatewayTradeInvite.subOpcode, to: &inviteWriter)
        inviter.append(to: &inviteWriter)
        inviteWriter.writeUInt64(0x1122_3344_5566_7788)
        inviteWriter.writeInt32(710)
        let invite = try GatewayWorldCodec.decodeAny(inviteWriter.data)
        guard case .tradeInvite(let decodedInvite) = invite else {
            return XCTFail("Expected trade invite, got \(invite)")
        }
        XCTAssertEqual(decodedInvite.inviterName, inviter)
        XCTAssertEqual(decodedInvite.inviterGUID, 0x1122_3344_5566_7788)
        XCTAssertEqual(decodedInvite.sessionID, 710)

        var startWriter = PacketWriter()
        header(GatewayTradeStartSession.subOpcode, to: &startWriter)
        startWriter.writeUInt64(0x8877_6655_4433_2211)
        partner.append(to: &startWriter)
        startWriter.writeInt32(711)
        let start = try GatewayWorldCodec.decodeAny(startWriter.data)
        guard case .tradeStartSession(let decodedStart) = start else {
            return XCTFail("Expected trade start session, got \(start)")
        }
        XCTAssertEqual(decodedStart.partnerGUID, 0x8877_6655_4433_2211)
        XCTAssertEqual(decodedStart.partnerName, partner)
        XCTAssertEqual(decodedStart.sessionID, 711)

        var rejectedWriter = PacketWriter()
        header(GatewayTradeRejected.subOpcode, to: &rejectedWriter)
        rejecter.append(to: &rejectedWriter)
        let rejected = try GatewayWorldCodec.decodeAny(rejectedWriter.data)
        guard case .tradeRejected(let decodedRejection) = rejected else {
            return XCTFail("Expected trade rejection, got \(rejected)")
        }
        XCTAssertEqual(decodedRejection.rejectingPlayer, rejecter)

        var observation = GatewayWorldObservation.empty
        for packet in [invite, start, rejected] {
            observation.apply(packet)
        }
        XCTAssertEqual(observation.tradeInvites[710]?.inviterName, inviter)
        XCTAssertEqual(observation.lastTradeStartSession?.sessionID, 711)
        XCTAssertEqual(observation.lastTradeRejection?.rejectingPlayer, rejecter)
        XCTAssertNil(observation.lastTradeMessage)
        XCTAssertTrue(observation.confirmedTradeSessionIDs.isEmpty)
    }

    func testStoreBundlesDecoderMatchesNestedCSharpFieldOrder() throws {
        var writer = PacketWriter()
        GatewayWire.appendInt16(GatewayInGamePurchaseStoreBundles.opcode, to: &writer.data)
        GatewayWire.appendInt16(GatewayInGamePurchaseStoreBundles.subOpcode, to: &writer.data)
        writer.writeInt32(GatewayInGamePurchaseStoreBundles.bundlesOpcode)
        writer.writeInt32(7)

        // StoreDefinition.Serialize
        writer.writeInt32(7)
        writer.writeInt32(8001)
        writer.writeInt32(8002)
        writer.writeString("StoreImage.dds")
        writer.writeString("FFFFFFFF")
        writer.writeInt32(1)
        writer.writeInt32(9001)

        // MarketingBundleDefinition.Serialize
        writer.writeInt32(1001)
        writer.writeInt32(1002)
        writer.writeInt32(1003)
        writer.writeInt32(2)
        writer.writeString("Bundle.dds")
        writer.writeString("11223344")
        writer.writeBool(true)
        writer.writeString("TintGroup")
        writer.writeInt32(3)
        writer.writeInt32(499)
        writer.writeInt32(0)
        writer.writeInt32(299)
        writer.writeInt32(11)
        writer.writeInt64(1_700_000_000)
        writer.writeInt64(1_800_000_000)
        writer.writeInt32(77)
        writer.writeBool(false)
        writer.writeInt64(1_700_000_000)
        writer.writeInt64(1_800_000_000)
        writer.writeInt32(1)
        writer.writeInt32(2)
        writer.writeInt32(50001)
        writer.writeInt32(50002)
        writer.writeString("TintOverride")

        // StoreBundleDefinition.Serialize
        writer.writeInt32(7)
        writer.writeInt32(12)
        writer.writeBool(true)
        writer.writeInt32(4)
        writer.writeInt32(5)
        writer.writeInt32(6)
        writer.writeInt32(1)
        writer.writeInt32(50003)
        writer.writeInt32(99)
        writer.writeInt32(0)
        writer.writeInt32(0)
        writer.writeUInt8(3)
        writer.writeBool(true)
        writer.writeBool(false)

        // AppStoreBundleDefinition.Serialize
        writer.writeInt32(10)
        writer.writeInt32(20)
        writer.writeBool(true)
        writer.writeInt32(2)
        writer.writeInt32(399)
        writer.writeInt32(199)
        writer.writeBool(false)
        writer.writeBool(true)
        writer.writeInt32(1)
        writer.writeInt32(1234)

        let packet = try GatewayWorldCodec.decodeAny(writer.data)
        guard case .inGamePurchaseStoreBundles(let bundles) = packet else {
            return XCTFail("Expected store bundles, got \(packet)")
        }
        XCTAssertEqual(bundles.storeID, 7)
        XCTAssertEqual(bundles.store.nameID, 8001)
        XCTAssertEqual(bundles.store.descriptionID, 8002)
        XCTAssertEqual(bundles.store.image.image, "StoreImage.dds")
        XCTAssertEqual(bundles.store.image.tint, "FFFFFFFF")
        let bundle = try XCTUnwrap(bundles.store.bundles[9001])
        XCTAssertEqual(bundle.bundle.marketing.id, 1001)
        XCTAssertEqual(bundle.bundle.marketing.image.tint, "11223344")
        XCTAssertTrue(bundle.bundle.marketing.isTintable)
        XCTAssertEqual(bundle.bundle.marketing.tintGroup, "TintGroup")
        XCTAssertEqual(bundle.bundle.marketing.launchTimeSeconds, 1_700_000_000)
        XCTAssertEqual(bundle.bundle.marketing.repeatedExpireTimeSeconds, 1_800_000_000)
        XCTAssertEqual(bundle.bundle.marketing.entries.first?.quantity, 2)
        XCTAssertEqual(bundle.bundle.marketing.entries.first?.imageTintOverride, "TintOverride")
        XCTAssertEqual(bundle.bundle.storeID, 7)
        XCTAssertEqual(bundle.bundle.skuID, 50003)
        XCTAssertEqual(bundle.bundle.termsAndConditionsID, 3)
        XCTAssertTrue(bundle.bundle.isNew)
        XCTAssertFalse(bundle.bundle.isViewOnly)
        XCTAssertTrue(bundle.isMembersOnly)
        XCTAssertEqual(bundle.membersOnlyPrice, 399)
        XCTAssertFalse(bundle.isMerchantOnly)
        XCTAssertTrue(bundle.isLimitedTime)
        XCTAssertEqual(bundle.previewAnimID, 1234)

        var observation = GatewayWorldObservation.empty
        observation.apply(packet)
        XCTAssertEqual(observation.inGamePurchaseStoreBundles?.storeID, 7)
        XCTAssertEqual(observation.inGamePurchaseStoreBundles?.store.bundles.count, 1)
        XCTAssertTrue(observation.positions.isEmpty)

        var badCount = PacketWriter()
        GatewayWire.appendInt16(GatewayInGamePurchaseStoreBundles.opcode, to: &badCount.data)
        GatewayWire.appendInt16(GatewayInGamePurchaseStoreBundles.subOpcode, to: &badCount.data)
        badCount.writeInt32(GatewayInGamePurchaseStoreBundles.bundlesOpcode)
        badCount.writeInt32(7)
        badCount.writeInt32(7)
        badCount.writeInt32(8001)
        badCount.writeInt32(8002)
        badCount.writeString("StoreImage.dds")
        badCount.writeString("FFFFFFFF")
        badCount.writeInt32(-1)
        XCTAssertThrowsError(try GatewayWorldCodec.decodeAny(badCount.data))
    }

    func testAdditionalStorePacketsUseExactCSharpFieldOrder() throws {
        func writeHeader(_ sub: Int16, to writer: inout PacketWriter) {
            GatewayWire.appendInt16(66, to: &writer.data)
            GatewayWire.appendInt16(sub, to: &writer.data)
        }

        var groupsWriter = PacketWriter()
        writeHeader(6, to: &groupsWriter)
        groupsWriter.writeInt32(1)
        groupsWriter.writeInt32(5)
        groupsWriter.writeInt32(5)
        groupsWriter.writeInt32(2)
        groupsWriter.writeInt32(11)
        groupsWriter.writeInt32(12)
        let groupsPacket = try GatewayWorldCodec.decodeAny(groupsWriter.data)
        guard case .storeCategoryGroups(let groups) = groupsPacket else {
            return XCTFail("Expected store category groups, got \(groupsPacket)")
        }
        XCTAssertEqual(groups.groups[5]?.categoryIDs, [11, 12])

        var categoriesWriter = PacketWriter()
        writeHeader(7, to: &categoriesWriter)
        categoriesWriter.writeInt32(1)
        categoriesWriter.writeInt32(20)
        categoriesWriter.writeInt32(20)
        categoriesWriter.writeInt32(700)
        categoriesWriter.writeString("Category.dds")
        categoriesWriter.writeString("FFFFFFFF")
        categoriesWriter.writeInt32(3)
        categoriesWriter.writeInt32(4)
        categoriesWriter.writeInt32(5)
        categoriesWriter.writeBool(true)
        let categoriesPacket = try GatewayWorldCodec.decodeAny(categoriesWriter.data)
        guard case .storeCategories(let categories) = categoriesPacket else {
            return XCTFail("Expected store categories, got \(categoriesPacket)")
        }
        XCTAssertTrue(categories.tree.sorted)
        let categoryNode = try XCTUnwrap(categories.tree.categories[20])
        XCTAssertEqual(categoryNode.category.image.image, "Category.dds")
        XCTAssertEqual(categoryNode.parentID, 3)
        XCTAssertEqual(categoryNode.count, 4)
        XCTAssertEqual(categoryNode.displayOrder, 5)

        var bundleGroupsWriter = PacketWriter()
        writeHeader(9, to: &bundleGroupsWriter)
        bundleGroupsWriter.writeInt32(1)
        bundleGroupsWriter.writeInt32(30)
        bundleGroupsWriter.writeInt32(30)
        bundleGroupsWriter.writeInt32(800)
        bundleGroupsWriter.writeInt32(801)
        bundleGroupsWriter.writeString("")
        bundleGroupsWriter.writeString("")
        bundleGroupsWriter.writeBool(true)
        bundleGroupsWriter.writeInt32(2)
        bundleGroupsWriter.writeInt32(1)
        bundleGroupsWriter.writeInt32(900)
        bundleGroupsWriter.writeInt32(900)
        bundleGroupsWriter.writeInt32(7)
        let bundleGroupsPacket = try GatewayWorldCodec.decodeAny(bundleGroupsWriter.data)
        guard case .storeBundleGroups(let bundleGroups) = bundleGroupsPacket else {
            return XCTFail("Expected store bundle groups, got \(bundleGroupsPacket)")
        }
        XCTAssertTrue(bundleGroups.groups[30]?.isExclusive == true)
        XCTAssertEqual(bundleGroups.groups[30]?.status, 2)
        XCTAssertEqual(bundleGroups.groups[30]?.entries[900]?.displayOrder, 7)

        var walletWriter = PacketWriter()
        writeHeader(11, to: &walletWriter)
        walletWriter.writeInt32(0)
        walletWriter.writeBool(false)
        walletWriter.writeInt32(12_345)
        walletWriter.writeInt32(4)
        walletWriter.writeString("USD")
        walletWriter.writeString("")
        walletWriter.writeBool(true)
        let walletPacket = try GatewayWorldCodec.decodeAny(walletWriter.data)
        guard case .storeWalletInfo(let wallet) = walletPacket else {
            return XCTFail("Expected store wallet info, got \(walletPacket)")
        }
        XCTAssertEqual(wallet.errorCode, 0)
        XCTAssertEqual(wallet.wallet.stationCash, 12_345)
        XCTAssertEqual(wallet.wallet.currencyCode, "USD")
        XCTAssertTrue(wallet.wallet.international)

        var subscriptionsWriter = PacketWriter()
        writeHeader(23, to: &subscriptionsWriter)
        subscriptionsWriter.writeInt32(1)
        subscriptionsWriter.writeString("en_US")
        subscriptionsWriter.writeInt32(1)
        subscriptionsWriter.writeString("premium")
        subscriptionsWriter.writeString("Premium")
        subscriptionsWriter.writeString("Premium description")
        subscriptionsWriter.writeString("Preview legal")
        subscriptionsWriter.writeString("Marketing legal")
        subscriptionsWriter.writeString("Product legal")
        subscriptionsWriter.writeInt32(999)
        subscriptionsWriter.writeInt32(499)
        subscriptionsWriter.writeInt32(42)
        subscriptionsWriter.writeBool(true)
        let subscriptionsPacket = try GatewayWorldCodec.decodeAny(subscriptionsWriter.data)
        guard case .subscriptionProducts(let subscriptions) = subscriptionsPacket else {
            return XCTFail("Expected subscription products, got \(subscriptionsPacket)")
        }
        XCTAssertEqual(subscriptions.locale, "en_US")
        XCTAssertEqual(subscriptions.membershipSKUs.first?.sku, "premium")
        XCTAssertEqual(subscriptions.membershipSKUs.first?.priceStationCash, 499)
        XCTAssertTrue(subscriptions.membershipSKUs.first?.isVatTaxable == true)

        var errorSubscriptionsWriter = PacketWriter()
        writeHeader(23, to: &errorSubscriptionsWriter)
        errorSubscriptionsWriter.writeInt32(2)
        errorSubscriptionsWriter.writeString("en_US")
        let errorSubscriptionsPacket = try GatewayWorldCodec.decodeAny(errorSubscriptionsWriter.data)
        guard case .subscriptionProducts(let errorSubscriptions) = errorSubscriptionsPacket else {
            return XCTFail("Expected subscription products error, got \(errorSubscriptionsPacket)")
        }
        XCTAssertTrue(errorSubscriptions.membershipSKUs.isEmpty)

        var salesWriter = PacketWriter()
        writeHeader(40, to: &salesWriter)
        salesWriter.writeInt32(1)
        salesWriter.writeInt32(1001)
        salesWriter.writeInt32(1002)
        salesWriter.writeInt32(1003)
        salesWriter.writeInt32(1004)
        salesWriter.writeInt32(1005)
        salesWriter.writeInt32(600)
        salesWriter.writeInt32(7)
        salesWriter.writeBool(true)
        let salesPacket = try GatewayWorldCodec.decodeAny(salesWriter.data)
        guard case .saleDisplayUpdate(let sales) = salesPacket else {
            return XCTFail("Expected sale display update, got \(salesPacket)")
        }
        XCTAssertEqual(sales.sales.first?.id, 1001)
        XCTAssertEqual(sales.sales.first?.secondsLeft, 600)
        XCTAssertTrue(sales.sales.first?.isMembership == true)

        var observation = GatewayWorldObservation.empty
        for packet in [
            groupsPacket,
            categoriesPacket,
            bundleGroupsPacket,
            walletPacket,
            subscriptionsPacket,
            salesPacket
        ] {
            observation.apply(packet)
        }
        XCTAssertEqual(observation.storeCategoryGroups?[5]?.categoryIDs, [11, 12])
        let observedCategoryNode = try XCTUnwrap(observation.storeCategoryTree?.categories[20])
        XCTAssertEqual(observedCategoryNode.category.nameID, 700)
        XCTAssertEqual(observation.storeBundleGroups?[30]?.entries[900]?.storeBundleID, 900)
        XCTAssertEqual(observation.storeWalletInfo?.stationCash, 12_345)
        XCTAssertEqual(observation.subscriptionProducts?.membershipSKUs.count, 1)
        XCTAssertEqual(observation.saleDisplays?.first?.unknown, 7)
        XCTAssertTrue(observation.positions.isEmpty)

        var badCount = PacketWriter()
        writeHeader(40, to: &badCount)
        badCount.writeInt32(-1)
        XCTAssertThrowsError(try GatewayWorldCodec.decodeAny(badCount.data))
    }

    func testAdditionalCommerceResponsesUseExactCSharpFieldOrder() throws {
        func writeHeader(_ sub: Int16, to writer: inout PacketWriter) {
            GatewayWire.appendInt16(66, to: &writer.data)
            GatewayWire.appendInt16(sub, to: &writer.data)
        }

        var previewWriter = PacketWriter()
        writeHeader(2, to: &previewWriter)
        previewWriter.writeInt32(91)
        previewWriter.writeInt32(5)
        previewWriter.writeInt32(120)
        previewWriter.writeInt32(880)
        let previewPacket = try GatewayWorldCodec.decodeAny(previewWriter.data)
        guard case .storePreviewOrder(let preview) = previewPacket else {
            return XCTFail("Expected store preview order, got \(previewPacket)")
        }
        XCTAssertEqual(preview.orderTrackingID, 91)
        XCTAssertEqual(preview.result, 5)
        XCTAssertEqual(preview.discount, 120)
        XCTAssertEqual(preview.total, 880)

        var placeWriter = PacketWriter()
        writeHeader(4, to: &placeWriter)
        placeWriter.writeInt32(92)
        placeWriter.writeInt32(8)
        placeWriter.writeString("order-92")
        placeWriter.writeInt32(130)
        placeWriter.writeInt32(870)
        let placePacket = try GatewayWorldCodec.decodeAny(placeWriter.data)
        guard case .storePlaceOrder(let place) = placePacket else {
            return XCTFail("Expected store place order, got \(placePacket)")
        }
        XCTAssertEqual(place.orderID, "order-92")
        XCTAssertEqual(place.result, 8)
        XCTAssertEqual(place.total, 870)

        var currencyWriter = PacketWriter()
        writeHeader(17, to: &currencyWriter)
        currencyWriter.writeInt32(1)
        currencyWriter.writeString("en_US")
        currencyWriter.writeInt32(1)
        currencyWriter.writeUInt32(840)
        currencyWriter.writeString("USD")
        currencyWriter.writeString("$")
        currencyWriter.writeString(".")
        currencyWriter.writeString("US Dollar")
        currencyWriter.writeInt32(100)
        currencyWriter.writeInt32(2)
        currencyWriter.writeBool(false)
        let currencyPacket = try GatewayWorldCodec.decodeAny(currencyWriter.data)
        guard case .storeCurrencyCodes(let currencies) = currencyPacket else {
            return XCTFail("Expected currency codes, got \(currencyPacket)")
        }
        XCTAssertEqual(currencies.currencies[840]?.symbol, "$")
        XCTAssertEqual(currencies.currencies[840]?.minorUnit, 100)

        var errorCurrencyWriter = PacketWriter()
        writeHeader(17, to: &errorCurrencyWriter)
        errorCurrencyWriter.writeInt32(2)
        errorCurrencyWriter.writeString("en_US")
        let errorCurrencyPacket = try GatewayWorldCodec.decodeAny(errorCurrencyWriter.data)
        guard case .storeCurrencyCodes(let errorCurrencies) = errorCurrencyPacket else {
            return XCTFail("Expected currency error, got \(errorCurrencyPacket)")
        }
        XCTAssertTrue(errorCurrencies.currencies.isEmpty)

        var stateWriter = PacketWriter()
        writeHeader(19, to: &stateWriter)
        stateWriter.writeInt32(1)
        stateWriter.writeInt32(1)
        stateWriter.writeString("CA")
        stateWriter.writeString("California")
        let statePacket = try GatewayWorldCodec.decodeAny(stateWriter.data)
        guard case .storeStateCodes(let states) = statePacket else {
            return XCTFail("Expected state codes, got \(statePacket)")
        }
        XCTAssertEqual(states.states.first?.name, "California")

        var countryWriter = PacketWriter()
        writeHeader(21, to: &countryWriter)
        countryWriter.writeInt32(1)
        countryWriter.writeString("en_US")
        countryWriter.writeInt32(1)
        countryWriter.writeString("US")
        countryWriter.writeString("en")
        countryWriter.writeString("en_US")
        countryWriter.writeString("United States")
        let countryPacket = try GatewayWorldCodec.decodeAny(countryWriter.data)
        guard case .storeCountryCodes(let countries) = countryPacket else {
            return XCTFail("Expected country codes, got \(countryPacket)")
        }
        XCTAssertEqual(countries.countries.first?.code, "US")
        XCTAssertEqual(countries.countries.first?.name, "United States")

        var accountWriter = PacketWriter()
        writeHeader(26, to: &accountWriter)
        accountWriter.writeInt32(1)
        accountWriter.writeString("US")
        accountWriter.writeString("USD")
        accountWriter.writeBool(true)
        let accountPacket = try GatewayWorldCodec.decodeAny(accountWriter.data)
        guard case .storeAccountInfo(let account) = accountPacket else {
            return XCTFail("Expected store account info, got \(accountPacket)")
        }
        XCTAssertEqual(account.defaultCountryCode, "US")
        XCTAssertTrue(account.isParentalPasswordEnabled)

        var contentWriter = PacketWriter()
        writeHeader(28, to: &contentWriter)
        contentWriter.writeInt32(2)
        contentWriter.writeInt32(7)
        contentWriter.writeInt32(101)
        contentWriter.writeInt32(7)
        contentWriter.writeInt32(102)
        let contentPacket = try GatewayWorldCodec.decodeAny(contentWriter.data)
        guard case .storeBundleContent(let content) = contentPacket else {
            return XCTFail("Expected store bundle content, got \(contentPacket)")
        }
        XCTAssertEqual(content.responses.map(\.bundleID), [101, 102])

        var requirementsWriter = PacketWriter()
        writeHeader(39, to: &requirementsWriter)
        requirementsWriter.writeInt32(2)
        requirementsWriter.writeInt32(101)
        requirementsWriter.writeBool(true)
        requirementsWriter.writeInt32(102)
        requirementsWriter.writeBool(false)
        let requirementsPacket = try GatewayWorldCodec.decodeAny(requirementsWriter.data)
        guard case .storeItemRequirements(let requirements) = requirementsPacket else {
            return XCTFail("Expected store item requirements, got \(requirementsPacket)")
        }
        XCTAssertEqual(requirements.itemRequirements.map(\.canPurchase), [true, false])

        var observation = GatewayWorldObservation.empty
        for packet in [
            previewPacket,
            placePacket,
            errorCurrencyPacket,
            currencyPacket,
            statePacket,
            countryPacket,
            accountPacket,
            contentPacket,
            requirementsPacket
        ] {
            observation.apply(packet)
        }
        XCTAssertEqual(observation.storePreviewOrder?.total, 880)
        XCTAssertEqual(observation.storePlaceOrder?.orderID, "order-92")
        XCTAssertEqual(observation.storeCurrencyCodes?[840]?.name, "US Dollar")
        XCTAssertEqual(observation.storeStateCodes?.first?.code, "CA")
        XCTAssertEqual(observation.storeCountryCodes?.first?.language, "en")
        XCTAssertEqual(observation.storeAccountInfo?.defaultCurrencyCode, "USD")
        XCTAssertEqual(observation.storeBundleContentResponses?.count, 2)
        XCTAssertEqual(observation.storeItemRequirements?.count, 2)
        XCTAssertTrue(observation.positions.isEmpty)

        var badCount = PacketWriter()
        writeHeader(39, to: &badCount)
        badCount.writeInt32(-1)
        XCTAssertThrowsError(try GatewayWorldCodec.decodeAny(badCount.data))

        var badCurrencyCount = PacketWriter()
        writeHeader(17, to: &badCurrencyCount)
        badCurrencyCount.writeInt32(1)
        badCurrencyCount.writeString("en_US")
        badCurrencyCount.writeInt32(65_537)
        XCTAssertThrowsError(try GatewayWorldCodec.decodeAny(badCurrencyCount.data))
    }

    func testServerBroadcastAndHousingZoneDataUseExactCSharpFieldOrder() throws {
        var broadcastWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayZoneBroadcast.opcode, to: &broadcastWriter.data)
        GatewayWire.appendInt16(GatewayZoneBroadcast.subOpcode, to: &broadcastWriter.data)
        let name = GatewayName(
            firstNameID: 1,
            lastNamePrefixID: 2,
            lastNameSuffixID: 3,
            firstName: "Ava",
            lastName: "Zephyr"
        )
        name.append(to: &broadcastWriter)
        broadcastWriter.writeString("Welcome to the zone")
        broadcastWriter.writeInt32(314)
        let broadcastPacket = try GatewayWorldCodec.decodeAny(broadcastWriter.data)
        guard case .zoneBroadcast(let broadcast) = broadcastPacket else {
            return XCTFail("Expected zone broadcast, got \(broadcastPacket)")
        }
        XCTAssertEqual(broadcast.name.firstName, "Ava")
        XCTAssertEqual(broadcast.message, "Welcome to the zone")
        XCTAssertEqual(broadcast.messageID, 314)

        var housingWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayHousingZoneData.opcode, to: &housingWriter.data)
        GatewayWire.appendInt16(GatewayHousingZoneData.subOpcode, to: &housingWriter.data)
        housingWriter.writeBool(true)
        housingWriter.writeBool(false)
        housingWriter.writeInt32(42)
        housingWriter.writeUInt64(0x1000)
        housingWriter.writeUInt64(0x2000)
        housingWriter.writeInt32(700)
        housingWriter.writeString("My House")
        housingWriter.writeString("Owner")
        housingWriter.writeInt32(11)
        housingWriter.writeInt32(12)
        housingWriter.writeInt32(13)
        housingWriter.writeInt64(1_700_000_000)
        housingWriter.writeBool(true)
        housingWriter.writeBool(false)
        housingWriter.writeBool(true)
        housingWriter.writeString("Description")
        housingWriter.writeString("keyword")
        housingWriter.writeString("unknown")
        housingWriter.writeFloat(4.5)
        housingWriter.writeInt32(9)
        housingWriter.writeBool(true)
        housingWriter.writeBool(false)
        housingWriter.writeInt32(77)
        housingWriter.writeInt64(1_600_000_000)
        let housingPacket = try GatewayWorldCodec.decodeAny(housingWriter.data)
        guard case .housingZoneData(let zone) = housingPacket else {
            return XCTFail("Expected housing zone data, got \(housingPacket)")
        }
        XCTAssertTrue(zone.isPreview)
        XCTAssertEqual(zone.headSize, 42)
        XCTAssertEqual(zone.instanceInfo.ownerGUID, 0x1000)
        XCTAssertEqual(zone.instanceInfo.houseName, "My House")
        XCTAssertEqual(zone.instanceInfo.ownerName, "Owner")
        XCTAssertEqual(zone.instanceInfo.lastVisitedSeconds, 1_700_000_000)
        XCTAssertEqual(zone.instanceInfo.rating, 4.5)
        XCTAssertEqual(zone.instanceInfo.whenCreatedSeconds, 1_600_000_000)

        var observation = GatewayWorldObservation.empty
        observation.apply(broadcastPacket)
        observation.apply(housingPacket)
        XCTAssertEqual(observation.lastZoneBroadcast?.name.lastName, "Zephyr")
        XCTAssertEqual(observation.housingZoneData?.instanceInfo.furnitureScore, 13)
        XCTAssertTrue(observation.positions.isEmpty)

        var houseInfoWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayHousingUpdateHouseInfo.opcode, to: &houseInfoWriter.data)
        GatewayWire.appendInt16(GatewayHousingUpdateHouseInfo.subOpcode, to: &houseInfoWriter.data)
        houseInfoWriter.writeBool(true)
        houseInfoWriter.writeInt32(99)
        houseInfoWriter.writeBool(false)
        houseInfoWriter.writeBool(true)
        houseInfoWriter.writeBool(false)
        houseInfoWriter.writeInt32(4)
        houseInfoWriter.writeInt32(5)
        houseInfoWriter.writeInt32(6)
        let houseInfoPacket = try GatewayWorldCodec.decodeAny(houseInfoWriter.data)
        guard case .housingUpdateHouseInfo(let info) = houseInfoPacket else {
            return XCTFail("Expected housing update, got \(houseInfoPacket)")
        }
        XCTAssertTrue(info.inEditMode)
        XCTAssertEqual(info.unused, 99)
        XCTAssertFalse(info.isLocked)
        XCTAssertTrue(info.isFloraAllowed)
        XCTAssertFalse(info.petAutospawn)
        XCTAssertEqual(info.curFixtureCount, 4)
        XCTAssertEqual(info.curLandmarkCount, 5)
        XCTAssertEqual(info.furnitureScore, 6)

        var observationWithHouseInfo = GatewayWorldObservation.empty
        observationWithHouseInfo.apply(houseInfoPacket)
        XCTAssertEqual(observationWithHouseInfo.lastHousingUpdateHouseInfo?.furnitureScore, 6)

        var wrongSub = PacketWriter()
        GatewayWire.appendInt16(GatewayHousingZoneData.opcode, to: &wrongSub.data)
        GatewayWire.appendInt16(43, to: &wrongSub.data)
        wrongSub.writeBool(false)
        let fallback = try GatewayWorldCodec.decodeAny(wrongSub.data)
        guard case .mapped = fallback else {
            return XCTFail("Expected raw-preserving mapped fallback, got \(fallback)")
        }
    }

    func testHousingInstanceListUsesVerifiedNestedOrderAndBoundedCount() throws {
        func writeInstance(_ writer: inout PacketWriter) {
            writer.writeUInt64(0x1111)
            writer.writeUInt64(0x2222)
            writer.writeInt32(500)
            writer.writeString("Garden")
            writer.writeString("Owner")
            writer.writeInt32(6)
            writer.writeInt32(7)
            writer.writeInt32(8)
            writer.writeInt64(1_700_000_001)
            writer.writeBool(false)
            writer.writeBool(true)
            writer.writeBool(false)
            writer.writeString("desc")
            writer.writeString("key")
            writer.writeString("u21")
            writer.writeFloat(2.25)
            writer.writeInt32(3)
            writer.writeBool(true)
            writer.writeBool(false)
            writer.writeInt32(9)
            writer.writeInt64(1_600_000_001)
        }

        var writer = PacketWriter()
        GatewayWire.appendInt16(GatewayHousingInstanceList.opcode, to: &writer.data)
        GatewayWire.appendInt16(GatewayHousingInstanceList.subOpcode, to: &writer.data)
        writer.writeInt32(1)
        writeInstance(&writer)
        writer.writeUInt64(0x3333)

        let packet = try GatewayWorldCodec.decodeAny(writer.data)
        guard case .housingInstanceList(let list) = packet else {
            return XCTFail("Expected housing instance list, got \(packet)")
        }
        XCTAssertEqual(list.instances.count, 1)
        XCTAssertEqual(list.instances[0].instanceGUID, 0x2222)
        XCTAssertEqual(list.instances[0].houseName, "Garden")
        XCTAssertEqual(list.instances[0].furnitureScore, 8)
        XCTAssertEqual(list.instances[0].whenCreatedSeconds, 1_600_000_001)
        XCTAssertEqual(list.playerGUID, 0x3333)

        var observation = GatewayWorldObservation.empty
        observation.apply(packet)
        XCTAssertEqual(observation.housingInstanceList?.instances[0].nameID, 500)
        XCTAssertEqual(observation.housingInstanceList?.playerGUID, 0x3333)
        XCTAssertNil(observation.housingZoneData)

        var invalid = PacketWriter()
        GatewayWire.appendInt16(GatewayHousingInstanceList.opcode, to: &invalid.data)
        GatewayWire.appendInt16(GatewayHousingInstanceList.subOpcode, to: &invalid.data)
        invalid.writeInt32(-1)
        XCTAssertThrowsError(try GatewayWorldCodec.decodeAny(invalid.data))
    }

    func testExecuteScriptPacketsDecodeArgumentsWithoutRunningScripts() throws {
        func header(_ sub: UInt8, to writer: inout PacketWriter) {
            GatewayWire.appendInt16(GatewayExecuteScript.opcode, to: &writer.data)
            writer.writeUInt8(sub)
        }

        var intWriter = PacketWriter()
        header(GatewayExecuteScript.subOpcode, to: &intWriter)
        intWriter.writeString("HUD.StartingZoneLoaded")
        intWriter.writeInt32(2)
        intWriter.writeInt32(10)
        intWriter.writeInt32(-3)
        let intPacket = try GatewayWorldCodec.decodeAny(intWriter.data)
        guard case .executeScript(let intScript) = intPacket else {
            return XCTFail("Expected int-argument UI packet, got \(intPacket)")
        }
        XCTAssertEqual(intScript.script, "HUD.StartingZoneLoaded")
        XCTAssertEqual(intScript.parameters, [10, -3])

        var stringWriter = PacketWriter()
        header(GatewayExecuteScriptStringParams.subOpcode, to: &stringWriter)
        stringWriter.writeString("OpenWindow")
        stringWriter.writeInt32(2)
        stringWriter.writeString("Inventory")
        stringWriter.writeString("1")
        let stringPacket = try GatewayWorldCodec.decodeAny(stringWriter.data)
        guard case .executeScriptStringParams(let stringScript) = stringPacket else {
            return XCTFail("Expected string-argument UI packet, got \(stringPacket)")
        }
        XCTAssertEqual(stringScript.script, "OpenWindow")
        XCTAssertEqual(stringScript.parameters, ["Inventory", "1"])

        var observation = GatewayWorldObservation.empty
        observation.apply(intPacket)
        observation.apply(stringPacket)
        XCTAssertEqual(observation.lastExecuteScript?.parameters, [10, -3])
        XCTAssertEqual(observation.lastExecuteScriptStringParams?.parameters, ["Inventory", "1"])
        XCTAssertNil(observation.lastTradeMessage)
        XCTAssertTrue(observation.positions.isEmpty)

        var invalid = PacketWriter()
        header(GatewayExecuteScript.subOpcode, to: &invalid)
        invalid.writeString("Bad")
        invalid.writeInt32(-1)
        XCTAssertThrowsError(try GatewayWorldCodec.decodeAny(invalid.data))
    }

    func testRawPayloadPacketsKeepPayloadBytesWithoutInterpretingThem() throws {
        let poiBytes = Data([0x01, 0x02, 0x03])
        var poiWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayPOIDefinitionReply.opcode, to: &poiWriter.data)
        poiWriter.writeData(poiBytes)
        let poiPacket = try GatewayWorldCodec.decodeAny(poiWriter.data)
        guard case .poiDefinitionReply(let reply) = poiPacket else {
            return XCTFail("Expected POI definition reply, got \(poiPacket)")
        }
        XCTAssertEqual(reply.payload, poiBytes)

        let inspectBytes = Data([0xAA, 0xBB])
        var inspectWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayStartInspect.opcode, to: &inspectWriter.data)
        inspectWriter.writeUInt8(GatewayStartInspect.subOpcode)
        inspectWriter.writeUInt64(0x4455)
        inspectWriter.writeBool(true)
        inspectWriter.writeData(inspectBytes)
        let inspectPacket = try GatewayWorldCodec.decodeAny(inspectWriter.data)
        guard case .startInspect(let inspect) = inspectPacket else {
            return XCTFail("Expected start inspect, got \(inspectPacket)")
        }
        XCTAssertEqual(inspect.guid, 0x4455)
        XCTAssertTrue(inspect.showPedestal)
        XCTAssertEqual(inspect.payload, inspectBytes)

        let titleBytes = Data([0x10, 0x20])
        var titleWriter = PacketWriter()
        GatewayWire.appendInt16(GatewayPlayerTitleUpdateAll.opcode, to: &titleWriter.data)
        titleWriter.writeInt32(GatewayPlayerTitleUpdateAll.subOpcode)
        titleWriter.writeData(titleBytes)
        let titlePacket = try GatewayWorldCodec.decodeAny(titleWriter.data)
        guard case .playerTitleUpdateAll(let titles) = titlePacket else {
            return XCTFail("Expected title update, got \(titlePacket)")
        }
        XCTAssertEqual(titles.payload, titleBytes)

        var observation = GatewayWorldObservation.empty
        for packet in [poiPacket, inspectPacket, titlePacket] {
            observation.apply(packet)
        }
        XCTAssertEqual(observation.lastPOIDefinitionReply?.payload, poiBytes)
        XCTAssertEqual(observation.lastStartInspect?.payload, inspectBytes)
        XCTAssertEqual(observation.lastPlayerTitleUpdateAll?.payload, titleBytes)
        XCTAssertNil(observation.lastExecuteScript)
    }

    private func writeHeader(_ opcode: Int16, _ subOpcode: Int16, to writer: inout PacketWriter) {
        GatewayWire.appendInt16(opcode, to: &writer.data)
        GatewayWire.appendInt16(subOpcode, to: &writer.data)
    }

    private func writeByteHeader(_ opcode: Int16, _ subOpcode: UInt8, to writer: inout PacketWriter) {
        GatewayWire.appendInt16(opcode, to: &writer.data)
        writer.writeUInt8(subOpcode)
    }

    private func writeIntHeader(_ opcode: Int16, _ subOpcode: Int32, to writer: inout PacketWriter) {
        GatewayWire.appendInt16(opcode, to: &writer.data)
        writer.writeInt32(subOpcode)
    }

    private func makeName(_ first: String, _ last: String) -> GatewayName {
        GatewayName(
            firstNameID: 1,
            lastNamePrefixID: 2,
            lastNameSuffixID: 3,
            firstName: first,
            lastName: last
        )
    }

    func testSourceVerifiedChatCommandPlayerAndCollectionReplies() throws {
        var debugChatWriter = PacketWriter()
        writeHeader(GatewayDebugChat.opcode, GatewayDebugChat.subOpcode, to: &debugChatWriter)
        debugChatWriter.writeString("debug line")
        debugChatWriter.writeBool(true)
        let debugChatPacket = try GatewayWorldCodec.decodeAny(debugChatWriter.data)
        guard case .debugChat(let debugChat) = debugChatPacket else {
            return XCTFail("Expected debug chat, got \(debugChatPacket)")
        }
        XCTAssertEqual(debugChat.message, "debug line")
        XCTAssertTrue(debugChat.printToChat)

        var tellWriter = PacketWriter()
        writeHeader(GatewayTellEcho.opcode, GatewayTellEcho.subOpcode, to: &tellWriter)
        makeName("Ava", "Zephyr").append(to: &tellWriter)
        tellWriter.writeString("hello back")
        let tellPacket = try GatewayWorldCodec.decodeAny(tellWriter.data)
        guard case .tellEcho(let tell) = tellPacket else {
            return XCTFail("Expected tell echo, got \(tellPacket)")
        }
        XCTAssertEqual(tell.name.lastName, "Zephyr")
        XCTAssertEqual(tell.message, "hello back")

        var endDialogWriter = PacketWriter()
        writeHeader(GatewayEndDialog.opcode, GatewayEndDialog.subOpcode, to: &endDialogWriter)
        let endDialogPacket = try GatewayWorldCodec.decodeAny(endDialogWriter.data)
        guard case .endDialog = endDialogPacket else {
            return XCTFail("Expected end dialog, got \(endDialogPacket)")
        }

        var friendRequestWriter = PacketWriter()
        writeHeader(GatewayConfirmFriendRequest.opcode, GatewayConfirmFriendRequest.subOpcode, to: &friendRequestWriter)
        friendRequestWriter.writeUInt64(0xA1)
        makeName("Bo", "River").append(to: &friendRequestWriter)
        friendRequestWriter.writeBool(false)
        let friendRequestPacket = try GatewayWorldCodec.decodeAny(friendRequestWriter.data)
        guard case .confirmFriendRequest(let friendRequest) = friendRequestPacket else {
            return XCTFail("Expected friend request confirmation, got \(friendRequestPacket)")
        }
        XCTAssertEqual(friendRequest.guid, 0xA1)
        XCTAssertEqual(friendRequest.name.firstName, "Bo")
        XCTAssertFalse(friendRequest.unknown)

        var effectWriter = PacketWriter()
        writeHeader(GatewayPlayCompositeEffect.opcode, GatewayPlayCompositeEffect.subOpcode, to: &effectWriter)
        effectWriter.writeUInt64(0xB1)
        effectWriter.writeUInt64(0xB2)
        effectWriter.writeInt32(77)
        effectWriter.writeInt32(88)
        effectWriter.writeInt32(99)
        effectWriter.writeFloat(1.5)
        effectWriter.writeFloat(2.5)
        effectWriter.writeFloat(3.5)
        effectWriter.writeFloat(4.5)
        effectWriter.writeBool(true)
        let effectPacket = try GatewayWorldCodec.decodeAny(effectWriter.data)
        guard case .playCompositeEffect(let effect) = effectPacket else {
            return XCTFail("Expected composite effect, got \(effectPacket)")
        }
        XCTAssertEqual(effect.guid, 0xB1)
        XCTAssertEqual(effect.unknown2, 0xB2)
        XCTAssertEqual(effect.compositeEffectID, 77)
        XCTAssertEqual(effect.positionW, 4.5)
        XCTAssertTrue(effect.clear)

        var renameWriter = PacketWriter()
        writeHeader(GatewayPlayerRename.opcode, GatewayPlayerRename.subOpcode, to: &renameWriter)
        renameWriter.writeUInt64(0xC1)
        makeName("Cy", "Storm").append(to: &renameWriter)
        let renamePacket = try GatewayWorldCodec.decodeAny(renameWriter.data)
        guard case .playerRename(let rename) = renamePacket else {
            return XCTFail("Expected player rename, got \(renamePacket)")
        }
        XCTAssertEqual(rename.guid, 0xC1)
        XCTAssertEqual(rename.name.firstName, "Cy")

        var syncWriter = PacketWriter()
        writeHeader(GatewaySynchronizedAnimations.opcode, GatewaySynchronizedAnimations.subOpcode, to: &syncWriter)
        syncWriter.writeInt32(2)
        syncWriter.writeUInt64(0xD1)
        syncWriter.writeInt32(11)
        syncWriter.writeUInt64(0xD2)
        syncWriter.writeInt32(12)
        let syncPacket = try GatewayWorldCodec.decodeAny(syncWriter.data)
        guard case .synchronizedAnimations(let sync) = syncPacket else {
            return XCTFail("Expected synchronized animations, got \(syncPacket)")
        }
        XCTAssertEqual(sync.animations.count, 2)
        XCTAssertEqual(sync.animations[1].guid, 0xD2)
        XCTAssertEqual(sync.animations[1].animationID, 12)

        var collectionRemoveWriter = PacketWriter()
        writeHeader(GatewayCollectionRemove.opcode, GatewayCollectionRemove.subOpcode, to: &collectionRemoveWriter)
        collectionRemoveWriter.writeInt32(21)
        let collectionRemovePacket = try GatewayWorldCodec.decodeAny(collectionRemoveWriter.data)
        guard case .collectionRemove(let collectionRemove) = collectionRemovePacket else {
            return XCTFail("Expected collection remove, got \(collectionRemovePacket)")
        }
        XCTAssertEqual(collectionRemove.collectionID, 21)

        var addEntryWriter = PacketWriter()
        writeHeader(GatewayCollectionAddEntry.opcode, GatewayCollectionAddEntry.subOpcode, to: &addEntryWriter)
        for value: Int32 in [1, 2, 3, 4, 5, 6, 7] { addEntryWriter.writeInt32(value) }
        addEntryWriter.writeBool(false)
        let addEntryPacket = try GatewayWorldCodec.decodeAny(addEntryWriter.data)
        guard case .collectionAddEntry(let addEntry) = addEntryPacket else {
            return XCTFail("Expected collection add entry, got \(addEntryPacket)")
        }
        XCTAssertEqual(addEntry.definitionID, 1)
        XCTAssertEqual(addEntry.iconTintID, 3)
        XCTAssertEqual(addEntry.collectionID, 5)
        XCTAssertEqual(addEntry.unknown, 7)
        XCTAssertFalse(addEntry.collected)

        var removeEntryWriter = PacketWriter()
        writeHeader(GatewayCollectionRemoveEntry.opcode, GatewayCollectionRemoveEntry.subOpcode, to: &removeEntryWriter)
        removeEntryWriter.writeInt32(31)
        removeEntryWriter.writeInt32(32)
        let removeEntryPacket = try GatewayWorldCodec.decodeAny(removeEntryWriter.data)
        guard case .collectionRemoveEntry(let removeEntry) = removeEntryPacket else {
            return XCTFail("Expected collection remove entry, got \(removeEntryPacket)")
        }
        XCTAssertEqual(removeEntry.collectionID, 31)
        XCTAssertEqual(removeEntry.entryID, 32)

        var observation = GatewayWorldObservation.empty
        for packet in [
            debugChatPacket, tellPacket, endDialogPacket, friendRequestPacket, effectPacket,
            renamePacket, syncPacket, collectionRemovePacket, addEntryPacket, removeEntryPacket
        ] {
            observation.apply(packet)
        }
        XCTAssertEqual(observation.lastDebugChat?.message, "debug line")
        XCTAssertEqual(observation.lastTellEcho?.name.lastName, "Zephyr")
        XCTAssertNotNil(observation.lastEndDialog)
        XCTAssertEqual(observation.lastConfirmFriendRequest?.guid, 0xA1)
        XCTAssertEqual(observation.lastPlayCompositeEffect?.compositeEffectID, 77)
        XCTAssertEqual(observation.lastPlayerRename?.guid, 0xC1)
        XCTAssertEqual(observation.lastSynchronizedAnimations?.animations.count, 2)
        XCTAssertEqual(observation.lastCollectionRemove?.collectionID, 21)
        XCTAssertEqual(observation.lastCollectionAddEntry?.definitionID, 1)
        XCTAssertEqual(observation.lastCollectionRemoveEntry?.entryID, 32)
        XCTAssertTrue(observation.positions.isEmpty)
    }

    func testSourceVerifiedPetQuickChatFriendAndIgnoreReplies() throws {
        var petNameWriter = PacketWriter()
        writeByteHeader(GatewayPetSetName.opcode, GatewayPetSetName.subOpcode, to: &petNameWriter)
        petNameWriter.writeUInt64(0x111)
        petNameWriter.writeString("Pixel")
        petNameWriter.writeBool(true)
        let petNamePacket = try GatewayWorldCodec.decodeAny(petNameWriter.data)
        guard case .petSetName(let petName) = petNamePacket else {
            return XCTFail("Expected pet set name, got \(petNamePacket)")
        }
        XCTAssertEqual(petName.petGUID, 0x111)
        XCTAssertEqual(petName.name, "Pixel")
        XCTAssertTrue(petName.accepted)

        var petEquipWriter = PacketWriter()
        writeByteHeader(GatewayPetEquip.opcode, GatewayPetEquip.subOpcode, to: &petEquipWriter)
        petEquipWriter.writeBool(false)
        petEquipWriter.writeInt32(3)
        petEquipWriter.writeInt32(44)
        let petEquipPacket = try GatewayWorldCodec.decodeAny(petEquipWriter.data)
        guard case .petEquip(let petEquip) = petEquipPacket else {
            return XCTFail("Expected pet equip, got \(petEquipPacket)")
        }
        XCTAssertFalse(petEquip.unequip)
        XCTAssertEqual(petEquip.slot, 3)
        XCTAssertEqual(petEquip.itemGUID, 44)

        var petUtilityWriter = PacketWriter()
        writeByteHeader(GatewayPetUtility.opcode, GatewayPetUtility.subOpcode, to: &petUtilityWriter)
        petUtilityWriter.writeBool(true)
        petUtilityWriter.writeInt32(55)
        petUtilityWriter.writeInt32(6)
        petUtilityWriter.writeInt32(77)
        let petUtilityPacket = try GatewayWorldCodec.decodeAny(petUtilityWriter.data)
        guard case .petUtility(let petUtility) = petUtilityPacket else {
            return XCTFail("Expected pet utility, got \(petUtilityPacket)")
        }
        XCTAssertTrue(petUtility.unequip)
        XCTAssertEqual(petUtility.petID, 55)
        XCTAssertEqual(petUtility.slot, 6)
        XCTAssertEqual(petUtility.itemGUID, 77)

        var quickChatWriter = PacketWriter()
        writeHeader(GatewayQuickChatChannel.opcode, GatewayQuickChatChannel.subOpcode, to: &quickChatWriter)
        quickChatWriter.writeInt32(101)
        quickChatWriter.writeUInt64(0x222)
        makeName("Dee", "Lake").append(to: &quickChatWriter)
        GatewayWire.appendInt16(7, to: &quickChatWriter.data)
        quickChatWriter.writeInt32(808)
        quickChatWriter.writeUInt64(0x333)
        let quickChatPacket = try GatewayWorldCodec.decodeAny(quickChatWriter.data)
        guard case .quickChatChannel(let quickChat) = quickChatPacket else {
            return XCTFail("Expected quick chat channel, got \(quickChatPacket)")
        }
        XCTAssertEqual(quickChat.id, 101)
        XCTAssertEqual(quickChat.name.firstName, "Dee")
        XCTAssertEqual(quickChat.channel, 7)
        XCTAssertEqual(quickChat.areaNameID, 808)
        XCTAssertEqual(quickChat.guildGUID, 0x333)

        var friendMessageWriter = PacketWriter()
        writeByteHeader(GatewayFriendMessage.opcode, GatewayFriendMessage.subOpcode, to: &friendMessageWriter)
        friendMessageWriter.writeUInt8(2)
        friendMessageWriter.writeUInt64(0x444)
        makeName("Eve", "Vale").append(to: &friendMessageWriter)
        makeName("Eve", "Nova").append(to: &friendMessageWriter)
        let friendMessagePacket = try GatewayWorldCodec.decodeAny(friendMessageWriter.data)
        guard case .friendMessage(let friendMessage) = friendMessagePacket else {
            return XCTFail("Expected friend message, got \(friendMessagePacket)")
        }
        XCTAssertEqual(friendMessage.type, 2)
        XCTAssertEqual(friendMessage.guid, 0x444)
        XCTAssertEqual(friendMessage.name.lastName, "Vale")
        XCTAssertEqual(friendMessage.newName.lastName, "Nova")

        var ignoreRemoveWriter = PacketWriter()
        writeByteHeader(GatewayIgnoreRemove.opcode, GatewayIgnoreRemove.subOpcode, to: &ignoreRemoveWriter)
        ignoreRemoveWriter.writeUInt64(0x555)
        let ignoreRemovePacket = try GatewayWorldCodec.decodeAny(ignoreRemoveWriter.data)
        guard case .ignoreRemove(let ignoreRemove) = ignoreRemovePacket else {
            return XCTFail("Expected ignore remove, got \(ignoreRemovePacket)")
        }
        XCTAssertEqual(ignoreRemove.guid, 0x555)

        var observation = GatewayWorldObservation.empty
        for packet in [
            petNamePacket, petEquipPacket, petUtilityPacket, quickChatPacket,
            friendMessagePacket, ignoreRemovePacket
        ] {
            observation.apply(packet)
        }
        XCTAssertEqual(observation.lastPetSetName?.name, "Pixel")
        XCTAssertEqual(observation.lastPetEquip?.slot, 3)
        XCTAssertEqual(observation.lastPetUtility?.petID, 55)
        XCTAssertEqual(observation.lastQuickChatChannel?.channel, 7)
        XCTAssertEqual(observation.lastFriendMessage?.newName.lastName, "Nova")
        XCTAssertEqual(observation.lastIgnoreRemove?.guid, 0x555)
        XCTAssertTrue(observation.positions.isEmpty)
    }

    func testSourceVerifiedGuildNameChangeAndJournalReplies() throws {
        var memberStatusWriter = PacketWriter()
        writeHeader(GatewayGuildMemberStatusUpdate.opcode, GatewayGuildMemberStatusUpdate.subOpcode, to: &memberStatusWriter)
        memberStatusWriter.writeUInt64(0x1001)
        memberStatusWriter.writeUInt64(0x1002)
        makeName("Finn", "Brook").append(to: &memberStatusWriter)
        memberStatusWriter.writeInt32(4)
        memberStatusWriter.writeBool(true)
        for value: Int32 in [6, 7, 8, 9, 10] { memberStatusWriter.writeInt32(value) }
        let memberStatusPacket = try GatewayWorldCodec.decodeAny(memberStatusWriter.data)
        guard case .guildMemberStatusUpdate(let memberStatus) = memberStatusPacket else {
            return XCTFail("Expected guild member status, got \(memberStatusPacket)")
        }
        XCTAssertEqual(memberStatus.guildGUID, 0x1001)
        XCTAssertEqual(memberStatus.memberGUID, 0x1002)
        XCTAssertEqual(memberStatus.name.firstName, "Finn")
        XCTAssertEqual(memberStatus.role, 4)
        XCTAssertTrue(memberStatus.online)
        XCTAssertEqual(memberStatus.profileRank, 10)

        var guildNameWriter = PacketWriter()
        writeHeader(GatewayGuildNameUpdate.opcode, GatewayGuildNameUpdate.subOpcode, to: &guildNameWriter)
        guildNameWriter.writeUInt64(0x2001)
        guildNameWriter.writeString("Night Owls")
        let guildNamePacket = try GatewayWorldCodec.decodeAny(guildNameWriter.data)
        guard case .guildNameUpdate(let guildName) = guildNamePacket else {
            return XCTFail("Expected guild name update, got \(guildNamePacket)")
        }
        XCTAssertEqual(guildName.guid, 0x2001)
        XCTAssertEqual(guildName.name, "Night Owls")

        var guildErrorWriter = PacketWriter()
        writeHeader(GatewayGuildError.opcode, GatewayGuildError.subOpcode, to: &guildErrorWriter)
        guildErrorWriter.writeString("GuildError_Invalid")
        let guildErrorPacket = try GatewayWorldCodec.decodeAny(guildErrorWriter.data)
        guard case .guildError(let guildError) = guildErrorPacket else {
            return XCTFail("Expected guild error, got \(guildErrorPacket)")
        }
        XCTAssertEqual(guildError.messageName, "GuildError_Invalid")

        var inviteAcceptWriter = PacketWriter()
        writeHeader(GatewayGuildInviteAcceptNotification.opcode, GatewayGuildInviteAcceptNotification.subOpcode, to: &inviteAcceptWriter)
        makeName("Gia", "Wren").append(to: &inviteAcceptWriter)
        let inviteAcceptPacket = try GatewayWorldCodec.decodeAny(inviteAcceptWriter.data)
        guard case .guildInviteAcceptNotification(let inviteAccept) = inviteAcceptPacket else {
            return XCTFail("Expected guild invite accept, got \(inviteAcceptPacket)")
        }
        XCTAssertEqual(inviteAccept.name.lastName, "Wren")

        var inviteDeclineWriter = PacketWriter()
        writeHeader(GatewayGuildInviteDeclineNotification.opcode, GatewayGuildInviteDeclineNotification.subOpcode, to: &inviteDeclineWriter)
        makeName("Hal", "Frost").append(to: &inviteDeclineWriter)
        inviteDeclineWriter.writeBool(true)
        let inviteDeclinePacket = try GatewayWorldCodec.decodeAny(inviteDeclineWriter.data)
        guard case .guildInviteDeclineNotification(let inviteDecline) = inviteDeclinePacket else {
            return XCTFail("Expected guild invite decline, got \(inviteDeclinePacket)")
        }
        XCTAssertEqual(inviteDecline.name.firstName, "Hal")
        XCTAssertTrue(inviteDecline.timedOut)

        var renameCheckWriter = PacketWriter()
        writeHeader(GatewayGuildRenameCheckReply.opcode, GatewayGuildRenameCheckReply.subOpcode, to: &renameCheckWriter)
        renameCheckWriter.writeUInt64(0x3001)
        renameCheckWriter.writeString("New Name")
        renameCheckWriter.writeInt32(5)
        let renameCheckPacket = try GatewayWorldCodec.decodeAny(renameCheckWriter.data)
        guard case .guildRenameCheckReply(let renameCheck) = renameCheckPacket else {
            return XCTFail("Expected guild rename check, got \(renameCheckPacket)")
        }
        XCTAssertEqual(renameCheck.guid, 0x3001)
        XCTAssertEqual(renameCheck.name, "New Name")
        XCTAssertEqual(renameCheck.result, 5)

        var playerStatusWriter = PacketWriter()
        writeHeader(GatewayGuildPlayerStatusUpdate.opcode, GatewayGuildPlayerStatusUpdate.subOpcode, to: &playerStatusWriter)
        playerStatusWriter.writeUInt64(0x4001)
        playerStatusWriter.writeUInt64(0x4002)
        playerStatusWriter.writeBool(false)
        let playerStatusPacket = try GatewayWorldCodec.decodeAny(playerStatusWriter.data)
        guard case .guildPlayerStatusUpdate(let playerStatus) = playerStatusPacket else {
            return XCTFail("Expected guild player status, got \(playerStatusPacket)")
        }
        XCTAssertEqual(playerStatus.playerGUID, 0x4001)
        XCTAssertEqual(playerStatus.guildGUID, 0x4002)
        XCTAssertFalse(playerStatus.isInGuild)

        var canCreateWriter = PacketWriter()
        writeHeader(GatewayGuildCanCreate.opcode, GatewayGuildCanCreate.subOpcode, to: &canCreateWriter)
        canCreateWriter.writeBool(true)
        let canCreatePacket = try GatewayWorldCodec.decodeAny(canCreateWriter.data)
        guard case .guildCanCreate(let canCreate) = canCreatePacket else {
            return XCTFail("Expected guild can create, got \(canCreatePacket)")
        }
        XCTAssertTrue(canCreate.canCreateGuild)

        var createWriter = PacketWriter()
        writeHeader(GatewayGuildCreateAllowed.opcode, GatewayGuildCreateAllowed.subOpcode, to: &createWriter)
        createWriter.writeBool(false)
        let createPacket = try GatewayWorldCodec.decodeAny(createWriter.data)
        guard case .guildCreateAllowed(let create) = createPacket else {
            return XCTFail("Expected guild create reply, got \(createPacket)")
        }
        XCTAssertFalse(create.createGuild)

        var checkNameWriter = PacketWriter()
        writeHeader(GatewayCheckNameResponse.opcode, GatewayCheckNameResponse.subOpcode, to: &checkNameWriter)
        makeName("Ivy", "Moss").append(to: &checkNameWriter)
        checkNameWriter.writeInt32(2)
        checkNameWriter.writeInt32(3)
        checkNameWriter.writeUInt64(0x5001)
        let checkNamePacket = try GatewayWorldCodec.decodeAny(checkNameWriter.data)
        guard case .checkNameResponse(let checkName) = checkNamePacket else {
            return XCTFail("Expected name check response, got \(checkNamePacket)")
        }
        XCTAssertEqual(checkName.name.lastName, "Moss")
        XCTAssertEqual(checkName.result, 2)
        XCTAssertEqual(checkName.type, 3)
        XCTAssertEqual(checkName.guid, 0x5001)

        var nameChangeWriter = PacketWriter()
        writeHeader(GatewayNameChangeResponse.opcode, GatewayNameChangeResponse.subOpcode, to: &nameChangeWriter)
        nameChangeWriter.writeInt32(4)
        nameChangeWriter.writeUInt64(0x6001)
        makeName("Jade", "Sky").append(to: &nameChangeWriter)
        nameChangeWriter.writeInt32(5)
        let nameChangePacket = try GatewayWorldCodec.decodeAny(nameChangeWriter.data)
        guard case .nameChangeResponse(let nameChange) = nameChangePacket else {
            return XCTFail("Expected name change response, got \(nameChangePacket)")
        }
        XCTAssertEqual(nameChange.type, 4)
        XCTAssertEqual(nameChange.guid, 0x6001)
        XCTAssertEqual(nameChange.name.firstName, "Jade")
        XCTAssertEqual(nameChange.result, 5)

        var journalWriter = PacketWriter()
        writeIntHeader(GatewayJournalQuestUpdate.opcode, GatewayJournalQuestUpdate.subOpcode, to: &journalWriter)
        journalWriter.writeInt32(2)
        journalWriter.writeInt32(71)
        journalWriter.writeInt32(3)
        journalWriter.writeInt32(72)
        journalWriter.writeInt32(4)
        let journalPacket = try GatewayWorldCodec.decodeAny(journalWriter.data)
        guard case .journalQuestUpdate(let journal) = journalPacket else {
            return XCTFail("Expected journal quest update, got \(journalPacket)")
        }
        XCTAssertEqual(journal.questStates[71], 3)
        XCTAssertEqual(journal.questStates[72], 4)

        var observation = GatewayWorldObservation.empty
        for packet in [
            memberStatusPacket, guildNamePacket, guildErrorPacket, inviteAcceptPacket,
            inviteDeclinePacket, renameCheckPacket, playerStatusPacket, canCreatePacket,
            createPacket, checkNamePacket, nameChangePacket, journalPacket
        ] {
            observation.apply(packet)
        }
        XCTAssertEqual(observation.lastGuildMemberStatusUpdate?.profileRank, 10)
        XCTAssertEqual(observation.lastGuildNameUpdate?.name, "Night Owls")
        XCTAssertEqual(observation.lastGuildError?.messageName, "GuildError_Invalid")
        XCTAssertEqual(observation.lastGuildInviteAcceptNotification?.name.firstName, "Gia")
        XCTAssertTrue(observation.lastGuildInviteDeclineNotification?.timedOut ?? false)
        XCTAssertEqual(observation.lastGuildRenameCheckReply?.result, 5)
        XCTAssertFalse(observation.lastGuildPlayerStatusUpdate?.isInGuild ?? true)
        XCTAssertTrue(observation.lastGuildCanCreate?.canCreateGuild ?? false)
        XCTAssertFalse(observation.lastGuildCreateAllowed?.createGuild ?? true)
        XCTAssertEqual(observation.lastCheckNameResponse?.guid, 0x5001)
        XCTAssertEqual(observation.lastNameChangeResponse?.name.lastName, "Sky")
        XCTAssertEqual(observation.lastJournalQuestUpdate?.questStates.count, 2)
        XCTAssertTrue(observation.positions.isEmpty)
    }
}
