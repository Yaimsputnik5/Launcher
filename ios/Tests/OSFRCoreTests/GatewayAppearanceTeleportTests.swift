import Foundation
import XCTest
@testable import OSFRCore

/// Covers the audited server-to-client appearance and teleport packets that
/// complete the player-update lifecycle. All fixtures are built from the exact
/// Sanctuary `PacketWriter` field order, not from approximated values.
final class GatewayAppearanceTeleportTests: XCTestCase {
    private let guid: UInt64 = 0x1122_3344_5566_7788

    private func playerUpdate(
        _ sub: Int16,
        body: (inout PacketWriter) -> Void
    ) -> Data {
        var writer = PacketWriter()
        GatewayWire.appendInt16(35, to: &writer.data)
        GatewayWire.appendInt16(sub, to: &writer.data)
        body(&writer)
        return writer.data
    }

    private func writeAttachment(
        _ attachment: GatewayAttachment,
        to writer: inout PacketWriter
    ) {
        writer.writeString(attachment.modelName)
        writer.writeString(attachment.textureAlias)
        writer.writeString(attachment.tintAlias)
        writer.writeInt32(attachment.tintID)
        writer.writeInt32(attachment.compositeEffectID)
        writer.writeInt32(attachment.slot)
    }

    func testEquipItemChangeDecodesSingleAttachmentAndDoesNotFabricateEntity() throws {
        let attachment = GatewayAttachment(
            modelName: "hat_model",
            textureAlias: "hat_tex",
            tintAlias: "hat_tint",
            tintID: 11,
            compositeEffectID: 4005,
            slot: 7
        )
        let data = playerUpdate(6) { writer in
            writer.writeUInt64(guid)
            writer.writeInt32(77)
            writeAttachment(attachment, to: &writer)
            writer.writeInt32(9)
            writer.writeInt32(10)
            writer.writeInt32(3)
        }

        let decoded = try GatewayEquipItemChange(data: data)
        XCTAssertEqual(decoded.guid, guid)
        XCTAssertEqual(decoded.id, 77)
        XCTAssertEqual(decoded.attachment, attachment)
        XCTAssertEqual(decoded.profileID, 9)
        XCTAssertEqual(decoded.itemClassID, 10)
        XCTAssertEqual(decoded.wieldType, 3)

        var observation = GatewayWorldObservation.empty
        observation.apply(try GatewayWorldCodec.decodeAny(data))
        XCTAssertTrue(observation.names.isEmpty)
        XCTAssertTrue(observation.positions.isEmpty)
        XCTAssertEqual(observation.equipment[guid], [attachment])
    }

    func testUnequipEmptiesOnlyMatchingSlot() throws {
        let hat = GatewayAttachment(
            modelName: "hat", textureAlias: "", tintAlias: "", tintID: 0,
            compositeEffectID: 0, slot: 7
        )
        let boots = GatewayAttachment(
            modelName: "boots", textureAlias: "", tintAlias: "", tintID: 0,
            compositeEffectID: 0, slot: 4
        )
        var setup = GatewayWorldObservation.empty
        setup.equipment[guid] = [boots, hat]
        let data = playerUpdate(6) { writer in
            writer.writeUInt64(guid)
            writer.writeInt32(77)
            writeAttachment(
                GatewayAttachment(
                    modelName: "", textureAlias: "", tintAlias: "", tintID: 0,
                    compositeEffectID: 0, slot: 7
                ),
                to: &writer
            )
            writer.writeInt32(9)
            writer.writeInt32(10)
            writer.writeInt32(0)
        }
        setup.apply(try GatewayWorldCodec.decodeAny(data))
        XCTAssertEqual(setup.equipment[guid], [boots])
    }

    func testEquippedItemsChangeReplacesWholeAttachmentList() throws {
        let first = GatewayAttachment(
            modelName: "a", textureAlias: "b", tintAlias: "c", tintID: 1,
            compositeEffectID: 2, slot: 3
        )
        let second = GatewayAttachment(
            modelName: "d", textureAlias: "e", tintAlias: "f", tintID: 4,
            compositeEffectID: 5, slot: 6
        )
        let data = playerUpdate(7) { writer in
            writer.writeUInt64(guid)
            writer.writeInt32(2)
            writeAttachment(first, to: &writer)
            writeAttachment(second, to: &writer)
            writer.writeInt32(0)
        }

        let decoded = try GatewayEquippedItemsChange(data: data)
        XCTAssertEqual(decoded.guid, guid)
        XCTAssertEqual(decoded.attachments, [first, second])
        XCTAssertEqual(decoded.unknown, 0)

        var observation = GatewayWorldObservation.empty
        observation.apply(try GatewayWorldCodec.decodeAny(data))
        XCTAssertEqual(observation.equipment[guid], [first, second])
    }

    func testTemporaryAppearanceUsesIntBeforeGuidAndRemovalClearsIt() throws {
        let added = playerUpdate(14) { writer in
            writer.writeInt32(42)
            writer.writeUInt64(guid)
        }
        let removed = playerUpdate(15) { writer in
            writer.writeUInt64(guid)
            writer.writeInt32(0)
        }

        let decoded = try GatewayTemporaryAppearance(data: added)
        XCTAssertEqual(decoded.temporaryAppearance, 42)
        XCTAssertEqual(decoded.guid, guid)

        var observation = GatewayWorldObservation.empty
        observation.apply(try GatewayWorldCodec.decodeAny(added))
        XCTAssertEqual(observation.temporaryAppearances[guid], 42)
        observation.apply(try GatewayWorldCodec.decodeAny(removed))
        XCTAssertNil(observation.temporaryAppearances[guid])
    }

