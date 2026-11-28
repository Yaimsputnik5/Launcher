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

/// `BaseUiPacket` (47) / `ExecuteScriptPacket` (7). C# writes a string, then an
/// Int32 count followed by Int32 arguments. The name is a UI method selector;
/// decoding it must not execute a script.
struct GatewayExecuteScript: Equatable, Sendable {
    static let opcode: Int16 = 47
    static let subOpcode: UInt8 = 7
    private static let maxParameterCount = 65_536

    let script: String
    let parameters: [Int32]

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
        script = try reader.readString()
        let count = try reader.readInt32()
        guard count >= 0, count <= Self.maxParameterCount else {
            throw GatewayProtocolError.invalidCollectionCount("ExecuteScriptPacket.Params")
        }
        var decoded: [Int32] = []
        decoded.reserveCapacity(Int(count))
        for _ in 0..<Int(count) {
            decoded.append(try reader.readInt32())
        }
        parameters = decoded
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseUiPacket` (47) / `ExecuteScriptWithStringParamsPacket` (8). The C#
/// class comment names this a UI method dispatch, not Lua source execution.
struct GatewayExecuteScriptStringParams: Equatable, Sendable {
    static let opcode: Int16 = 47
    static let subOpcode: UInt8 = 8
    private static let maxParameterCount = 65_536

    let script: String
    let parameters: [String]

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
        script = try reader.readString()
        let count = try reader.readInt32()
        guard count >= 0, count <= Self.maxParameterCount else {
            throw GatewayProtocolError.invalidCollectionCount("ExecuteScriptWithStringParamsPacket.Params")
        }
        var decoded: [String] = []
        decoded.reserveCapacity(Int(count))
        for _ in 0..<Int(count) {
            decoded.append(try reader.readString())
        }
        parameters = decoded
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `PacketPointOfInterestDefinitionReply` (57). C# writes a single
/// length-prefixed payload byte array; the bytes remain undecoded raw data.
struct GatewayPOIDefinitionReply: Equatable, Sendable {
    static let opcode: Int16 = 57

    let payload: Data

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        payload = try reader.readData()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseInspectPacket` (149) / `StartInspectPacket` (1). The payload follows
/// the GUID and boolean and is preserved verbatim; no inspect content is parsed.
struct GatewayStartInspect: Equatable, Sendable {
    static let opcode: Int16 = 149
    static let subOpcode: UInt8 = 1

    let guid: UInt64
    let showPedestal: Bool
    let payload: Data

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
        showPedestal = try reader.readBool()
        payload = try reader.readData()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BasePlayerTitlePacket` (152) / `PlayerTitleUpdateAllPacket` (3). The C#
/// payload is not interpreted here; its bytes are retained as received.
struct GatewayPlayerTitleUpdateAll: Equatable, Sendable {
    static let opcode: Int16 = 152
    static let subOpcode: Int32 = 3

    let payload: Data

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
        payload = try reader.readData()
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

/// `BaseTradePacket` (59) / `TradeInvitePacket` (2). `NameData.Serialize`
/// writes three Int32 ids followed by two length-prefixed strings.
struct GatewayTradeInvite: Equatable, Sendable {
    static let opcode: Int16 = 59
    static let subOpcode: UInt8 = 2

    let inviterName: GatewayName
    let inviterGUID: UInt64
    let sessionID: Int32

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
        inviterName = try GatewayName(reader: &reader)
        inviterGUID = try reader.readUInt64()
        sessionID = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseTradePacket` (59) / `TradeStartSessionPacket` (4). The GUID is written
/// before `NameData`, unlike the invite packet.
struct GatewayTradeStartSession: Equatable, Sendable {
    static let opcode: Int16 = 59
    static let subOpcode: UInt8 = 4

