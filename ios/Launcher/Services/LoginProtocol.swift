import Foundation

// Pure message encoding/decoding for the Sanctuary `LoginUdp_6` handshake.
//
// Matched to these C# sources (Sanctuary fork under /tmp/opencode/sanctuary/src):
// - Sanctuary.Login/LoginConnection.cs: RC4 is applied directly to the
//   application packet; outbound packets always use UdpChannel.Reliable1.
// - Sanctuary.Core/IO/PacketUtils.cs and Cryptography/CipherRC4.cs: the
//   direct-encryption path has no magic/trailer (that wrapper is only used when
//   encryption is disabled). The fixed login key is in ProtocolPrimitives.
// - Sanctuary.UdpLibrary/UdpConnection.cs, Internal/UdpMisc.cs and
//   Internal/UdpReliableChannel.cs: reliable frame = 0x00, packet type,
//   big-endian UInt16 reliable id, application bytes, 2-byte CRC. The CRC is
//   CRC-32 seeded with the little-endian bytes of EncryptCode and is appended
//   big-endian (low 16 bits). An application packet beginning with 0x00 is
//   zero-escaped with one extra leading 0x00.
// - Sanctuary.Packet/ExternalLogin/{LoginRequest,LoginReply,CharacterSelectInfoReply,
//   CharacterSelectInfoRequest,CharacterLoginRequest,CharacterLoginReply,ServerListReply}.cs
//   and Sanctuary.Packet.Common/Login/{EntityDetails,AccountInfo,ClientLoginData,
//   ClientCharacterData,AccountInfoCharacterDetails,AccountInfoCharacterData,
//   CharacterAttachmentData,ClientGameServerData,GameServerData}.cs.
//
// Scope / deliberate ambiguities:
// - Connect/confirm negotiation, EncryptCode assignment, reliable resend and
//   the user-supplied zlib compression pass are transport concerns. This file
//   does not implement them; callers supply EncryptCode and the reliable id.
//   Login's checked-in config does not set UseCompression, so compression is
//   absent here as well. Gateway AES-CCM is a different protocol.
// - Sanctuary calls several fields `Unknown` and never interprets them. They
//   are preserved verbatim as integers/strings; no meaning is invented.
// - The WebAPI login response supplies the session string. Its 32-hex shape is
//   not enforced here because the server may change that contract.
// - `Fingerprint`, `Locale`, `LocaleId`, attachment strings and the three
//   unknown ticket strings are opaque to the server; they are encoded but not
//   validated. No credentials or test accounts are embedded in this file.

// MARK: - Errors

enum LoginProtocolError: Error, LocalizedError, Equatable {
    case unexpectedOpcode(expected: UInt8, actual: UInt8)
    case unsupportedOpcode(UInt8)
    case trailingBytes(Int)
    case wire(ProtocolError)

    case frameTooShort(expected: Int, available: Int)
    case invalidFrameMarker(UInt8)
    case unsupportedFrameType(UInt8)
    case invalidZeroEscape
    case crcMismatch(expected: UInt16, actual: UInt16)

    var errorDescription: String? {
        switch self {
        case .unexpectedOpcode(let expected, let actual):
            return "Expected Login opcode \(expected), found \(actual)."
        case .unsupportedOpcode(let opcode):
            return "Unsupported Login opcode \(opcode)."
        case .trailingBytes(let count):
            return "\(count) trailing byte(s) after Login packet body."
        case .wire(let error):
            return error.errorDescription ?? "Invalid Login wire primitive."
        case .frameTooShort(let expected, let available):
            return "Truncated UDP frame: needed \(expected) byte(s), only \(available) available."
        case .invalidFrameMarker(let value):
            return "Invalid UDP frame marker 0x\(String(value, radix: 16)); expected 0x00."
        case .unsupportedFrameType(let value):
            return "UDP packet type \(value) is not a reliable application frame."
        case .invalidZeroEscape:
            return "Zero-escaped Login frame does not start with two 0x00 bytes."
        case .crcMismatch(let expected, let actual):
            return String(format: "Login frame CRC mismatch: expected 0x%04X, found 0x%04X.", expected, actual)
        }
    }
}

