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

// MARK: - Additional top-level scalar packets

/// `PacketWorldShutdownNotice` (92).
struct GatewayWorldShutdownNotice: Equatable, Sendable {
    static let opcode: Int16 = 92

    let timeRemaining: Int32
    let reason: String
    let reasonID: Int32

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        timeRemaining = try reader.readInt32()
        reason = try reader.readString()
        reasonID = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `PacketPOIChangeMessage` (104).
struct GatewayPOIChange: Equatable, Sendable {
    static let opcode: Int16 = 104

    let nameID: Int32
    let zoneID: Int32
    let areaID: Int32

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        nameID = try reader.readInt32()
        zoneID = try reader.readInt32()
        areaID = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

// MARK: - Additional client-update packets (38)

/// `BaseClientUpdatePacket` (38) / `ClientUpdatePacketCoinCount` (19).
struct GatewayCoinCount: Equatable, Sendable {
    static let opcode: Int16 = 38
    static let subOpcode: Int16 = 19

    let coins: Int32

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
        coins = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseClientUpdatePacket` (38) / `ClientUpdatePacketItemDelete` (4).
struct GatewayItemDelete: Equatable, Sendable {
    static let opcode: Int16 = 38
    static let subOpcode: Int16 = 4

    let itemGUID: Int32

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
        itemGUID = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseClientUpdatePacket` (38) / `ClientUpdatePacketUnequipSlot` (6).
struct GatewaySlotUnequip: Equatable, Sendable {
    static let opcode: Int16 = 38
    static let subOpcode: Int16 = 6

    let slot: Int32
    let profileID: Int32

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
        slot = try reader.readInt32()
        profileID = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseClientUpdatePacket` (38) / `ClientUpdatePacketItemUpdate` (3).
struct GatewayItemUpdate: Equatable, Sendable {
    static let opcode: Int16 = 38
    static let subOpcode: Int16 = 3

    let itemGUID: Int32
    let count: Int32
    let actionBarID: Int32
    let consumedCount: Int32
    let abilityCount: Int32
    let rentalExpirationTime: Int64

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
        itemGUID = try reader.readInt32()
        count = try reader.readInt32()
        actionBarID = try reader.readInt32()
        consumedCount = try reader.readInt32()
        abilityCount = try reader.readInt32()
        rentalExpirationTime = try reader.readInt64()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseClientUpdatePacket` (38) / `ClientUpdatePacketImmediateActivationCheck` (30).
struct GatewayImmediateActivationCheck: Equatable, Sendable {
    static let opcode: Int16 = 38
    static let subOpcode: Int16 = 30

    let itemGUID: Int32
    let categoryID: Int32
    let bundleID: Int32
    let titleStringID: Int32
    let bodyStringID: Int32
    let success: Bool

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
        itemGUID = try reader.readInt32()
        categoryID = try reader.readInt32()
        bundleID = try reader.readInt32()
        titleStringID = try reader.readInt32()
        bodyStringID = try reader.readInt32()
        success = try reader.readBool()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

// MARK: - Additional quest packets (49)

/// `BaseQuestPacket` (49) / `QuestAbandonedPacket` (6). The C# writer sends a
/// literal `false` after the quest ID; the field is kept verbatim.
struct GatewayQuestAbandoned: Equatable, Sendable {
    static let opcode: Int16 = 49
    static let subOpcode: Int32 = 6

    let questID: Int32
    let literalFalse: Bool

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
        literalFalse = try reader.readBool()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseQuestPacket` (49) / `QuestEndBlockedPacket` (16).
struct GatewayQuestEndBlocked: Equatable, Sendable {
    static let opcode: Int16 = 49
    static let subOpcode: Int32 = 16

    let npcGUID: UInt64
    let questID: Int32
    let textID: Int32

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
        npcGUID = try reader.readUInt64()
        questID = try reader.readInt32()
        textID = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

// MARK: - Additional friend packets (74)

/// `BaseFriendPacket` (74) / `FriendOfflinePacket` (3).
struct GatewayFriendOffline: Equatable, Sendable {
    static let opcode: Int16 = 74
    static let subOpcode: UInt8 = 3

    let guid: UInt64

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        let sub = try reader.readUInt8()
        guard sub == Self.subOpcode else {
            throw GatewayProtocolError.unexpectedInternalOpcode(expected: Self.subOpcode, actual: sub)
        }
        guid = try reader.readUInt64()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseFriendPacket` (74) / `FriendRemovePacket` (7).
struct GatewayFriendRemove: Equatable, Sendable {
    static let opcode: Int16 = 74
    static let subOpcode: UInt8 = 7