    let partnerGUID: UInt64
    let partnerName: GatewayName
    let sessionID: Int32

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
        partnerGUID = try reader.readUInt64()
        partnerName = try GatewayName(reader: &reader)
        sessionID = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseTradePacket` (59) / `TradeRejectedPacket` (16).
struct GatewayTradeRejected: Equatable, Sendable {
    static let opcode: Int16 = 59
    static let subOpcode: UInt8 = 16

    let rejectingPlayer: GatewayName

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
        rejectingPlayer = try GatewayName(reader: &reader)
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

/// `BaseTradePacket` (59) / `TradeEndSessionPacket` (5). The sub-opcode is one byte.
struct GatewayTradeEndSession: Equatable, Sendable {
    static let opcode: Int16 = 59
    static let subOpcode: UInt8 = 5

    let sessionID: Int32

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
        sessionID = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `Sanctuary.Packet.Common.ItemInstance` as serialized by
/// `TradeUpdateAddItemPacket`. `ItemRecord.Serialize` writes `Definition` and
/// `Tint`; `ItemInstance.Serialize` then writes the remaining fields, a hard-coded
/// rental placeholder, and `AbilityCount`. Names come from the C# source only.
struct GatewayTradeItemInstance: Equatable, Sendable {
    let definition: Int32
    let tint: Int32
    let id: Int32
    let count: Int32
    let consumedCount: Int32
    let lastCastTime: Int32
    let rentalPlaceholder: Bool
    let abilityCount: Int32

    init(reader: inout PacketReader) throws {
        definition = try reader.readInt32()
        tint = try reader.readInt32()
        id = try reader.readInt32()
        count = try reader.readInt32()
        consumedCount = try reader.readInt32()
        lastCastTime = try reader.readInt32()
        rentalPlaceholder = try reader.readBool()
        abilityCount = try reader.readInt32()
    }
}

/// `BaseTradePacket` (59) / `TradeUpdateAddItemPacket` (12). Its nested
/// `ItemInstance.Serialize(writer)` is scalar-only, so it is decoded here
/// instead of falling back to raw bytes.
struct GatewayTradeAddItem: Equatable, Sendable {
    static let opcode: Int16 = 59
    static let subOpcode: UInt8 = 12

    let sessionID: Int32
    let revision: Int32
    let isMine: Bool
    let item: GatewayTradeItemInstance

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
        sessionID = try reader.readInt32()
        revision = try reader.readInt32()
        isMine = try reader.readBool()
        item = try GatewayTradeItemInstance(reader: &reader)
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseTradePacket` (59) / `TradeUpdateItemCountPacket` (13).
struct GatewayTradeItemCount: Equatable, Sendable {
    static let opcode: Int16 = 59
    static let subOpcode: UInt8 = 13

    let sessionID: Int32
    let revision: Int32
    let isMine: Bool
    let itemInstanceID: Int32
    let offeredTotal: Int32

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
        sessionID = try reader.readInt32()
        revision = try reader.readInt32()
        isMine = try reader.readBool()
        itemInstanceID = try reader.readInt32()
        offeredTotal = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseTradePacket` (59) / `TradeUpdateLockPacket` (17).
struct GatewayTradeLock: Equatable, Sendable {
    static let opcode: Int16 = 59
    static let subOpcode: UInt8 = 17

    let sessionID: Int32
    let locked: Bool

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
        sessionID = try reader.readInt32()
        locked = try reader.readBool()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseTradePacket` (59) / `TradeConfirmPacket` (18).
struct GatewayTradeConfirm: Equatable, Sendable {
    static let opcode: Int16 = 59
    static let subOpcode: UInt8 = 18

    let sessionID: Int32

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
        sessionID = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

// MARK: - Store bundles (66/5/1)

private enum GatewayStoreCodec {
    static let maxCollectionCount = 65_536

    static func readCount(_ reader: inout PacketReader, _ name: String) throws -> Int {
        let raw = try reader.readInt32()
        guard raw >= 0, raw <= maxCollectionCount else {
            throw GatewayProtocolError.invalidCollectionCount(name)
        }
        return Int(raw)
    }
}

/// `ImageDataDefinition.Serialize`: two length-prefixed UTF-8 strings. C#
/// writes `null` and `""` as the same zero-length field; the decoded value is
/// therefore the wire string, not a reconstructed nil.
struct GatewayStoreImageData: Equatable, Sendable {
    let image: String
    let tint: String

    init(reader: inout PacketReader) throws {
        image = try reader.readString()
        tint = try reader.readString()
    }
}

/// `MarketingBundleDefinition.Entry.Serialize`.
struct GatewayStoreMarketingEntry: Equatable, Sendable {
    let quantity: Int32
    let gameItemID: Int32
    let marketingItemID: Int32
    let imageTintOverride: String

    init(reader: inout PacketReader) throws {
        quantity = try reader.readInt32()
        gameItemID = try reader.readInt32()
        marketingItemID = try reader.readInt32()
        imageTintOverride = try reader.readString()
    }
}

/// `MarketingBundleDefinition.Serialize`. `DateTimeOffset` is written as
/// seconds since the Unix epoch by `PacketWriter`, so it is kept here as an
/// `Int64` rather than converted into an inferred local time.
struct GatewayStoreMarketingBundle: Equatable, Sendable {
    let id: Int32
    let nameID: Int32
    let descriptionID: Int32
    let status: Int32
    let image: GatewayStoreImageData
    let isTintable: Bool
    let tintGroup: String
    let currencyType: Int32
    let price: Int32
    let altCurrencyPrice: Int32
    let altPrice: Int32
    let partnerID: Int32
    let launchTimeSeconds: Int64
    let expireTimeSeconds: Int64
    let unknown: Int32
    let unknown2: Bool
    let repeatedLaunchTimeSeconds: Int64
    let repeatedExpireTimeSeconds: Int64
    let entries: [GatewayStoreMarketingEntry]