// MARK: - Opcodes and frame types

/// Byte opcodes from `Sanctuary.Packet/ExternalLogin` and
/// `Sanctuary.Packet.Common/Extensions/PacketReaderExtensions.cs`.
enum LoginOpcode: UInt8 {
    case loginRequest = 1
    case loginReply = 2
    case logout = 3
    case forceDisconnect = 4
    case characterCreateRequest = 5
    case characterCreateReply = 6
    case characterLoginRequest = 7
    case characterLoginReply = 8
    case characterDeleteRequest = 9
    case characterDeleteReply = 10
    case characterSelectInfoRequest = 11
    case characterSelectInfoReply = 12
    case serverListRequest = 13
    case serverListReply = 14
    case serverUpdate = 15
    case tunnelClientToServer = 16
    case tunnelServerToClient = 17
}

/// Values from `Sanctuary.UdpLibrary/Internal/UdpPacketType.cs`.
enum UdpFrameType: UInt8 {
    case zeroEscape = 0
    case connect = 1
    case confirm = 2
    case multi = 3
    case big = 4
    case terminate = 5
    case keepAlive = 6
    case clockSync = 7
    case clockReflect = 8
    case reliable1 = 9
    case reliable2 = 10
    case reliable3 = 11
    case reliable4 = 12
    case fragment1 = 13

    var isReliableApplicationFrame: Bool {
        (UInt8(self.rawValue) >= UInt8(UdpFrameType.reliable1.rawValue)) &&
            (UInt8(self.rawValue) <= UInt8(UdpFrameType.reliable4.rawValue))
    }
}

// MARK: - UDP framing and RC4 boundary

/// Four-byte internal header used by `UdpReliableChannel.Send`: 0x00,
/// packet type, big-endian UInt16 reliable id.
struct LoginFrameHeader: Equatable {
    static let marker: UInt8 = 0

    var type: UdpFrameType
    var reliableID: UInt16

    init(type: UdpFrameType = .reliable1, reliableID: UInt16 = 0) {
        precondition(type.isReliableApplicationFrame, "Login frames must use a reliable channel")
        self.type = type
        self.reliableID = reliableID
    }

    init(data: Data) throws {
        guard data.count >= 4 else {
            throw LoginProtocolError.frameTooShort(expected: 4, available: data.count)
        }
        let bytes = Array(data.prefix(4))
        guard bytes[0] == Self.marker else {
            throw LoginProtocolError.invalidFrameMarker(bytes[0])
        }
        guard let type = UdpFrameType(rawValue: bytes[1]), type.isReliableApplicationFrame else {
            throw LoginProtocolError.unsupportedFrameType(bytes[1])
        }
        self.type = type
        self.reliableID = (UInt16(bytes[2]) << 8) | UInt16(bytes[3])
    }

    func encoded() -> Data {
        Data([
            Self.marker,
            type.rawValue,
            UInt8(truncatingIfNeeded: reliableID >> 8),
            UInt8(truncatingIfNeeded: reliableID)
        ])
    }
}

/// A physical Login UDP frame. `ciphertext` is the RC4 output *after* the
/// optional zero escape has been removed; it is what the server decrypts.
struct LoginFrame: Equatable {
    /// LoginUdp_6 registers `CrcBytes = 2` in Sanctuary.Login/Program.cs.
    static let crcByteCount = 2

    var header: LoginFrameHeader
    var encryptCode: UInt32
    var ciphertext: Data

    private var physicalPayload: Data {
        ciphertext.first == 0 ? Data([0]) + ciphertext : ciphertext
    }

    private var crc: UInt16 {
        UInt16(truncatingIfNeeded: CRC32.checksum(signedBytes, encryptCode: encryptCode))
    }

    private var signedBytes: Data {
        var data = header.encoded()
        data.append(physicalPayload)
        return data
    }

    static func encode(header: LoginFrameHeader, encryptCode: UInt32, ciphertext: Data) -> Data {
        var data = header.encoded()
        if ciphertext.first == 0 {
            data.append(0)
        }
        data.append(ciphertext)

        let crc = UInt16(truncatingIfNeeded: CRC32.checksum(data, encryptCode: encryptCode))
        data.append(UInt8(truncatingIfNeeded: crc >> 8))
        data.append(UInt8(truncatingIfNeeded: crc))
        return data
    }