    let guid: UInt64

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        let sub = try reader.readUInt8()
        guard sub == Self.subOpcode else {
            throw GatewayProtocolError.unexpectedInternalOpcode(expected: Self.subOpcode, actual: sub)
        }
        guid = try reader.readUInt64()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseFriendPacket` (74) / `FriendRenamePacket` (10).
struct GatewayFriendRename: Equatable, Sendable {
    static let opcode: Int16 = 74
    static let subOpcode: UInt8 = 10

    let name: String
    let guid: UInt64

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        let sub = try reader.readUInt8()
        guard sub == Self.subOpcode else {
            throw GatewayProtocolError.unexpectedInternalOpcode(expected: Self.subOpcode, actual: sub)
        }
        name = try reader.readString()
        guid = try reader.readUInt64()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

// MARK: - Additional chat packets (15)

/// `BaseChatPacket` (15) / `ChatPacketEnterArea` (2).
struct GatewayChatEnterArea: Equatable, Sendable {
    static let opcode: Int16 = 15
    static let subOpcode: Int16 = 2

    let areaNameID: Int32

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
        areaNameID = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseChatPacket` (15) / `ChatPacketFromStringId` (4). The string ID is kept
/// as a numeric ID; no localized text is fabricated by the client.
struct GatewayChatFromStringID: Equatable, Sendable {
    static let opcode: Int16 = 15
    static let subOpcode: Int16 = 4

    let speakerGUID: UInt64
    let stringID: Int32
    let isEmote: Bool
    let isChatLogged: Bool
    let hasColor: Bool
    let colorID: Int32
    let targetGUID: UInt64
    let ownerGUID: UInt64
    let elapsedTime: Int32

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
        speakerGUID = try reader.readUInt64()
        stringID = try reader.readInt32()
        isEmote = try reader.readBool()
        isChatLogged = try reader.readBool()
        hasColor = try reader.readBool()
        colorID = try reader.readInt32()
        targetGUID = try reader.readUInt64()
        ownerGUID = try reader.readUInt64()
        elapsedTime = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

// MARK: - Ability packets (36)

/// `BaseAbilityPacket` (36) / `AbilityPacketFailed` (1).
struct GatewayAbilityFailed: Equatable, Sendable {
    static let opcode: Int16 = 36
    static let subOpcode: Int16 = 1

    let stringID: Int32

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
        stringID = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseAbilityPacket` (36) / `AbilityPacketStartCasting` (3). The C# field
/// named `Unused` is preserved verbatim.
struct GatewayAbilityStartCasting: Equatable, Sendable {
    static let opcode: Int16 = 36
    static let subOpcode: Int16 = 3

    let casterGUID: UInt64
    let unused: UInt64
    let compositeEffectID: Int32
    let animation: Int32
    let abilityID: Int32
    let actionTime: Float
    let hasActionProgress: Bool

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
        casterGUID = try reader.readUInt64()
        unused = try reader.readUInt64()
        compositeEffectID = try reader.readInt32()
        animation = try reader.readInt32()
        abilityID = try reader.readInt32()
        actionTime = try reader.readFloat()
        hasActionProgress = try reader.readBool()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

// MARK: - Additional scalar-only player updates (35)

/// `BasePlayerUpdatePacket` (35) / `PlayerUpdatePacketUpdateWalkAnim` (21).
struct GatewayWalkAnimationUpdate: Equatable, Sendable {
    static let opcode: Int16 = 35
    static let subOpcode: Int16 = 21

    let guid: UInt64
    let animation: Int32

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
        animation = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BasePlayerUpdatePacket` (35) / `PlayerUpdatePacketUpdateIdleAnim` (26).
struct GatewayIdleAnimationUpdate: Equatable, Sendable {
    static let opcode: Int16 = 35
    static let subOpcode: Int16 = 26

    let guid: UInt64
    let animationID: Int32

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
        animationID = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BasePlayerUpdatePacket` (35) / `PlayerUpdatePacketSetAnimation` (8).
/// `Unknown` and `Flags` are kept with their source names and wire types.
struct GatewaySetAnimation: Equatable, Sendable {
    static let opcode: Int16 = 35
    static let subOpcode: Int16 = 8

    let guid: UInt64
    let animationID: Int32
    let unknown: Int32
    let flags: UInt8

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
        animationID = try reader.readInt32()
        unknown = try reader.readInt32()
        flags = try reader.readUInt8()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BasePlayerUpdatePacket` (35) /
/// `PlayerUpdatePacketRemoveEffectTagCompositeEffect` (42).
struct GatewayRemoveCompositeEffectTag: Equatable, Sendable {
    static let opcode: Int16 = 35
    static let subOpcode: Int16 = 42

    let guid: UInt64
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
        guid = try reader.readUInt64()
        tagID = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BasePlayerUpdatePacket` (35) /
/// `PlayerUpdatePacketEffectTagCompositeEffectsEnable` (43).
struct GatewayCompositeEffectsEnabled: Equatable, Sendable {
    static let opcode: Int16 = 35
    static let subOpcode: Int16 = 43

    let enabled: Bool

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
        enabled = try reader.readBool()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BasePlayerUpdatePacket` (35) /
/// `PlayerUpdatePacketAddEffectTagCompositeEffect` (41). Fields named
/// `Unknown`/`Unknown2` are preserved verbatim.
struct GatewayAddCompositeEffectTag: Equatable, Sendable {
    static let opcode: Int16 = 35
    static let subOpcode: Int16 = 41