    init(reader: inout PacketReader) throws {
        id = try reader.readInt32()
        nameID = try reader.readInt32()
        descriptionID = try reader.readInt32()
        status = try reader.readInt32()
        image = try GatewayStoreImageData(reader: &reader)
        isTintable = try reader.readBool()
        tintGroup = try reader.readString()
        currencyType = try reader.readInt32()
        price = try reader.readInt32()
        altCurrencyPrice = try reader.readInt32()
        altPrice = try reader.readInt32()
        partnerID = try reader.readInt32()
        launchTimeSeconds = try reader.readInt64()
        expireTimeSeconds = try reader.readInt64()
        unknown = try reader.readInt32()
        unknown2 = try reader.readBool()
        repeatedLaunchTimeSeconds = try reader.readInt64()
        repeatedExpireTimeSeconds = try reader.readInt64()
        let count = try GatewayStoreCodec.readCount(&reader, "marketing bundle entries")
        var decoded: [GatewayStoreMarketingEntry] = []
        decoded.reserveCapacity(count)
        for _ in 0..<count {
            decoded.append(try GatewayStoreMarketingEntry(reader: &reader))
        }
        entries = decoded
    }
}

/// `StoreBundleDefinition.Serialize`, including its inherited
/// `MarketingBundleDefinition` fields.
struct GatewayStoreBundleDefinition: Equatable, Sendable {
    let marketing: GatewayStoreMarketingBundle
    let storeID: Int32
    let categoryGroupID: Int32
    let isVisible: Bool
    let maxPerOrder: Int32
    let displayOrder: Int32
    let categoryDisplayOrder: Int32
    let discountType: Int32
    let skuID: Int32
    let discountValue: Int32
    let unknown3: Int32
    let unknown4: Int32
    let termsAndConditionsID: UInt8
    let isNew: Bool
    let isViewOnly: Bool

    init(reader: inout PacketReader) throws {
        marketing = try GatewayStoreMarketingBundle(reader: &reader)
        storeID = try reader.readInt32()
        categoryGroupID = try reader.readInt32()
        isVisible = try reader.readBool()
        maxPerOrder = try reader.readInt32()
        displayOrder = try reader.readInt32()
        categoryDisplayOrder = try reader.readInt32()
        discountType = try reader.readInt32()
        skuID = try reader.readInt32()
        discountValue = try reader.readInt32()
        unknown3 = try reader.readInt32()
        unknown4 = try reader.readInt32()
        termsAndConditionsID = try reader.readUInt8()
        isNew = try reader.readBool()
        isViewOnly = try reader.readBool()
    }
}

/// `AppStoreBundleDefinition.Serialize`, including its inherited
/// `StoreBundleDefinition` fields. The write order of the final booleans differs
/// from their declaration order in C#, so the decoder follows `Serialize()`.
struct GatewayAppStoreBundleDefinition: Equatable, Sendable {
    let bundle: GatewayStoreBundleDefinition
    let memberDiscount: Int32
    let limitedSeriesID: Int32
    let isMembersOnly: Bool
    let vipRank: Int32
    let membersOnlyPrice: Int32
    let salePrice: Int32
    let isMerchantOnly: Bool
    let isLimitedTime: Bool
    let forceCanPreview: Int32
    let previewAnimID: Int32

    init(reader: inout PacketReader) throws {
        bundle = try GatewayStoreBundleDefinition(reader: &reader)
        memberDiscount = try reader.readInt32()
        limitedSeriesID = try reader.readInt32()
        isMembersOnly = try reader.readBool()
        vipRank = try reader.readInt32()
        membersOnlyPrice = try reader.readInt32()
        salePrice = try reader.readInt32()
        isMerchantOnly = try reader.readBool()
        isLimitedTime = try reader.readBool()
        forceCanPreview = try reader.readInt32()
        previewAnimID = try reader.readInt32()
    }
}

/// `StoreDefinition.Serialize`: three ints, `ImageDataDefinition`, then an
/// `IDictionary<int, AppStoreBundleDefinition>` written as an int32 count
/// followed by int32 keys and serialized values.
struct GatewayStoreDefinition: Equatable, Sendable {
    let id: Int32
    let nameID: Int32
    let descriptionID: Int32
    let image: GatewayStoreImageData
    let bundles: [Int32: GatewayAppStoreBundleDefinition]