    static func decode(_ data: Data, encryptCode: UInt32) throws -> LoginFrame {
        let minimum = 4 + crcByteCount
        guard data.count >= minimum else {
            throw LoginProtocolError.frameTooShort(expected: minimum, available: data.count)
        }

        let header = try LoginFrameHeader(data: data)
        let signed = data.dropLast(crcByteCount)
        let expected = UInt16(truncatingIfNeeded: CRC32.checksum(Data(signed), encryptCode: encryptCode))
        let actual = (UInt16(data[data.count - 2]) << 8) | UInt16(data[data.count - 1])
        guard expected == actual else {
            throw LoginProtocolError.crcMismatch(expected: expected, actual: actual)
        }

        var payload = Data(signed.dropFirst(4))
        if payload.first == 0 {
            guard payload.count >= 2, payload[1] == 0 else {
                throw LoginProtocolError.invalidZeroEscape
            }
            payload.removeFirst()
        }

        return LoginFrame(header: header, encryptCode: encryptCode, ciphertext: payload)
    }
}

/// Mirrors `CipherRC4`: one keystream for sends and one for receives. Use one
/// instance per connection; reusing it across connections would continue the
/// keystream and break compatibility with Sanctuary.
struct LoginCipher {
    private var outgoing: RC4
    private var incoming: RC4

    init(key: Data = RC4.loginKey) {
        outgoing = RC4(key: key)
        incoming = RC4(key: key)
    }

    mutating func encryptPacket(_ plaintext: Data) -> Data {
        outgoing.process(plaintext)
    }

    mutating func decryptPacket(_ ciphertext: Data) -> Data {
        incoming.process(ciphertext)
    }
}

enum LoginFrameCodec {
    /// RC4 first, then the UDP header/CRC. Sanctuary encrypts the application
    /// packet before the UDP library prepends the reliable header.
    static func encode(
        packet: Data,
        header: LoginFrameHeader = LoginFrameHeader(),
        encryptCode: UInt32,
        cipher: inout LoginCipher
    ) -> Data {
        let ciphertext = cipher.encryptPacket(packet)
        return LoginFrame.encode(header: header, encryptCode: encryptCode, ciphertext: ciphertext)
    }

    static func decode(
        frame: Data,
        encryptCode: UInt32,
        cipher: inout LoginCipher
    ) throws -> Data {
        let parsed = try LoginFrame.decode(frame, encryptCode: encryptCode)
        return cipher.decryptPacket(parsed.ciphertext)
    }
}

// MARK: - Message codec

protocol LoginMessage {
    static var opcode: LoginOpcode { get }
    init(fieldsFrom reader: inout PacketReader) throws
    func appendFields(to writer: inout PacketWriter)
}

enum LoginPacket {
    static func encode<Message: LoginMessage>(_ message: Message) -> Data {
        var writer = PacketWriter()
        writer.writeUInt8(Message.opcode.rawValue)
        message.appendFields(to: &writer)
        return writer.data
    }

    static func decode<Message: LoginMessage>(_ type: Message.Type, from data: Data) throws -> Message {
        var reader = PacketReader(data)
        let raw = try reader.readUInt8()
        guard raw == type.opcode.rawValue else {
            throw LoginProtocolError.unexpectedOpcode(expected: type.opcode.rawValue, actual: raw)
        }
        let message = try Message(fieldsFrom: &reader)
        guard reader.isAtEnd else {
            throw LoginProtocolError.trailingBytes(reader.remaining)
        }
        return message
    }

    static func opcode(from data: Data) throws -> LoginOpcode {
        var reader = PacketReader(data)
        let raw = try reader.readUInt8()
        guard let opcode = LoginOpcode(rawValue: raw) else {
            throw LoginProtocolError.unsupportedOpcode(raw)
        }
        return opcode
    }

