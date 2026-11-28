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

// MARK: - Player update family (35)

/// `BasePlayerUpdatePacket` (35) / `PlayerUpdatePacketSetLookAt` (17).
struct GatewayLookAtTarget: Equatable, Sendable {
    static let opcode: Int16 = 35
    static let subOpcode: Int16 = 17

    let guid: UInt64
    let targetGUID: UInt64

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
        guid = try reader.readUInt64()
        targetGUID = try reader.readUInt64()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BasePlayerUpdatePacket` (35) / `PlayerUpdatePacketExpectedSpeed` (23).
struct GatewayExpectedSpeed: Equatable, Sendable {
    static let opcode: Int16 = 35
    static let subOpcode: Int16 = 23

    let guid: UInt64
    let expectedSpeed: Float

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
        guid = try reader.readUInt64()
        expectedSpeed = try reader.readFloat()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BasePlayerUpdatePacket` (35) / `PlayerUpdatePacketThoughtBubble` (27).
struct GatewayThoughtBubble: Equatable, Sendable {
    static let opcode: Int16 = 35
    static let subOpcode: Int16 = 27

    let guid: UInt64
    let iconID: Int32
    let durationSeconds: Int32
    let clear: Bool

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
        guid = try reader.readUInt64()
        iconID = try reader.readInt32()
        durationSeconds = try reader.readInt32()
        clear = try reader.readBool()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BasePlayerUpdatePacket` (35) / `PlayerUpdatePacketSetCollidable` (50).
struct GatewayCollidableUpdate: Equatable, Sendable {
    static let opcode: Int16 = 35
    static let subOpcode: Int16 = 50

    let guid: UInt64
    let collidable: Bool

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
        guid = try reader.readUInt64()
        collidable = try reader.readBool()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

// MARK: - Friend family (74)

/// `BaseFriendPacket` (74) / `FriendOnlinePacket` (2). A null or empty name is
/// serialized as a zero byte count and is therefore indistinguishable from "".
struct GatewayFriendOnline: Equatable, Sendable {
    static let opcode: Int16 = 74
    static let subOpcode: UInt8 = 2

    let name: String
    let guid: UInt64
    let isLocal: Bool

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
        name = try reader.readString()
        guid = try reader.readUInt64()
        isLocal = try reader.readBool()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

// MARK: - Mount family (168)

/// `MountBasePacket` (168) / `PacketMountResponse` (2). The `unknown` field is
/// preserved verbatim because the C# source does not name its semantics.
struct GatewayMountState: Equatable, Sendable {
    static let opcode: Int16 = 168
    static let subOpcode: UInt8 = 2

    let riderGUID: UInt64
    let mountGUID: UInt64
    let seat: Int32
    let queuePosition: Int32
    let unknown: Int32
    let compositeEffectID: Int32
    let nameVerticalOffset: Float

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
        riderGUID = try reader.readUInt64()
        mountGUID = try reader.readUInt64()
        seat = try reader.readInt32()
        queuePosition = try reader.readInt32()
        unknown = try reader.readInt32()
        compositeEffectID = try reader.readInt32()
        nameVerticalOffset = try reader.readFloat()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `MountBasePacket` (168) / `PacketDismountResponse` (4).
struct GatewayDismount: Equatable, Sendable {
    static let opcode: Int16 = 168
    static let subOpcode: UInt8 = 4

    let riderGUID: UInt64
    let compositeEffectID: Int32

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
        riderGUID = try reader.readUInt64()
        compositeEffectID = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

// MARK: - Additional quest objectives (49)

/// `BaseQuestPacket` (49) / `QuestObjectiveActivatedPacket` (8).
struct GatewayQuestObjectiveActivated: Equatable, Sendable {
    static let opcode: Int16 = 49
    static let subOpcode: Int32 = 8

    let questID: Int32
    let objectiveID: Int32
    let requiredCount: Int32
    let unknown2: Bool

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
        objectiveID = try reader.readInt32()
        requiredCount = try reader.readInt32()
        unknown2 = try reader.readBool()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseQuestPacket` (49) / `QuestObjectiveUpdatePacket` (9).
struct GatewayQuestObjectiveUpdate: Equatable, Sendable {
    static let opcode: Int16 = 49
    static let subOpcode: Int32 = 9

    let questID: Int32
    let objectiveID: Int32
    let currentCount: Int32
    let completedPercentage: Float
    let silent: Bool
    let unknown6: Int32

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
        objectiveID = try reader.readInt32()
        currentCount = try reader.readInt32()
        completedPercentage = try reader.readFloat()
        silent = try reader.readBool()
        unknown6 = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseQuestPacket` (49) / `QuestObjectiveCompletePacket` (10).
struct GatewayQuestObjectiveComplete: Equatable, Sendable {
    static let opcode: Int16 = 49
    static let subOpcode: Int32 = 10

    let questID: Int32
    let objectiveID: Int32
    let percent: Float
    let compositeEffectID: Int32
    let silent: Bool

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
        objectiveID = try reader.readInt32()
        percent = try reader.readFloat()
        compositeEffectID = try reader.readInt32()
        silent = try reader.readBool()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseQuestPacket` (49) / `QuestObjectiveFailedPacket` (11).
struct GatewayQuestObjectiveFailed: Equatable, Sendable {
    static let opcode: Int16 = 49
    static let subOpcode: Int32 = 11

    let questID: Int32
    let objectiveID: Int32

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
        objectiveID = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `PetBasePacket` (53) / `PetTrickNotifyPacket` (15). Unknown5 is preserved
/// verbatim because the C# source does not name its semantics.
struct GatewayPetTrickNotification: Equatable, Sendable {
    static let opcode: Int16 = 53
    static let subOpcode: UInt8 = 15

    let petID: Int32
    let notificationType: Int32
    let trickID: Int32
    let nameID: Int32
    let unknown5: Int32

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
        notificationType = try reader.readInt32()
        trickID = try reader.readInt32()
        nameID = try reader.readInt32()
        unknown5 = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}