    init(reader: inout PacketReader) throws {
        id = try reader.readInt32()
        nameID = try reader.readInt32()
        descriptionID = try reader.readInt32()
        image = try GatewayStoreImageData(reader: &reader)
        let count = try GatewayStoreCodec.readCount(&reader, "store definition bundles")
        var decoded: [Int32: GatewayAppStoreBundleDefinition] = [:]
        decoded.reserveCapacity(count)
        for _ in 0..<count {
            let key = try reader.readInt32()
            decoded[key] = try GatewayAppStoreBundleDefinition(reader: &reader)
        }
        bundles = decoded
    }
}

/// `PacketBaseInGamePurchase` (66) / `PacketInGamePurchaseStoreBundleBase` (5)
/// / `PacketInGamePurchaseStoreBundles` (internal opcode 1). The base packet
/// writes an `int SubOpCode` and `int StoreId` before `StoreDefinition`.
struct GatewayInGamePurchaseStoreBundles: Equatable, Sendable {
    static let opcode: Int16 = 66
    static let subOpcode: Int16 = 5
    static let bundlesOpcode: Int32 = 1

    let storeID: Int32
    let store: GatewayStoreDefinition

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
        let bundlesOpcode = try reader.readInt32()
        guard bundlesOpcode == Self.bundlesOpcode else {
            throw GatewayProtocolError.malformedFrame(
                "Expected store bundles internal opcode \(Self.bundlesOpcode), found \(bundlesOpcode)"
            )
        }
        storeID = try reader.readInt32()
        store = try GatewayStoreDefinition(reader: &reader)
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

// MARK: - Store categories, groups, wallet, and subscriptions (66)

/// `StoreBundleCategoryGroupDefinition.Serialize`.
struct GatewayStoreCategoryGroupDefinition: Equatable, Sendable {
    let id: Int32
    let categoryIDs: [Int32]

    init(reader: inout PacketReader) throws {
        id = try reader.readInt32()
        let count = try GatewayStoreCodec.readCount(&reader, "category group IDs")
        var decoded: [Int32] = []
        decoded.reserveCapacity(count)
        for _ in 0..<count {
            decoded.append(try reader.readInt32())
        }
        categoryIDs = decoded
    }
}

/// `PacketInGamePurchaseStoreBundleCategoryGroups` (66/6).
struct GatewayStoreCategoryGroupsPacket: Equatable, Sendable {
    static let opcode: Int16 = 66
    static let subOpcode: Int16 = 6

    let groups: [Int32: GatewayStoreCategoryGroupDefinition]

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
        let count = try GatewayStoreCodec.readCount(&reader, "store category groups")
        var decoded: [Int32: GatewayStoreCategoryGroupDefinition] = [:]
        decoded.reserveCapacity(count)
        for _ in 0..<count {
            let key = try reader.readInt32()
            decoded[key] = try GatewayStoreCategoryGroupDefinition(reader: &reader)
        }
        groups = decoded
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `StoreBundleCategoryDefinition.Serialize`.
struct GatewayStoreCategoryDefinition: Equatable, Sendable {
    let id: Int32
    let nameID: Int32
    let image: GatewayStoreImageData

    init(reader: inout PacketReader) throws {
        id = try reader.readInt32()
        nameID = try reader.readInt32()
        image = try GatewayStoreImageData(reader: &reader)
    }
}

/// `StoreBundleCategoryNode.Serialize`, including its inherited base fields.
struct GatewayStoreCategoryNode: Equatable, Sendable {
    let category: GatewayStoreCategoryDefinition
    let parentID: Int32
    let count: Int32
    let displayOrder: Int32

    init(reader: inout PacketReader) throws {
        category = try GatewayStoreCategoryDefinition(reader: &reader)
        parentID = try reader.readInt32()
        count = try reader.readInt32()
        displayOrder = try reader.readInt32()
    }
}

/// `StoreBundleCategoryTree.Serialize`.
struct GatewayStoreCategoryTree: Equatable, Sendable {
    let categories: [Int32: GatewayStoreCategoryNode]
    let sorted: Bool