    static func decodeAny(from data: Data) throws -> LoginDecodedMessage {
        switch try opcode(from: data) {
        case .loginRequest: return .sessionRequest(try decode(LoginProtocol.SessionRequest.self, from: data))
        case .loginReply: return .sessionReply(try decode(LoginProtocol.SessionReply.self, from: data))
        case .characterSelectInfoRequest: return .characterSelectRequest
        case .characterSelectInfoReply: return .characterSelectReply(try decode(LoginProtocol.CharacterSelectReply.self, from: data))
        case .characterLoginRequest: return .characterLoginRequest(try decode(LoginProtocol.CharacterLoginRequest.self, from: data))
        case .characterLoginReply: return .characterLoginReply(try decode(LoginProtocol.CharacterLoginReply.self, from: data))
        case .serverListRequest: return .serverListRequest
        case .serverListReply: return .serverListReply(try decode(LoginProtocol.ServerListReply.self, from: data))
        default: throw LoginProtocolError.unsupportedOpcode(try opcode(from: data).rawValue)
        }
    }
}

enum LoginDecodedMessage: Equatable {
    case sessionRequest(LoginProtocol.SessionRequest)
    case sessionReply(LoginProtocol.SessionReply)
    case characterSelectRequest
    case characterSelectReply(LoginProtocol.CharacterSelectReply)
    case characterLoginRequest(LoginProtocol.CharacterLoginRequest)
    case characterLoginReply(LoginProtocol.CharacterLoginReply)
    case serverListRequest
    case serverListReply(LoginProtocol.ServerListReply)
}

/// Nested under `LoginProtocol` to avoid colliding with the Codable
/// `LoginRequest`/`LoginResponse` models used by the WebAPI launcher layer.
enum LoginProtocol {
    // MARK: Login request / session ticket

    /// `LoginRequest` opcode 1: `Session` is the WebAPI session id;
    /// `Fingerprint` is an opaque client-supplied string ignored by Sanctuary.
    struct SessionRequest: LoginMessage, Equatable {
        static let opcode: LoginOpcode = .loginRequest

        var sessionID: String
        var fingerprint: String

        init(sessionID: String, fingerprint: String) {
            self.sessionID = sessionID
            self.fingerprint = fingerprint
        }

        init(fieldsFrom reader: inout PacketReader) throws {
            sessionID = try reader.readString()
            fingerprint = try reader.readString()
        }

        func appendFields(to writer: inout PacketWriter) {
            writer.writeString(sessionID)
            writer.writeString(fingerprint)
        }
    }

    /// `AccountInfo` payload written on a successful `LoginReply`.
    struct AccountInfo: Equatable {
        var isMember: Bool
        var maxCharacters: Int32
        var isAdminAccount: Bool

        init(isMember: Bool, maxCharacters: Int32, isAdminAccount: Bool) {
            self.isMember = isMember
            self.maxCharacters = maxCharacters
            self.isAdminAccount = isAdminAccount
        }

        func encoded() -> Data {
            var writer = PacketWriter()
            writer.writeBool(isMember)
            writer.writeInt32(maxCharacters)
            writer.writeBool(isAdminAccount)
            return writer.data
        }

        init(data: Data) throws {
            var reader = PacketReader(data)
            isMember = try reader.readBool()
            maxCharacters = try reader.readInt32()
            isAdminAccount = try reader.readBool()
            guard reader.isAtEnd else { throw LoginProtocolError.trailingBytes(reader.remaining) }
        }
    }

    /// `LoginReply` opcode 2. Failure replies carry an empty payload.
    struct SessionReply: LoginMessage, Equatable {
        static let opcode: LoginOpcode = .loginReply

        var loggedIn: Bool
        var status: Int32
        var isMember: Bool
        var payload: Data

        func accountInfo() throws -> AccountInfo {
            try AccountInfo(data: payload)
        }

        init(loggedIn: Bool, status: Int32, isMember: Bool, payload: Data = Data()) {
            self.loggedIn = loggedIn
            self.status = status
            self.isMember = isMember
            self.payload = payload
        }

        init(fieldsFrom reader: inout PacketReader) throws {
            loggedIn = try reader.readBool()
            status = try reader.readInt32()
            isMember = try reader.readBool()
            payload = try reader.readData()
        }