    let guid: UInt64
    let tagID: Int32
    let compositeEffectID: Int32
    let sourceGUID: UInt64
    let unknown: Int32
    let unknown2: Int32

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
        tagID = try reader.readInt32()
        compositeEffectID = try reader.readInt32()
        sourceGUID = try reader.readUInt64()
        unknown = try reader.readInt32()
        unknown2 = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BasePlayerUpdatePacket` (35) / `PlayerUpdatePacketQueueAnimation` (22).
/// Unknown literals are absent; all fields below are written by C#.
struct GatewayQueuedAnimation: Equatable, Sendable {
    static let opcode: Int16 = 35
    static let subOpcode: Int16 = 22

    let guid: UInt64
    let animationGroupID: Int32
    let loopCount: Int32
    let playbackSpeed: Float
    let delay: Float
    let endTime: Float
    let easeOutLoopingAnimations: Bool
    let useTransitions: Bool
    let useAnimationPriority: Bool

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
        animationGroupID = try reader.readInt32()
        loopCount = try reader.readInt32()
        playbackSpeed = try reader.readFloat()
        delay = try reader.readFloat()
        endTime = try reader.readFloat()
        easeOutLoopingAnimations = try reader.readBool()
        useTransitions = try reader.readBool()
        useAnimationPriority = try reader.readBool()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `PetBasePacket` (53) / `PetUtilityNotifyPacket` (20). Unknown4/5/6 are
/// preserved with the C# names because their semantics are not defined there.
struct GatewayPetUtilityNotification: Equatable, Sendable {
    static let opcode: Int16 = 53
    static let subOpcode: UInt8 = 20

    let petID: Int32
    let notificationType: Int32
    let groomDurationSeconds: Int32
    let unknown4: Int32
    let unknown5: Int32
    let unknown6: Int32

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        let sub = try reader.readUInt8()
        guard sub == Self.subOpcode else {
            throw GatewayProtocolError.unexpectedInternalOpcode(expected: Self.subOpcode, actual: sub)
        }
        petID = try reader.readInt32()
        notificationType = try reader.readInt32()
        groomDurationSeconds = try reader.readInt32()
        unknown4 = try reader.readInt32()
        unknown5 = try reader.readInt32()
        unknown6 = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `PacketBaseInGamePurchase` (66) /
/// `PacketInGamePurchaseStoreEnablePaymentSources` (33).
struct GatewayInGamePurchasePaymentSources: Equatable, Sendable {
    static let opcode: Int16 = 66
    static let subOpcode: Int16 = 33

    let sms: Bool
    let paypal: Bool

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
        sms = try reader.readBool()
        paypal = try reader.readBool()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `PacketBaseInGamePurchase` (66) / `PacketInGamePurchaseEnableMarketplace` (24).
struct GatewayInGamePurchaseMarketplace: Equatable, Sendable {
    static let opcode: Int16 = 66
    static let subOpcode: Int16 = 24

    let enabled: Bool

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
        enabled = try reader.readBool()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseUiPacket` (47) / `ObjectiveTargetUpdatePacket` (14). The C# serializer
/// writes the target fields only when `Active` is true; the decoder mirrors that
/// branch and leaves the optionals nil otherwise.
struct GatewayObjectiveTargetUpdate: Equatable, Sendable {
    static let opcode: Int16 = 47
    static let subOpcode: UInt8 = 14

    let active: Bool
    let taskID: UInt64?
    let selectTaskID: Int32?
    let guid: UInt64?
    let nameID: Int32?
    let positionX: Float?
    let positionY: Float?
    let positionZ: Float?
    let positionW: Float?
    let targetType: Int32?

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        let sub = try reader.readUInt8()
        guard sub == Self.subOpcode else {
            throw GatewayProtocolError.unexpectedInternalOpcode(expected: Self.subOpcode, actual: sub)
        }
        active = try reader.readBool()
        var taskID: UInt64?
        var selectTaskID: Int32?
        var guid: UInt64?
        var nameID: Int32?
        var positionX: Float?
        var positionY: Float?
        var positionZ: Float?
        var positionW: Float?
        var targetType: Int32?
        if active {
            taskID = try reader.readUInt64()
            selectTaskID = try reader.readInt32()
            guid = try reader.readUInt64()
            nameID = try reader.readInt32()
            positionX = try reader.readFloat()
            positionY = try reader.readFloat()
            positionZ = try reader.readFloat()
            positionW = try reader.readFloat()
            targetType = try reader.readInt32()
        }
        self.taskID = taskID
        self.selectTaskID = selectTaskID
        self.guid = guid
        self.nameID = nameID
        self.positionX = positionX
        self.positionY = positionY
        self.positionZ = positionZ
        self.positionW = positionW
        self.targetType = targetType
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseObjectivePacket` (45) / `ObjectiveClientClearPacket` (8).
struct GatewayObjectiveClientClear: Equatable, Sendable {
    static let opcode: Int16 = 45
    static let subOpcode: UInt8 = 8

    let unknown: Int32

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        let sub = try reader.readUInt8()
        guard sub == Self.subOpcode else {
            throw GatewayProtocolError.unexpectedInternalOpcode(expected: Self.subOpcode, actual: sub)
        }
        unknown = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}
