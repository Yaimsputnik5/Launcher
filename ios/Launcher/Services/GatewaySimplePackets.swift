import Foundation

/// Small server-to-client packets whose layouts are taken directly from
/// `Sanctuary.Packet` `Serialize()` implementations. These are decoded from
/// packet bytes only; no offline value is ever used to fill a field.

/// `BaseClientUpdatePacket` (38) / `ClientUpdatePacketHitpoints` (1).
struct GatewayHitpointsUpdate: Equatable, Sendable {
    static let opcode: Int16 = 38
    static let subOpcode: Int16 = 1

    let current: Int32
    let max: Int32

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        let sub = try GatewayWire.readInt16(&reader)
        guard sub == Self.subOpcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.subOpcode, actual: sub)
        }
        current = try reader.readInt32()
        max = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `PacketSetClientArea` (89): `AreaId`, `Enabled`, `ElapsedMilliseconds`.
struct GatewayClientAreaUpdate: Equatable, Sendable {
    static let opcode: Int16 = 89

    let areaID: Int32
    let enabled: Bool
    let elapsedMilliseconds: Int32

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        areaID = try reader.readInt32()
        enabled = try reader.readBool()
        elapsedMilliseconds = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `PacketMOTD` (87): two length-prefixed UTF-8 strings.
struct GatewayMessageOfTheDay: Equatable, Sendable {
    static let opcode: Int16 = 87

    let message: String
    let secondary: String

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        message = try reader.readString()
        secondary = try reader.readString()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseClientUpdatePacket` (38) / `ClientUpdatePacketMana` (13).
struct GatewayManaUpdate: Equatable, Sendable {
    static let opcode: Int16 = 38
    static let subOpcode: Int16 = 13

    let current: Int32
    let max: Int32
    let showOverHead: Bool

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        let sub = try GatewayWire.readInt16(&reader)
        guard sub == Self.subOpcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.subOpcode, actual: sub)
        }
        current = try reader.readInt32()
        max = try reader.readInt32()
        showOverHead = try reader.readBool()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseClientUpdatePacket` (38) / `ClientUpdatePacketRemoveEffectTag` (17).
struct GatewayEffectTagRemoval: Equatable, Sendable {
    static let opcode: Int16 = 38
    static let subOpcode: Int16 = 17

    let tagID: Int32

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        let sub = try GatewayWire.readInt16(&reader)
        guard sub == Self.subOpcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.subOpcode, actual: sub)
        }
        tagID = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseQuestPacket` (49) / `QuestCompletePacket` (4).
struct GatewayQuestComplete: Equatable, Sendable {
    static let opcode: Int16 = 49
    static let subOpcode: Int32 = 4

    let questID: Int32

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        let sub = try reader.readInt32()
        guard sub == Self.subOpcode else {
            throw GatewayProtocolError.unexpectedOpcode(
                expected: Int16(Self.subOpcode),
                actual: Int16(truncatingIfNeeded: sub)
            )
        }
        questID = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseQuestPacket` (49) / `QuestFailedPacket` (5).
struct GatewayQuestFailed: Equatable, Sendable {
    static let opcode: Int16 = 49
    static let subOpcode: Int32 = 5

    let questID: Int32

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        let sub = try reader.readInt32()
        guard sub == Self.subOpcode else {
            throw GatewayProtocolError.unexpectedOpcode(
                expected: Int16(Self.subOpcode),
                actual: Int16(truncatingIfNeeded: sub)
            )
        }
        questID = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseQuestPacket` (49) / `CompletedQuestCountUpdatePacket` (12).
struct GatewayCompletedQuestCount: Equatable, Sendable {
    static let opcode: Int16 = 49
    static let subOpcode: Int32 = 12

    let count: Int32

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        let sub = try reader.readInt32()
        guard sub == Self.subOpcode else {
            throw GatewayProtocolError.unexpectedOpcode(
                expected: Int16(Self.subOpcode),
                actual: Int16(truncatingIfNeeded: sub)
            )
        }
        count = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}