        func appendFields(to writer: inout PacketWriter) {
            writer.writeBool(loggedIn)
            writer.writeInt32(status)
            writer.writeBool(isMember)
            writer.writeData(payload)
        }
    }

    // MARK: Character select / list

    struct CharacterSelectRequest: LoginMessage, Equatable {
        static let opcode: LoginOpcode = .characterSelectInfoRequest
        init() {}
        init(fieldsFrom reader: inout PacketReader) throws {}
        func appendFields(to writer: inout PacketWriter) {}
    }

    /// `CharacterAttachmentData` as serialized into a character's
    /// `AccountInfoCharacterDetails` application data.
    struct CharacterAttachment: Equatable {
        var modelName: String
        var textureAlias: String
        var tintAlias: String
        var tintID: Int32
        var compositeEffectID: Int32
        var slot: Int32

        func appendFields(to writer: inout PacketWriter) {
            writer.writeString(modelName)
            writer.writeString(textureAlias)
            writer.writeString(tintAlias)
            writer.writeInt32(tintID)
            writer.writeInt32(compositeEffectID)
            writer.writeInt32(slot)
        }

        init(modelName: String, textureAlias: String, tintAlias: String,
             tintID: Int32, compositeEffectID: Int32, slot: Int32) {
            self.modelName = modelName
            self.textureAlias = textureAlias
            self.tintAlias = tintAlias
            self.tintID = tintID
            self.compositeEffectID = compositeEffectID
            self.slot = slot
        }

        init(fieldsFrom reader: inout PacketReader) throws {
            modelName = try reader.readString()
            textureAlias = try reader.readString()
            tintAlias = try reader.readString()
            tintID = try reader.readInt32()
            compositeEffectID = try reader.readInt32()
            slot = try reader.readInt32()
        }
    }

    /// Decoded `AccountInfoCharacterDetails` payload. Sanctuary writes `Head`
    /// and `Hair` as Int32 ids here (unlike some gateway packets that use
    /// strings), and writes every string with an Int32 byte-count prefix.
    struct CharacterSelectDetails: Equatable {
        var headshotURL: String
        var guid: UInt64
        var name: String
        var model: Int32
        var head: Int32
        var hair: Int32
        var modelCustomization: String
        var facePaint: String
        var skinTone: String
        var eyeTint: Int32
        var hairTint: Int32
        var attachments: [CharacterAttachment]

        init(headshotURL: String, guid: UInt64, name: String, model: Int32, head: Int32,
             hair: Int32, modelCustomization: String, facePaint: String, skinTone: String,
             eyeTint: Int32, hairTint: Int32, attachments: [CharacterAttachment]) {
            self.headshotURL = headshotURL
            self.guid = guid
            self.name = name
            self.model = model
            self.head = head
            self.hair = hair
            self.modelCustomization = modelCustomization
            self.facePaint = facePaint
            self.skinTone = skinTone
            self.eyeTint = eyeTint
            self.hairTint = hairTint
            self.attachments = attachments
        }

        func encoded() -> Data {
            var writer = PacketWriter()
            appendFields(to: &writer)
            return writer.data
        }

        func appendFields(to writer: inout PacketWriter) {
            writer.writeString(headshotURL)
            writer.writeUInt64(guid)
            writer.writeString(name)
            writer.writeInt32(model)
            writer.writeInt32(head)
            writer.writeInt32(hair)
            writer.writeString(modelCustomization)
            writer.writeString(facePaint)
            writer.writeString(skinTone)
            writer.writeInt32(eyeTint)
            writer.writeInt32(hairTint)
            writer.writeInt32(Int32(attachments.count))
            for attachment in attachments { attachment.appendFields(to: &writer) }
        }

        init(data: Data) throws {
            var reader = PacketReader(data)
            try self.init(fieldsFrom: &reader)
            guard reader.isAtEnd else { throw LoginProtocolError.trailingBytes(reader.remaining) }
        }

