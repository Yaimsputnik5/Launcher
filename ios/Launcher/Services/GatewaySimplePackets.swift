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

/// `PetBasePacket` (53) / `PetStatusPacket` (3). The sub-opcode is one byte.
struct GatewayPetStatus: Equatable, Sendable {
    static let opcode: Int16 = 53
    static let subOpcode: UInt8 = 3

    let petID: Int32
    let hunger: Float
    let hygiene: Float
    let play: Float
    let mood: Float

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        let sub = try reader.readUInt8()
        guard sub == Self.subOpcode else {
            throw GatewayProtocolError.unexpectedInternalOpcode(
                expected: Self.subOpcode,
                actual: sub
            )
        }
        petID = try reader.readInt32()
        hunger = try reader.readFloat()
        hygiene = try reader.readFloat()
        play = try reader.readFloat()
        mood = try reader.readFloat()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `PetBasePacket` (53) / `PetActivePacket` (9). The sub-opcode is one byte.
struct GatewayPetActive: Equatable, Sendable {
    static let opcode: Int16 = 53
    static let subOpcode: UInt8 = 9

    let petID: Int32
    let petGUID: UInt64

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        let sub = try reader.readUInt8()
        guard sub == Self.subOpcode else {
            throw GatewayProtocolError.unexpectedInternalOpcode(
                expected: Self.subOpcode,
                actual: sub
            )
        }
        petID = try reader.readInt32()
        petGUID = try reader.readUInt64()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseTradePacket` (59) / `TradeUpdateCoinCountPacket` (11).
struct GatewayTradeCoinCount: Equatable, Sendable {
    static let opcode: Int16 = 59
    static let subOpcode: UInt8 = 11

    let sessionID: Int32
    let revision: Int32
    let isMine: Bool
    let offeredCoins: Int32

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        let sub = try reader.readUInt8()
        guard sub == Self.subOpcode else {
            throw GatewayProtocolError.unexpectedInternalOpcode(
                expected: Self.subOpcode,
                actual: sub
            )
        }
        sessionID = try reader.readInt32()
        revision = try reader.readInt32()
        isMine = try reader.readBool()
        offeredCoins = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseTradePacket` (59) / `TradeMessagePacket` (15).
struct GatewayTradeMessage: Equatable, Sendable {
    static let opcode: Int16 = 59
    static let subOpcode: UInt8 = 15

    let partnerDisconnected: Bool
    let completed: Bool
    let messageCode: UInt8

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        let sub = try reader.readUInt8()
        guard sub == Self.subOpcode else {
            throw GatewayProtocolError.unexpectedInternalOpcode(
                expected: Self.subOpcode,
                actual: sub
            )
        }
        partnerDisconnected = try reader.readUInt8() == 2
        completed = try reader.readUInt8() == 6
        messageCode = try reader.readUInt8()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `PacketMembershipSubscriptionInfo` (189).
struct GatewayMembershipInfo: Equatable, Sendable {
    static let opcode: Int16 = 189

    let isMember: Bool
    let isReferee: Bool

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        isMember = try reader.readBool()
        isReferee = try reader.readBool()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}