    func testSlotFlairAndWieldTypeDecodeAndApply() throws {
        let flair = playerUpdate(31) { writer in
            writer.writeUInt64(guid)
            writer.writeInt32(7)
            writer.writeInt32(4005)
        }
        let cleared = playerUpdate(31) { writer in
            writer.writeUInt64(guid)
            writer.writeInt32(7)
            writer.writeInt32(0)
        }
        let wield = playerUpdate(61) { writer in
            writer.writeUInt64(guid)
            writer.writeInt32(3)
        }

        XCTAssertEqual(try GatewaySlotCompositeEffectOverride(data: flair).compositeEffect, 4005)
        XCTAssertEqual(try GatewayActiveWieldType(data: wield).wieldType, 3)

        var observation = GatewayWorldObservation.empty
        observation.apply(try GatewayWorldCodec.decodeAny(flair))
        XCTAssertEqual(observation.compositeEffectOverrides[guid], [7: 4005])
        observation.apply(try GatewayWorldCodec.decodeAny(cleared))
        XCTAssertNil(observation.compositeEffectOverrides[guid]?[7])
        observation.apply(try GatewayWorldCodec.decodeAny(wield))
        XCTAssertEqual(observation.activeWieldTypes[guid], 3)
    }

    func testBeginZoningDecodesExactFieldOrderAndSetsExpectedSequence() throws {
        let position = GatewayVector4(x: 1, y: 2, z: 3, w: 0.5)
        let rotation = GatewayVector4(x: 0, y: 0.25, z: 0, w: 0.9682458)
        var writer = PacketWriter()
        GatewayWire.appendInt16(31, to: &writer.data)
        writer.writeString("Felicity")
        writer.writeInt32(2)
        position.append(to: &writer)
        rotation.append(to: &writer)
        writer.writeString("day_clear")
        writer.writeBool(true)
        writer.writeUInt8(2)
        writer.writeInt32(10)
        writer.writeFloat(96)
        writer.writeInt32(214)
        writer.writeBool(true)
        writer.writeBool(false)

        let decoded = try GatewayClientBeginZoning(data: writer.data)
        XCTAssertEqual(decoded.name, "Felicity")
        XCTAssertEqual(decoded.type, 2)
        XCTAssertEqual(decoded.position, position)
        XCTAssertEqual(decoded.rotation, rotation)
        XCTAssertEqual(decoded.sky, "day_clear")
        XCTAssertTrue(decoded.tutorial)
        XCTAssertEqual(decoded.teleportSequence, 2)
        XCTAssertEqual(decoded.id, 10)
        XCTAssertEqual(decoded.geometryID, 214)
        XCTAssertTrue(decoded.overrideUpdateRadius)
        XCTAssertFalse(decoded.waitForZoneReadyPacket)

        var observation = GatewayWorldObservation.empty
        observation.playerGUID = guid
        observation.positions[guid] = GatewayWorldObservation.Position(
            guid: guid,
            position: ZoneVector(x: 0, y: 0, z: 0, w: 0),
            rotation: ZoneVector(x: 0, y: 0, z: 0, w: 1),
            state: 0,
            teleportSequence: 0,
            receivedAt: Date(timeIntervalSince1970: 0)
        )
        observation.apply(try GatewayWorldCodec.decodeAny(writer.data))
        XCTAssertEqual(observation.pendingZoneName, "Felicity")
        XCTAssertEqual(observation.pendingZoneID, 10)
        XCTAssertEqual(observation.pendingZoneGeometryID, 214)
        XCTAssertEqual(observation.ownTeleportSequence, 2)
        XCTAssertEqual(observation.teleportSequences[guid], 2)
        XCTAssertEqual(observation.positions[guid]?.teleportSequence, 2)
        XCTAssertEqual(observation.positions[guid]?.position.x, 1)
        XCTAssertTrue(observation.names.isEmpty)
    }

    func testUpdateLocationTeleportIsAppliedOnlyToKnownSelf() throws {
        var writer = PacketWriter()
        GatewayWire.appendInt16(38, to: &writer.data)
        GatewayWire.appendInt16(12, to: &writer.data)
        GatewayVector4(x: 10, y: 20, z: 30, w: 1).append(to: &writer)
        GatewayVector4(x: 0, y: 0.5, z: 0, w: 0.8660254).append(to: &writer)
        writer.writeBool(true)
        writer.writeUInt8(3)

        let decoded = try GatewayUpdateLocation(data: writer.data)
        XCTAssertTrue(decoded.teleport)
        XCTAssertEqual(decoded.teleportSequence, 3)

        var observation = GatewayWorldObservation.empty
        observation.playerGUID = guid
        observation.scales[guid] = 2
        observation.apply(try GatewayWorldCodec.decodeAny(writer.data))
        XCTAssertEqual(observation.ownTeleportSequence, 3)
        XCTAssertNil(observation.scales[guid])
        XCTAssertNil(observation.positions[guid])
        XCTAssertTrue(observation.names.isEmpty)
    }
}