        init(fieldsFrom reader: inout PacketReader) throws {
            headshotURL = try reader.readString()
            guid = try reader.readUInt64()
            name = try reader.readString()
            model = try reader.readInt32()
            head = try reader.readInt32()
            hair = try reader.readInt32()
            modelCustomization = try reader.readString()
            facePaint = try reader.readString()
            skinTone = try reader.readString()
            eyeTint = try reader.readInt32()
            hairTint = try reader.readInt32()
            let count = try LoginPacket.readCount(&reader, "character attachments")
            var attachments: [CharacterAttachment] = []
            attachments.reserveCapacity(count)
            for _ in 0..<count {
                attachments.append(try CharacterAttachment(fieldsFrom: &reader))
            }
            self.attachments = attachments
        }
    }

    /// `EntityDetails`: one entry in `CharacterSelectInfoReply.Entities`.
    struct CharacterSelectEntity: Equatable {
        var entityKey: UInt64
        var lastServerID: Int32
        var status: Int32
        var applicationData: Data

        func details() throws -> CharacterSelectDetails {
            try CharacterSelectDetails(data: applicationData)
        }

        func appendFields(to writer: inout PacketWriter) {
            writer.writeUInt64(entityKey)
            writer.writeInt32(lastServerID)
            writer.writeInt32(status)
            writer.writeData(applicationData)
        }

        init(entityKey: UInt64, lastServerID: Int32, status: Int32, applicationData: Data) {
            self.entityKey = entityKey
            self.lastServerID = lastServerID
            self.status = status
            self.applicationData = applicationData
        }

        init(fieldsFrom reader: inout PacketReader) throws {
            entityKey = try reader.readUInt64()
            lastServerID = try reader.readInt32()
            status = try reader.readInt32()
            applicationData = try reader.readData()
        }
    }

    /// `CharacterSelectInfoReply` opcode 12.
    struct CharacterSelectReply: LoginMessage, Equatable {
        static let opcode: LoginOpcode = .characterSelectInfoReply

        var status: Int32
        var canBypassServerLock: Bool
        var entities: [CharacterSelectEntity]

        init(status: Int32, canBypassServerLock: Bool, entities: [CharacterSelectEntity]) {
            self.status = status
            self.canBypassServerLock = canBypassServerLock
            self.entities = entities
        }

        init(fieldsFrom reader: inout PacketReader) throws {
            status = try reader.readInt32()
            canBypassServerLock = try reader.readBool()
            let count = try LoginPacket.readCount(&reader, "characters")
            var entities: [CharacterSelectEntity] = []
            entities.reserveCapacity(count)
            for _ in 0..<count {
                entities.append(try CharacterSelectEntity(fieldsFrom: &reader))
            }
            self.entities = entities
        }

        func appendFields(to writer: inout PacketWriter) {
            writer.writeInt32(status)
            writer.writeBool(canBypassServerLock)
            writer.writeInt32(Int32(entities.count))
            for entity in entities { entity.appendFields(to: &writer) }
        }
    }

    // MARK: Character login ticket

    /// `ClientLoginData` from Sanctuary.Packet.Common. Every field after
    /// `LocaleId` is named `Unknown*` in Sanctuary; values are kept verbatim.
    struct ClientLoginData: Equatable {
        var locale: String
        var localeID: Int32
        var unknown: Bool
        var unknown2: UInt8
        var unknown3: Int64

        func encoded() -> Data {
            var writer = PacketWriter()
            appendFields(to: &writer)
            return writer.data
        }

        func appendFields(to writer: inout PacketWriter) {
            writer.writeString(locale)
            writer.writeInt32(localeID)
            writer.writeBool(unknown)
            writer.writeUInt8(unknown2)
            writer.writeInt64(unknown3)
        }

        init(locale: String, localeID: Int32, unknown: Bool, unknown2: UInt8, unknown3: Int64) {
            self.locale = locale
            self.localeID = localeID
            self.unknown = unknown
            self.unknown2 = unknown2
            self.unknown3 = unknown3
        }

        init(data: Data) throws {
            var reader = PacketReader(data)
            try self.init(fieldsFrom: &reader)
            guard reader.isAtEnd else { throw LoginProtocolError.trailingBytes(reader.remaining) }
        }