    init(reader: inout PacketReader) throws {
        let count = try GatewayStoreCodec.readCount(&reader, "store category tree")
        var decoded: [Int32: GatewayStoreCategoryNode] = [:]
        decoded.reserveCapacity(count)
        for _ in 0..<count {
            let key = try reader.readInt32()
            decoded[key] = try GatewayStoreCategoryNode(reader: &reader)
        }
        categories = decoded
        sorted = try reader.readBool()
    }
}

/// `PacketInGamePurchaseStoreBundleCategories` (66/7).
struct GatewayStoreCategoriesPacket: Equatable, Sendable {
    static let opcode: Int16 = 66
    static let subOpcode: Int16 = 7

    let tree: GatewayStoreCategoryTree

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
        tree = try GatewayStoreCategoryTree(reader: &reader)
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `StoreBundleGroupDefinition.Entry.Serialize`.
struct GatewayStoreGroupEntry: Equatable, Sendable {
    let storeBundleID: Int32
    let displayOrder: Int32

    init(reader: inout PacketReader) throws {
        storeBundleID = try reader.readInt32()
        displayOrder = try reader.readInt32()
    }
}

/// `StoreBundleGroupDefinition.Serialize`. The write order of `IsExclusive`
/// and `Status` differs from their declaration order in C#, so the decoder
/// follows `Serialize()`.
struct GatewayStoreBundleGroupDefinition: Equatable, Sendable {
    let id: Int32
    let nameID: Int32
    let descriptionID: Int32
    let image: GatewayStoreImageData
    let isExclusive: Bool
    let status: Int32
    let entries: [Int32: GatewayStoreGroupEntry]

    init(reader: inout PacketReader) throws {
        id = try reader.readInt32()
        nameID = try reader.readInt32()
        descriptionID = try reader.readInt32()
        image = try GatewayStoreImageData(reader: &reader)
        isExclusive = try reader.readBool()
        status = try reader.readInt32()
        let count = try GatewayStoreCodec.readCount(&reader, "store bundle group entries")
        var decoded: [Int32: GatewayStoreGroupEntry] = [:]
        decoded.reserveCapacity(count)
        for _ in 0..<count {
            let key = try reader.readInt32()
            decoded[key] = try GatewayStoreGroupEntry(reader: &reader)
        }
        entries = decoded
    }
}

/// `PacketInGamePurchaseStoreBundleGroups` (66/9).
struct GatewayStoreBundleGroupsPacket: Equatable, Sendable {
    static let opcode: Int16 = 66
    static let subOpcode: Int16 = 9

    let groups: [Int32: GatewayStoreBundleGroupDefinition]

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
        let count = try GatewayStoreCodec.readCount(&reader, "store bundle groups")
        var decoded: [Int32: GatewayStoreBundleGroupDefinition] = [:]
        decoded.reserveCapacity(count)
        for _ in 0..<count {
            let key = try reader.readInt32()
            decoded[key] = try GatewayStoreBundleGroupDefinition(reader: &reader)
        }
        groups = decoded
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `WalletInfo.Serialize`. C# writes both strings with a maximum length of 8,
/// but the wire representation remains an int32 byte count followed by bytes.
struct GatewayStoreWalletInfo: Equatable, Sendable {
    let unknown: Bool
    let stationCash: Int32
    let creditCardID: Int32
    let currencyCode: String
    let unknown5: String
    let international: Bool

    init(reader: inout PacketReader) throws {
        unknown = try reader.readBool()
        stationCash = try reader.readInt32()
        creditCardID = try reader.readInt32()
        currencyCode = try reader.readString()
        unknown5 = try reader.readString()
        international = try reader.readBool()
    }
}

/// `PacketInGamePurchaseWalletInfoResponse` (66/11).
struct GatewayStoreWalletInfoResponse: Equatable, Sendable {
    static let opcode: Int16 = 66
    static let subOpcode: Int16 = 11

    let errorCode: Int32
    let wallet: GatewayStoreWalletInfo

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
        errorCode = try reader.readInt32()
        wallet = try GatewayStoreWalletInfo(reader: &reader)
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `MembershipSkuData.Serialize`.
struct GatewayMembershipSKU: Equatable, Sendable {
    let sku: String
    let name: String
    let description: String
    let previewLegalText: String
    let marketingDescription: String
    let productLegalText: String
    let priceLocalCurrency: Int32
    let priceStationCash: Int32
    let unknown9: Int32
    let isVatTaxable: Bool