        init(fieldsFrom reader: inout PacketReader) throws {
            locale = try reader.readString()
            localeID = try reader.readInt32()
            unknown = try reader.readBool()
            unknown2 = try reader.readUInt8()
            unknown3 = try reader.readInt64()
        }
    }

    /// `CharacterLoginRequest` opcode 7. `entityKey` is the player GUID
    /// (`(characterId << 4) | 1`); `serverID` is the client-selected server.
    struct CharacterLoginRequest: LoginMessage, Equatable {
        static let opcode: LoginOpcode = .characterLoginRequest

        var entityKey: UInt64
        var serverID: Int32
        var clientLoginData: ClientLoginData

        var characterID: UInt64? { GuidHelper.playerId(entityKey) }

        init(entityKey: UInt64, serverID: Int32, clientLoginData: ClientLoginData) {
            self.entityKey = entityKey
            self.serverID = serverID
            self.clientLoginData = clientLoginData
        }

        init(fieldsFrom reader: inout PacketReader) throws {
            entityKey = try reader.readUInt64()
            serverID = try reader.readInt32()
            let payload = try reader.readData()
            clientLoginData = try ClientLoginData(data: payload)
        }

        func appendFields(to writer: inout PacketWriter) {
            writer.writeUInt64(entityKey)
            writer.writeInt32(serverID)
            writer.writeData(clientLoginData.encoded())
        }
    }

    /// `ClientCharacterData` written into the status-1 `CharacterLoginReply`.
    /// Sanctuary sets `CryptoKey` to `ServerTicket`; this type preserves the
    /// wire values without deriving or inventing either one.
    struct ClientCharacterData: Equatable {
        var serverAddress: String
        var serverTicket: String
        var cryptoKey: String
        var guid: UInt64
        var unknown: Int64
        var unknown2: String
        var unknown3: String
        var unknown4: String

        func encoded() -> Data {
            var writer = PacketWriter()
            appendFields(to: &writer)
            return writer.data
        }

        func appendFields(to writer: inout PacketWriter) {
            writer.writeString(serverAddress)
            writer.writeString(serverTicket)
            writer.writeString(cryptoKey)
            writer.writeUInt64(guid)
            writer.writeInt64(unknown)
            writer.writeString(unknown2)
            writer.writeString(unknown3)
            writer.writeString(unknown4)
        }

        init(serverAddress: String, serverTicket: String, cryptoKey: String,
             guid: UInt64, unknown: Int64, unknown2: String, unknown3: String, unknown4: String) {
            self.serverAddress = serverAddress
            self.serverTicket = serverTicket
            self.cryptoKey = cryptoKey
            self.guid = guid
            self.unknown = unknown
            self.unknown2 = unknown2
            self.unknown3 = unknown3
            self.unknown4 = unknown4
        }

        init(data: Data) throws {
            var reader = PacketReader(data)
            try self.init(fieldsFrom: &reader)
            guard reader.isAtEnd else { throw LoginProtocolError.trailingBytes(reader.remaining) }
        }

        init(fieldsFrom reader: inout PacketReader) throws {
            serverAddress = try reader.readString()
            serverTicket = try reader.readString()
            cryptoKey = try reader.readString()
            guid = try reader.readUInt64()
            unknown = try reader.readInt64()
            unknown2 = try reader.readString()
            unknown3 = try reader.readString()
            unknown4 = try reader.readString()
        }
    }

    /// `CharacterLoginReply` opcode 8. Failure statuses may carry an empty
    /// payload; call `clientData()` only for the status-1 ticket payload.
    struct CharacterLoginReply: LoginMessage, Equatable {
        static let opcode: LoginOpcode = .characterLoginReply

        var entityKey: UInt64
        var serverID: Int32
        var status: Int32
        var payload: Data

        func clientData() throws -> ClientCharacterData {
            try ClientCharacterData(data: payload)
        }

        init(entityKey: UInt64, serverID: Int32, status: Int32, payload: Data = Data()) {
            self.entityKey = entityKey
            self.serverID = serverID
            self.status = status
            self.payload = payload
        }

        init(fieldsFrom reader: inout PacketReader) throws {
            entityKey = try reader.readUInt64()
            serverID = try reader.readInt32()
            status = try reader.readInt32()
            payload = try reader.readData()
        }

        func appendFields(to writer: inout PacketWriter) {
            writer.writeUInt64(entityKey)
            writer.writeInt32(serverID)
            writer.writeInt32(status)
            writer.writeData(payload)
        }
    }

    // MARK: Server list

    /// `GameServerData` plus `ClientGameServerData.AllowedAccess`. Sanctuary
    /// writes fields the original client does not read; they are retained so
    /// the byte layout stays identical. `state` is the raw byte flags value
    /// (Locked=1, Offline=2).
    struct GameServerInfo: Equatable {
        var id: Int32
        var state: UInt8
        var name: String
        var nameID: Int32
        var descriptionText: String
        var descriptionID: Int32
        var requiredFeatureID: Int32
        var applicationData: String
        var populationLevel: Int32
        var populationOOBData: String
        var allowedAccess: Bool

        func appendFields(to writer: inout PacketWriter) {
            writer.writeInt32(id)
            writer.writeUInt8(state)
            writer.writeString(name)
            writer.writeInt32(nameID)
            writer.writeString(descriptionText)
            writer.writeInt32(descriptionID)
            writer.writeInt32(requiredFeatureID)
            writer.writeString(applicationData)
            writer.writeInt32(populationLevel)
            writer.writeString(populationOOBData)
            writer.writeBool(allowedAccess)
        }

        init(id: Int32, state: UInt8, name: String, nameID: Int32,
             descriptionText: String, descriptionID: Int32, requiredFeatureID: Int32,
             applicationData: String, populationLevel: Int32,
             populationOOBData: String, allowedAccess: Bool) {
            self.id = id
            self.state = state
            self.name = name
            self.nameID = nameID
            self.descriptionText = descriptionText
            self.descriptionID = descriptionID
            self.requiredFeatureID = requiredFeatureID
            self.applicationData = applicationData
            self.populationLevel = populationLevel
            self.populationOOBData = populationOOBData
            self.allowedAccess = allowedAccess
        }

        init(fieldsFrom reader: inout PacketReader) throws {
            id = try reader.readInt32()
            state = try reader.readUInt8()
            name = try reader.readString()
            nameID = try reader.readInt32()
            descriptionText = try reader.readString()
            descriptionID = try reader.readInt32()
            requiredFeatureID = try reader.readInt32()
            applicationData = try reader.readString()
            populationLevel = try reader.readInt32()
            populationOOBData = try reader.readString()
            allowedAccess = try reader.readBool()
        }
    }

    struct ServerListRequest: LoginMessage, Equatable {
        static let opcode: LoginOpcode = .serverListRequest
        init() {}
        init(fieldsFrom reader: inout PacketReader) throws {}
        func appendFields(to writer: inout PacketWriter) {}
    }

    struct ServerListReply: LoginMessage, Equatable {
        static let opcode: LoginOpcode = .serverListReply

        var servers: [GameServerInfo]

        init(servers: [GameServerInfo]) { self.servers = servers }

        init(fieldsFrom reader: inout PacketReader) throws {
            let count = try LoginPacket.readCount(&reader, "servers")
            var servers: [GameServerInfo] = []
            servers.reserveCapacity(count)
            for _ in 0..<count {
                servers.append(try GameServerInfo(fieldsFrom: &reader))
            }
            self.servers = servers
        }

        func appendFields(to writer: inout PacketWriter) {
            writer.writeInt32(Int32(servers.count))
            for server in servers { server.appendFields(to: &writer) }
        }
    }
}

extension LoginPacket {
    /// Sanctuary writes list counts as Int32. Reject negative values and
    /// counts that cannot fit in the remaining bytes (each element here is at
    /// least one byte) before reserving capacity.
    static func readCount(_ reader: inout PacketReader, _ field: String) throws -> Int {
        let raw = try reader.readInt32()
        guard raw >= 0 else {
            throw LoginProtocolError.wire(.negativeLength(field))
        }
        let count = Int(raw)
        guard count <= reader.remaining else {
            throw LoginProtocolError.wire(.truncated(expected: count, available: reader.remaining))
        }
        return count
    }
}