    init(reader: inout PacketReader) throws {
        sku = try reader.readString()
        name = try reader.readString()
        description = try reader.readString()
        previewLegalText = try reader.readString()
        marketingDescription = try reader.readString()
        productLegalText = try reader.readString()
        priceLocalCurrency = try reader.readInt32()
        priceStationCash = try reader.readInt32()
        unknown9 = try reader.readInt32()
        isVatTaxable = try reader.readBool()
    }
}

/// `PacketInGamePurchaseSubscriptionProductsResponse` (66/23). C# writes the
/// SKU list only when `ErrorCode == 1`; other error codes leave no list bytes.
struct GatewaySubscriptionProductsResponse: Equatable, Sendable {
    static let opcode: Int16 = 66
    static let subOpcode: Int16 = 23

    let errorCode: Int32
    let locale: String
    let membershipSKUs: [GatewayMembershipSKU]

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
        errorCode = try reader.readInt32()
        locale = try reader.readString()
        if errorCode == 1 {
            let count = try GatewayStoreCodec.readCount(&reader, "membership SKUs")
            var decoded: [GatewayMembershipSKU] = []
            decoded.reserveCapacity(count)
            for _ in 0..<count {
                decoded.append(try GatewayMembershipSKU(reader: &reader))
            }
            membershipSKUs = decoded
        } else {
            membershipSKUs = []
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `SaleDisplayInfo.Serialize`.
struct GatewaySaleDisplayInfo: Equatable, Sendable {
    let id: Int32
    let iconID: Int32
    let tintID: Int32
    let titleID: Int32
    let bodyID: Int32
    let secondsLeft: Int32
    let unknown: Int32
    let isMembership: Bool

    init(reader: inout PacketReader) throws {
        id = try reader.readInt32()
        iconID = try reader.readInt32()
        tintID = try reader.readInt32()
        titleID = try reader.readInt32()
        bodyID = try reader.readInt32()
        secondsLeft = try reader.readInt32()
        unknown = try reader.readInt32()
        isMembership = try reader.readBool()
    }
}

/// `InGamePurchaseUpdateSaleDisplay` (66/40).
struct GatewaySaleDisplayUpdate: Equatable, Sendable {
    static let opcode: Int16 = 66
    static let subOpcode: Int16 = 40

    let sales: [GatewaySaleDisplayInfo]

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
        let count = try GatewayStoreCodec.readCount(&reader, "sale displays")
        var decoded: [GatewaySaleDisplayInfo] = []
        decoded.reserveCapacity(count)
        for _ in 0..<count {
            decoded.append(try GatewaySaleDisplayInfo(reader: &reader))
        }
        sales = decoded
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

// MARK: - Additional commerce responses (66)

/// `PacketInGamePurchasePreviewOrderResponse` (66/2). All four fields are Int32.
struct GatewayStorePreviewOrderResponse: Equatable, Sendable {
    static let opcode: Int16 = 66
    static let subOpcode: Int16 = 2

    let orderTrackingID: Int32
    let result: Int32
    let discount: Int32
    let total: Int32

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
        orderTrackingID = try reader.readInt32()
        result = try reader.readInt32()
        discount = try reader.readInt32()
        total = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `PacketInGamePurchasePlaceOrderResponse` (66/4). C# casts the enum result
/// to `int`, so the wire field is decoded as an Int32 rather than guessing the
/// enum's semantics.
struct GatewayStorePlaceOrderResponse: Equatable, Sendable {
    static let opcode: Int16 = 66
    static let subOpcode: Int16 = 4

    let orderTrackingID: Int32
    let result: Int32
    let orderID: String
    let discount: Int32
    let total: Int32

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
        orderTrackingID = try reader.readInt32()
        result = try reader.readInt32()
        orderID = try reader.readString()
        discount = try reader.readInt32()
        total = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `CurrencyCodeData.Serialize`.
struct GatewayCurrencyCode: Equatable, Sendable {
    let code: String
    let symbol: String
    let separator: String
    let name: String
    let minorUnit: Int32
    let decimals: Int32
    let unknown: Bool

    init(reader: inout PacketReader) throws {
        code = try reader.readString()
        symbol = try reader.readString()
        separator = try reader.readString()
        name = try reader.readString()
        minorUnit = try reader.readInt32()
        decimals = try reader.readInt32()
        unknown = try reader.readBool()
    }
}

/// `PacketInGamePurchaseCurrencyCodesResponse` (66/17). The dictionary is
/// written only when `ErrorCode == 1`; its UInt32 key is written raw by C#.
struct GatewayCurrencyCodesResponse: Equatable, Sendable {
    static let opcode: Int16 = 66
    static let subOpcode: Int16 = 17

    let errorCode: Int32
    let locale: String
    let currencies: [UInt32: GatewayCurrencyCode]

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
        errorCode = try reader.readInt32()
        locale = try reader.readString()
        if errorCode == 1 {
            let count = try GatewayStoreCodec.readCount(&reader, "currency codes")
            var decoded: [UInt32: GatewayCurrencyCode] = [:]
            decoded.reserveCapacity(count)
            for _ in 0..<count {
                let key = try reader.readUInt32()
                decoded[key] = try GatewayCurrencyCode(reader: &reader)
            }
            currencies = decoded
        } else {
            currencies = [:]
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `StateCode.Serialize`.
struct GatewayStateCode: Equatable, Sendable {
    let code: String
    let name: String

    init(reader: inout PacketReader) throws {
        code = try reader.readString()
        name = try reader.readString()
    }
}

/// `PacketInGamePurchaseStateCodesResponse` (66/19). Unlike the other code
/// responses, C# does not write a locale before the conditional list.
struct GatewayStateCodesResponse: Equatable, Sendable {
    static let opcode: Int16 = 66
    static let subOpcode: Int16 = 19

    let errorCode: Int32
    let states: [GatewayStateCode]

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
        errorCode = try reader.readInt32()
        if errorCode == 1 {
            let count = try GatewayStoreCodec.readCount(&reader, "state codes")
            var decoded: [GatewayStateCode] = []
            decoded.reserveCapacity(count)
            for _ in 0..<count {
                decoded.append(try GatewayStateCode(reader: &reader))
            }
            states = decoded
        } else {
            states = []
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `CountryCode.Serialize`.
struct GatewayCountryCode: Equatable, Sendable {
    let code: String
    let language: String
    let locale: String
    let name: String

    init(reader: inout PacketReader) throws {
        code = try reader.readString()
        language = try reader.readString()
        locale = try reader.readString()
        name = try reader.readString()
    }
}

/// `PacketInGamePurchaseCountryCodesResponse` (66/21). The list is written
/// only when `ErrorCode == 1`.
struct GatewayCountryCodesResponse: Equatable, Sendable {
    static let opcode: Int16 = 66
    static let subOpcode: Int16 = 21

    let errorCode: Int32
    let locale: String
    let countries: [GatewayCountryCode]

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
        errorCode = try reader.readInt32()
        locale = try reader.readString()
        if errorCode == 1 {
            let count = try GatewayStoreCodec.readCount(&reader, "country codes")
            var decoded: [GatewayCountryCode] = []
            decoded.reserveCapacity(count)
            for _ in 0..<count {
                decoded.append(try GatewayCountryCode(reader: &reader))
            }
            countries = decoded
        } else {
            countries = []
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `PacketInGamePurchaseAccountInfoResponse` (66/26).
struct GatewayStoreAccountInfoResponse: Equatable, Sendable {
    static let opcode: Int16 = 66
    static let subOpcode: Int16 = 26

    let errorCode: Int32
    let defaultCountryCode: String
    let defaultCurrencyCode: String
    let isParentalPasswordEnabled: Bool

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
        errorCode = try reader.readInt32()
        defaultCountryCode = try reader.readString()
        defaultCurrencyCode = try reader.readString()
        isParentalPasswordEnabled = try reader.readBool()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `PacketInGamePurchaseStoreBundleContentResponse.ResponseData.Serialize`.
struct GatewayStoreBundleContentResponseItem: Equatable, Sendable {
    let storeID: Int32
    let bundleID: Int32

    init(reader: inout PacketReader) throws {
        storeID = try reader.readInt32()
        bundleID = try reader.readInt32()
    }
}

/// `PacketInGamePurchaseStoreBundleContentResponse` (66/28).
struct GatewayStoreBundleContentResponse: Equatable, Sendable {
    static let opcode: Int16 = 66
    static let subOpcode: Int16 = 28

    let responses: [GatewayStoreBundleContentResponseItem]

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
        let count = try GatewayStoreCodec.readCount(&reader, "store bundle content responses")
        var decoded: [GatewayStoreBundleContentResponseItem] = []
        decoded.reserveCapacity(count)
        for _ in 0..<count {
            decoded.append(try GatewayStoreBundleContentResponseItem(reader: &reader))
        }
        responses = decoded
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `InGamePurchaseUpdateItemRequirementsReply.UpdateData.Serialize`.
struct GatewayStoreItemRequirementUpdate: Equatable, Sendable {
    let bundleID: Int32
    let canPurchase: Bool

    init(reader: inout PacketReader) throws {
        bundleID = try reader.readInt32()
        canPurchase = try reader.readBool()
    }
}

/// `InGamePurchaseUpdateItemRequirementsReply` (66/39).
struct GatewayStoreItemRequirementsReply: Equatable, Sendable {
    static let opcode: Int16 = 66
    static let subOpcode: Int16 = 39

    let itemRequirements: [GatewayStoreItemRequirementUpdate]

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
        let count = try GatewayStoreCodec.readCount(&reader, "store item requirements")
        var decoded: [GatewayStoreItemRequirementUpdate] = []
        decoded.reserveCapacity(count)
        for _ in 0..<count {
            decoded.append(try GatewayStoreItemRequirementUpdate(reader: &reader))
        }
        itemRequirements = decoded
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

// MARK: - Server broadcast and housing zone data

/// `BaseBroadcastPacket` (77) / `BroadcastPacketZone` (2). `NameData` is the
/// verified three-Int32-id/two-string codec shared with chat packets.
struct GatewayZoneBroadcast: Equatable, Sendable {
    static let opcode: Int16 = 77
    static let subOpcode: Int16 = 2

    let name: GatewayName
    let message: String
    let messageID: Int32

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
        name = try GatewayName(reader: &reader)
        message = try reader.readString()
        messageID = try reader.readInt32()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `PlayerHousingInstanceInfo.Serialize`. C# writes `HouseName` before
/// `OwnerName` despite their declaration order, and writes each
/// `DateTimeOffset` as Int64 seconds since the Unix epoch.
struct GatewayPlayerHousingInstanceInfo: Equatable, Sendable {
    let ownerGUID: UInt64
    let instanceGUID: UInt64
    let nameID: Int32
    let houseName: String
    let ownerName: String
    let iconID: Int32
    let fixtureCount: Int32
    let furnitureScore: Int32
    let lastVisitedSeconds: Int64
    let isLocked: Bool
    let isMembersOnly: Bool
    let isFloraAllowed: Bool
    let description: String
    let keywordList: String
    let unknown21: String
    let rating: Float
    let votes: Int32
    let hasRating: Bool
    let canVote: Bool
    let factoryPlotID: Int32
    let whenCreatedSeconds: Int64

    init(reader: inout PacketReader) throws {
        ownerGUID = try reader.readUInt64()
        instanceGUID = try reader.readUInt64()
        nameID = try reader.readInt32()
        houseName = try reader.readString()
        ownerName = try reader.readString()
        iconID = try reader.readInt32()
        fixtureCount = try reader.readInt32()
        furnitureScore = try reader.readInt32()
        lastVisitedSeconds = try reader.readInt64()
        isLocked = try reader.readBool()
        isMembersOnly = try reader.readBool()
        isFloraAllowed = try reader.readBool()
        description = try reader.readString()
        keywordList = try reader.readString()
        unknown21 = try reader.readString()
        rating = try reader.readFloat()
        votes = try reader.readInt32()
        hasRating = try reader.readBool()
        canVote = try reader.readBool()
        factoryPlotID = try reader.readInt32()
        whenCreatedSeconds = try reader.readInt64()
    }
}

/// `BaseHousingPacket` (127) / `HousingPacketInstanceList` (39). C# writes an
/// Int32 count followed by each `PlayerHousingInstanceInfo.Serialize`, then the
/// player GUID.
struct GatewayHousingInstanceList: Equatable, Sendable {
    static let opcode: Int16 = 127
    static let subOpcode: Int16 = 39
    private static let maxInstanceCount = 65_536

    let instances: [GatewayPlayerHousingInstanceInfo]
    let playerGUID: UInt64

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
        let count = try reader.readInt32()
        guard count >= 0, count <= Self.maxInstanceCount else {
            throw GatewayProtocolError.invalidCollectionCount("HousingPacketInstanceList.Instances")
        }
        var decoded: [GatewayPlayerHousingInstanceInfo] = []
        decoded.reserveCapacity(Int(count))
        for _ in 0..<Int(count) {
            decoded.append(try GatewayPlayerHousingInstanceInfo(reader: &reader))
        }
        instances = decoded
        playerGUID = try reader.readUInt64()
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseHousingPacket` (127) / `HousingPacketZoneData` (45).
struct GatewayHousingZoneData: Equatable, Sendable {
    static let opcode: Int16 = 127
    static let subOpcode: Int16 = 45

    let isPreview: Bool
    let unused: Bool
    let headSize: Int32
    let instanceInfo: GatewayPlayerHousingInstanceInfo

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
        isPreview = try reader.readBool()
        unused = try reader.readBool()
        headSize = try reader.readInt32()
        instanceInfo = try GatewayPlayerHousingInstanceInfo(reader: &reader)
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}
