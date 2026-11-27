import Foundation
import Network

// Client-side Sanctuary LoginUdp_6 transport.
//
// Source-backed behavior (Sanctuary fork at /tmp/opencode/sanctuary/src):
// - Sanctuary.UdpLibrary/Internal/UdpConnection.cs: client negotiation sends a
//   raw Connect packet every ConnectAttemptDelay (default 1000 ms) until a
//   matching Confirm arrives. Connect version is Constants.ProtocolVersion (3),
//   ConnectCode is a random Int32, and MaxRawPacketSize comes from the default
//   UdpParams (512). The Confirm supplies EncryptCode, CrcBytes, encrypt
//   methods and MaxRawPacketSize.
// - Sanctuary.UdpLibrary/Internal/UdpPacketType.cs: Connect=1, Confirm=2,
//   Reliable1=9..Reliable4=12, Ack1=17..Ack4=20.
// - Sanctuary.UdpLibrary/Internal/UdpReliableChannel.cs: reliable packets carry
//   a 4-byte header (0x00, channel type, big-endian UInt16 id); acks carry
//   0x00, AckN, big-endian UInt16 id. Both are CRC-protected using the
//   connection EncryptCode.
// - Sanctuary.Login/Program.cs: the login listener uses ProtocolName
//   "LoginUdp_6", CrcBytes=2 and UserSupplied compression with one expansion
//   byte. LoginConnection.cs RC4-encrypts application packets with the fixed
//   base64 key F70IaxuU8C/w7FPXY1ibXw== before framing.
// - Sanctuary.Login/Handlers/{LoginRequestHandler,CharacterSelectInfoRequestHandler,
//   CharacterLoginRequestHandler}.cs: SessionId -> account -> character list ->
//   gateway ticket. CharacterLoginRequest.ServerId and ClientLoginData are
//   parsed but ignored by Sanctuary, so the values used here are documented
//   client choices rather than recovered stock-client constants.

enum LoginUDPError: LocalizedError {
    case invalidAddress(String)
    case timeout(String)
    case transport(String)
    case protocolError(String)
    case loginRejected(Int32)
    case noCharacters
    case invalidCharacterReply(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidAddress(let value): return "Invalid login server address: \(value)"
        case .timeout(let stage): return "Timed out waiting for \(stage)."
        case .transport(let detail): return "Login connection failed: \(detail)"
        case .protocolError(let detail): return "Invalid Login UDP packet: \(detail)"
        case .loginRejected(let status): return "The login server rejected the session (status \(status))."
        case .noCharacters: return "This account has no character available to enter the world."
        case .invalidCharacterReply(let status): return "Character login failed (status \(status))."
        }
    }
}

/// Result of the WebAPI-session-to-account exchange only.
struct LoginUDPSessionResult: Equatable {
    var reply: LoginProtocol.SessionReply
    var accountInfo: LoginProtocol.AccountInfo?

    init(reply: LoginProtocol.SessionReply) {
        self.reply = reply
        self.accountInfo = try? reply.accountInfo()
    }
}

/// Complete server-backed result needed to open a gateway connection.
struct LoginGameSessionResult: Equatable {
    var sessionReply: LoginProtocol.SessionReply
    var accountInfo: LoginProtocol.AccountInfo?
    var characterEntities: [LoginProtocol.CharacterSelectEntity]
    var character: LoginProtocol.CharacterSelectEntity
    var characterReply: LoginProtocol.CharacterLoginReply
    var clientData: LoginProtocol.ClientCharacterData

    /// Server-derived player GUID from `ClientCharacterData`, not a client guess.
    var playerGUID: UInt64 { clientData.guid }

    /// Server-derived entity key from the character list.
    var entityKey: UInt64 { character.entityKey }
}

/// Private accumulated result for one connection. All fields are captured on
/// the serial queue before the continuation resumes.
private struct LoginFlowResult {
    var sessionReply: LoginProtocol.SessionReply?
    var characterEntities: [LoginProtocol.CharacterSelectEntity] = []
    var character: LoginProtocol.CharacterSelectEntity?
    var characterReply: LoginProtocol.CharacterLoginReply?
    var clientData: LoginProtocol.ClientCharacterData?
}

// Big-endian helpers for the UdpLibrary handshake. Application packets use
// PacketWriter/PacketReader instead (little-endian .NET BinaryWriter layout).
private func readBE16(_ data: Data, offset: Int) -> UInt16 {
    (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
}

private func readBE32(_ data: Data, offset: Int) -> UInt32 {
    (UInt32(data[offset]) << 24) |
        (UInt32(data[offset + 1]) << 16) |
        (UInt32(data[offset + 2]) << 8) |
        UInt32(data[offset + 3])
}

private func appendBE16(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(truncatingIfNeeded: value >> 8))
    data.append(UInt8(truncatingIfNeeded: value))
}

private func appendBE32(_ value: Int32, to data: inout Data) {
    let bits = UInt32(bitPattern: value)
    data.append(UInt8(truncatingIfNeeded: bits >> 24))
    data.append(UInt8(truncatingIfNeeded: bits >> 16))
    data.append(UInt8(truncatingIfNeeded: bits >> 8))
    data.append(UInt8(truncatingIfNeeded: bits))
}

/// One client-side Login UDP connection. Create a fresh instance per login;
/// RC4 state and the EncryptCode are connection-scoped in Sanctuary.
final class LoginUDPSession: @unchecked Sendable {
    private static let protocolVersion: Int32 = 3
    private static let protocolName = "LoginUdp_6"
    private static let maxRawPacketSize: Int32 = 512
    private static let crcBytes: UInt8 = 2
    private static let connectAttemptDelay: TimeInterval = 1
    private static let maximumDatagramSize: Int = 2048

    private enum Stage: String {
        case negotiating
        case session
        case characters
        case characterLogin
    }

    private let endpoint: NWEndpoint
    private let queue = DispatchQueue(label: "dev.opensourcefreerealms.login-udp")
    private let connection: NWConnection
    private let connectCode: UInt32
    private let generation: UInt64

    private var stage: Stage = .negotiating
    private var fullFlow = false
    private var encryptCode: UInt32 = 0
    private var cipher = LoginCipher()
    private var udpState = UdpLibraryReassemblyState()
    private var incomingReliable = UdpLibraryIncomingReliableState()
    private var outgoingReliableID: UInt16 = 0
    private var pendingReliableFrame: Data?
    private var flowResult = LoginFlowResult()
    private var continuation: CheckedContinuation<LoginFlowResult, Error>?
    private var connectRetry: DispatchWorkItem?
    private var reliableRetry: DispatchWorkItem?
    private var timeoutWork: DispatchWorkItem?

    // Set immediately before the first send; stored on the serial queue.
    private var currentSessionID = ""
    private var currentFingerprint = ""
    private var currentLocale: GameLocale = .en_US
    private var currentServerID: Int32 = 1

    private init(endpoint: NWEndpoint, generation: UInt64) {
        self.endpoint = endpoint
        self.generation = generation
        connectCode = UInt32(truncatingIfNeeded: Int.random(in: Int.min...Int.max))
        connection = NWConnection(to: endpoint, using: .udp)
    }

    /// Authenticates a WebAPI session and returns the account reply only.
    /// `address` accepts `host`, `host:port`, and bracketed IPv6 forms.
    static func authenticate(
        address: String,
        sessionID: String,
        fingerprint: String,
        timeout: TimeInterval = 12
    ) async throws -> LoginUDPSessionResult {
        let result = try await authenticateFlow(
            address: address,
            sessionID: sessionID,
            fingerprint: fingerprint,
            locale: .en_US,
            serverID: 1,
            fullFlow: false,
            timeout: timeout
        )
        guard let reply = result.sessionReply else {
            throw LoginUDPError.protocolError("missing login reply")
        }
        return LoginUDPSessionResult(reply: reply)
    }

    /// Authenticates using an already-parsed host/port pair.
    static func authenticate(
        host: String,
        port: UInt16,
        sessionID: String,
        fingerprint: String,
        timeout: TimeInterval = 12
    ) async throws -> LoginUDPSessionResult {
        let result = try await authenticateFlow(
            host: host,
            port: port,
            sessionID: sessionID,
            fingerprint: fingerprint,
            locale: .en_US,
            serverID: 1,
            fullFlow: false,
            timeout: timeout
        )
        guard let reply = result.sessionReply else {
            throw LoginUDPError.protocolError("missing login reply")
        }
        return LoginUDPSessionResult(reply: reply)
    }

    /// Performs the complete Sanctuary flow: session request, character select,
    /// character login and gateway ticket extraction.
    static func authenticateCharacter(
        address: String,
        sessionID: String,
        fingerprint: String,
        locale: GameLocale,
        serverID: Int32 = 1,
        timeout: TimeInterval = 30
    ) async throws -> LoginGameSessionResult {
        let result = try await authenticateFlow(
            address: address,
            sessionID: sessionID,
            fingerprint: fingerprint,
            locale: locale,
            serverID: serverID,
            fullFlow: true,
            timeout: timeout
        )
        return try makeGameSessionResult(result)
    }

    /// Completes the full flow using an already-parsed host/port pair.
    static func authenticateCharacter(
        host: String,
        port: UInt16,
        sessionID: String,
        fingerprint: String,
        locale: GameLocale,
        serverID: Int32 = 1,
        timeout: TimeInterval = 30
    ) async throws -> LoginGameSessionResult {
        let result = try await authenticateFlow(
            host: host,
            port: port,
            sessionID: sessionID,
            fingerprint: fingerprint,
            locale: locale,
            serverID: serverID,
            fullFlow: true,
            timeout: timeout
        )
        return try makeGameSessionResult(result)
    }

    private static func makeGameSessionResult(_ flow: LoginFlowResult) throws -> LoginGameSessionResult {
        guard let session = flow.sessionReply else {
            throw LoginUDPError.protocolError("missing login reply")
        }
        guard let character = flow.character else {
            throw LoginUDPError.noCharacters
        }
        guard let reply = flow.characterReply, let data = flow.clientData else {
            throw LoginUDPError.protocolError("missing character login reply")
        }
        return LoginGameSessionResult(
            sessionReply: session,
            accountInfo: try? session.accountInfo(),
            characterEntities: flow.characterEntities,
            character: character,
            characterReply: reply,
            clientData: data
        )
    }

    private static func authenticateFlow(
        address: String,
        sessionID: String,
        fingerprint: String,
        locale: GameLocale,
        serverID: Int32,
        fullFlow: Bool,
        timeout: TimeInterval
    ) async throws -> LoginFlowResult {
        guard let (host, port) = ServerStatusClient.parse(address) else {
            throw LoginUDPError.invalidAddress(address)
        }
        return try await authenticateFlow(
            host: host,
            port: port,
            sessionID: sessionID,
            fingerprint: fingerprint,
            locale: locale,
            serverID: serverID,
            fullFlow: fullFlow,
            timeout: timeout
        )
    }

    private static func authenticateFlow(
        host: String,
        port: UInt16,
        sessionID: String,
        fingerprint: String,
        locale: GameLocale,
        serverID: Int32,
        fullFlow: Bool,
        timeout: TimeInterval
    ) async throws -> LoginFlowResult {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw LoginUDPError.invalidAddress("\(host):\(port)")
        }
        let session = LoginUDPSession(
            endpoint: NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort),
            generation: 1
        )
        return try await session.run(
            sessionID: sessionID,
            fingerprint: fingerprint,
            locale: locale,
            serverID: serverID,
            fullFlow: fullFlow,
            timeout: timeout
        )
    }

    /// Locale IDs mirror the Windows LCIDs used by the original client. Sanctuary
    /// ignores these fields, so unlisted locales intentionally use 0.
    static func localeID(for locale: GameLocale) -> Int32 {
        switch locale {
        case .none: return 0
        case .en_US: return 1033
        case .en_GB: return 2057
        case .de_DE: return 1031
        case .fr_FR: return 1036
        case .ja_JP: return 1041
        case .ko_KR: return 1042
        case .zh_CN: return 2052
        case .zh_TW: return 1028
        case .es_ES: return 1034
        case .it_IT: return 1040
        case .pt_PT: return 2070
        case .ru_RU: return 1049
        case .sv_SE: return 1053
        case .pt_BR: return 1046
        case .es_MX: return 3082
        case .nl_NL: return 1043
        case .pl_PL: return 1045
        case .fi_FL: return 1035
        case .da_DK: return 1030
        case .nn_NO: return 2068
        }
    }

    private func run(
        sessionID: String,
        fingerprint: String,
        locale: GameLocale,
        serverID: Int32,
        fullFlow: Bool,
        timeout: TimeInterval
    ) async throws -> LoginFlowResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.continuation = continuation
                self.fullFlow = fullFlow
                self.currentSessionID = sessionID
                self.currentFingerprint = fingerprint
                self.currentLocale = locale
                self.currentServerID = serverID
                self.installTimeout(timeout)
                self.connection.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    self.queue.async { self.handle(connectionState: state) }
                }
                self.connection.start(queue: self.queue)
            }
        }
    }

    // MARK: - Connection state

    private func handle(connectionState state: NWConnection.State) {
        guard continuation != nil else { return }
        switch state {
        case .ready:
            sendConnectPacket()
            receiveLoop()
        case .failed(let error):
            finish(.failure(LoginUDPError.transport(error.localizedDescription)))
        case .cancelled:
            break
        default:
            break
        }
    }

    private func receiveLoop() {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: Self.maximumDatagramSize
        ) { [weak self] data, _, _, error in
            guard let self else { return }
            self.queue.async {
                guard self.continuation != nil else { return }
                if let error {
                    self.finish(.failure(LoginUDPError.transport(error.localizedDescription)))
                    return
                }
                guard let data, !data.isEmpty else {
                    self.finish(.failure(LoginUDPError.transport("Connection closed")))
                    return
                }
                self.handle(datagram: data)
                guard self.continuation != nil else { return }
                self.receiveLoop()
            }
        }
    }

    // MARK: - Packet handling

    private func handle(datagram data: Data) {
        guard data.count >= 2, data[0] == 0 else { return }
        if data[1] == UdpFrameType.confirm.rawValue, stage == .negotiating {
            handleConfirm(data)
            return
        }

        // LoginUdp_6 negotiated methods [0,0], so there is no user-supplied
        // pass. The shared decoder still validates the CRC, expands Multi and
        // Group containers, and reassembles reliable fragments.
        do {
            let cooked = try UdpLibrary.cook(
                data,
                encryptCode: encryptCode,
                userSuppliedCompression: false
            )
            for packet in UdpLibrary.parse(cooked, state: &udpState) {
                handleUdpPacket(packet)
            }
        } catch {
            // A malformed datagram is ignored; the overall timeout keeps the
            // caller from hanging if every packet is corrupt.
            _ = error
        }
    }

    private func handleUdpPacket(_ packet: UdpLibraryPacket) {
        switch packet {
        case .reliable(let type, let reliableID, _, let applications):
            guard let ack = incomingReliable.receive(
                type: type,
                reliableID: reliableID,
                applications: applications
            ) else { return }
            let packet = UdpLibrary.encodeAck(
                type: ack.type,
                reliableID: ack.reliableID,
                encryptCode: encryptCode,
                userSuppliedCompression: false
            )
            rawSend(packet)
            for application in ack.applications {
                handleApplication(application)
            }
        case .ack(_, let reliableID):
            acknowledgeOutgoing(reliableID)
        case .ackAll(_, let reliableID):
            acknowledgeOutgoingThrough(reliableID)
        case .application, .internalPacket:
            break
        }
    }

    private func handleApplication(_ application: Data) {
        let plaintext = cipher.decryptPacket(application)
        guard let message = try? LoginPacket.decodeAny(from: plaintext) else { return }
        switch message {
        case .sessionReply(let reply):
            handleSessionReply(reply)
        case .characterSelectReply(let reply):
            handleCharacterSelectReply(reply)
        case .characterLoginReply(let reply):
            handleCharacterLoginReply(reply)
        default:
            break
        }
    }

    /// Stops resending the one outstanding request once the peer ACKs it.
    private func acknowledgeOutgoing(_ reliableID: UInt16) {
        guard reliableID == (outgoingReliableID &- 1) else { return }
        loginRetryStop()
    }

    private func acknowledgeOutgoingThrough(_ reliableID: UInt16) {
        let distance = Int(UInt16(truncatingIfNeeded: reliableID &- (outgoingReliableID &- 1)))
        if distance < 0x8000 {
            loginRetryStop()
        }
    }

    private func handleConfirm(_ data: Data) {
        // 0, Confirm, ConnectCode, EncryptCode, CrcBytes, EncryptMethod[2],
        // MaxRawPacketSize, optional ProtocolVersion. UdpConnection.cs accepts
        // the shorter 17-byte form from older peers.
        guard data.count >= 17 else {
            finish(.failure(LoginUDPError.protocolError("Truncated Confirm packet")))
            return
        }
        guard readBE32(data, offset: 2) == connectCode else { return }
        guard data[10] == Self.crcBytes else {
            finish(.failure(LoginUDPError.protocolError("Unsupported CRC byte count \(data[10])")))
            return
        }
        encryptCode = readBE32(data, offset: 6)
        stage = .session
        connectRetry?.cancel()
        connectRetry = nil
        // The remote EncryptCode seeds the UDP CRC. Application RC4 state is
        // independent and was initialized with the fixed login key.
        sendSessionRequest()
    }

    private func handleSessionReply(_ reply: LoginProtocol.SessionReply) {
        guard stage == .session else { return }
        loginRetryStop()
        guard reply.loggedIn else {
            finish(.failure(LoginUDPError.loginRejected(reply.status)))
            return
        }
        flowResult.sessionReply = reply
        if fullFlow {
            stage = .characters
            sendReliable(LoginProtocol.CharacterSelectRequest())
            installTimeout(20)
        } else {
            finish(.success(flowResult))
        }
    }

    private func handleCharacterSelectReply(_ reply: LoginProtocol.CharacterSelectReply) {
        guard stage == .characters else { return }
        loginRetryStop()
        guard reply.status == 1 else {
            finish(.failure(LoginUDPError.protocolError("Character list unavailable (status \(reply.status))")))
            return
        }
        guard let entity = reply.entities.first(where: { $0.status == 1 }) ?? reply.entities.first else {
            finish(.failure(LoginUDPError.noCharacters))
            return
        }
        flowResult.characterEntities = reply.entities
        flowResult.character = entity
        stage = .characterLogin
        let clientData = LoginProtocol.ClientLoginData(
            locale: currentLocale.rawValue,
            localeID: Self.localeID(for: currentLocale),
            unknown: false,
            unknown2: 0,
            unknown3: 0
        )
        let request = LoginProtocol.CharacterLoginRequest(
            entityKey: entity.entityKey,
            serverID: currentServerID,
            clientLoginData: clientData
        )
        sendReliable(request)
        installTimeout(20)
    }

    private func handleCharacterLoginReply(_ reply: LoginProtocol.CharacterLoginReply) {
        guard stage == .characterLogin else { return }
        loginRetryStop()
        guard reply.status == 1 else {
            finish(.failure(LoginUDPError.invalidCharacterReply(reply.status)))
            return
        }
        do {
            let data = try reply.clientData()
            flowResult.characterReply = reply
            flowResult.clientData = data
            finish(.success(flowResult))
        } catch {
            finish(.failure(LoginUDPError.protocolError("Invalid ClientCharacterData: \(error.localizedDescription)")))
        }
    }

    // MARK: - Sending

    private func sendConnectPacket() {
        guard stage == .negotiating else { return }
        var packet = Data([0, 1])
        appendBE32(Self.protocolVersion, to: &packet)
        appendBE32(Int32(bitPattern: connectCode), to: &packet)
        appendBE32(Self.maxRawPacketSize, to: &packet)
        packet.append(Data(Self.protocolName.utf8))
        packet.append(0)
        rawSend(packet)
        scheduleConnectRetry()
    }

    private func scheduleConnectRetry() {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.queue.async {
                guard self.continuation != nil, self.stage == .negotiating else { return }
                self.sendConnectPacket()
            }
        }
        connectRetry?.cancel()
        connectRetry = item
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + Self.connectAttemptDelay,
            execute: item
        )
    }

    private func sendSessionRequest() {
        let request = LoginProtocol.SessionRequest(
            sessionID: currentSessionID,
            fingerprint: currentFingerprint
        )
        sendReliable(request)
    }

    private func sendReliable<Message: LoginMessage>(_ message: Message) {
        guard continuation != nil else { return }
        loginRetryStop()
        let packet = LoginPacket.encode(message)
        let header = LoginFrameHeader(type: .reliable1, reliableID: outgoingReliableID)
        outgoingReliableID = outgoingReliableID &+ 1
        let frame = LoginFrame.encode(
            header: header,
            encryptCode: encryptCode,
            ciphertext: cipher.encryptPacket(packet)
        )
        pendingReliableFrame = frame
        rawSend(frame)
        scheduleReliableRetry()
    }

    private func loginRetryStop() {
        reliableRetry?.cancel()
        reliableRetry = nil
        pendingReliableFrame = nil
    }

    private func scheduleReliableRetry() {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.queue.async {
                guard self.continuation != nil, let frame = self.pendingReliableFrame else { return }
                self.rawSend(frame)
                self.scheduleReliableRetry()
            }
        }
        reliableRetry?.cancel()
        reliableRetry = item
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + Self.connectAttemptDelay,
            execute: item
        )
    }

    private func rawSend(_ packet: Data) {
        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            guard let self, let error else { return }
            self.queue.async {
                self.finish(.failure(LoginUDPError.transport(error.localizedDescription)))
            }
        })
    }

    // MARK: - Lifecycle

    private func installTimeout(_ timeout: TimeInterval) {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.queue.async {
                guard self.continuation != nil else { return }
                self.finish(.failure(LoginUDPError.timeout(self.stage == .negotiating ? "Login UDP confirm" : "\(self.stage) reply")))
            }
        }
        timeoutWork?.cancel()
        timeoutWork = item
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + max(1, timeout),
            execute: item
        )
    }

    private func finish(_ result: Result<LoginFlowResult, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        connectRetry?.cancel()
        reliableRetry?.cancel()
        timeoutWork?.cancel()
        connectRetry = nil
        reliableRetry = nil
        timeoutWork = nil
        pendingReliableFrame = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        switch result {
        case .success(let value): continuation.resume(returning: value)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    deinit {
        connectRetry?.cancel()
        reliableRetry?.cancel()
        timeoutWork?.cancel()
        connection.cancel()
    }
}

// MARK: - Gateway UDP transport

enum GatewayUDPError: LocalizedError {
    case invalidAddress(String)
    case timeout(String)
    case transport(String)
    case protocolError(String)
    case rejected

    var errorDescription: String? {
        switch self {
        case .invalidAddress(let value): return "Invalid gateway address: \(value)"
        case .timeout(let stage): return "Timed out waiting for \(stage)."
        case .transport(let detail): return "Gateway connection failed: \(detail)"
        case .protocolError(let detail): return "Invalid gateway packet: \(detail)"
        case .rejected: return "The gateway rejected the character login ticket."
        }
    }
}

/// Sanctuary's gateway uses the same UdpLibrary handshake as login, then a
/// plaintext `PacketLogin` followed by AES-CCM-protected gameplay traffic.
/// `GatewaySession` owns the codec state; this class owns the NWConnection,
/// reliable retransmission and acknowledgement loop.
final class GatewayUDPSession: @unchecked Sendable {
    /// Sanctuary's bundled `gateway.json` default. Servers may override this,
    /// so the value is carried in `WorldSessionConfiguration` by the caller.
    static let defaultClientVersion = "1.910.1.530630"

    private static let retryDelay: TimeInterval = 1
    /// Sanctuary's external-client `UdpParams` default. The public gateway's
    /// own server side uses 29 s, which is close to its 30 s no-data timeout.
    private static let keepAliveDelay: TimeInterval = 10
    private static let maximumDatagramSize = 8192

    private enum Stage: String {
        case negotiating
        case login
    }

    private let queue = DispatchQueue(label: "dev.opensourcefreerealms.gateway-udp")
    private let connection: NWConnection
    private let connectCode: Int32
    private let ticket: String
    private let hello: GatewaySessionHello

    private var stage: Stage = .negotiating
    private var encryptCode: UInt32 = 0
    private var gateway: GatewaySession
    private var udpState = UdpLibraryReassemblyState()
    /// Ordered inbound reliable channels. Matches Sanctuary's buffering and
    /// duplicate suppression; only packet-backed applications are delivered.
    private var incomingReliable = UdpLibraryIncomingReliableState()
    private var userSuppliedCompression = true
    private var isActive = false
    private var continuation: CheckedContinuation<Void, Error>?
    private var pendingFrames: [UInt16: Data] = [:]
    private var connectRetry: DispatchWorkItem?
    private var retryTimer: DispatchWorkItem?
    private var keepAliveTimer: DispatchWorkItem?
    private var timeoutWork: DispatchWorkItem?
    private var trace: [String] = []
    private var worldEventHandler: ((GatewayWorldPacket) -> Void)?

    private init(endpoint: NWEndpoint, ticket: String, hello: GatewaySessionHello) {
        self.connection = NWConnection(to: endpoint, using: .udp)
        self.connectCode = Int32(truncatingIfNeeded: Int.random(in: Int.min...Int.max))
        self.ticket = ticket
        self.hello = hello
        self.gateway = GatewaySession(
            connectCode: connectCode,
            encryptCode: 0,
            compressionEnabled: true
        )
    }

    static func connect(
        address: String,
        ticket: String,
        guid: UInt64,
        version: String = GatewayUDPSession.defaultClientVersion,
        timeout: TimeInterval = 20
    ) async throws -> GatewayUDPSession {
        guard let (host, port) = ServerStatusClient.parse(address) else {
            throw GatewayUDPError.invalidAddress(address)
        }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw GatewayUDPError.invalidAddress("\(host):\(port)")
        }
        let hello = GatewaySessionHello(ticket: ticket, guid: guid, version: version)
        let session = GatewayUDPSession(
            endpoint: NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort),
            ticket: ticket,
            hello: hello
        )
        try await session.run(timeout: timeout)
        return session
    }

    private func run(timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.continuation = continuation
                self.installTimeout(timeout)
                self.connection.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    self.queue.async { self.handle(connectionState: state) }
                }
                self.connection.start(queue: self.queue)
            }
        }
    }

    // MARK: - Connection state

    private func handle(connectionState state: NWConnection.State) {
        switch state {
        case .ready:
            sendConnectPacket()
            receiveLoop()
        case .failed(let error):
            if continuation != nil || isActive {
                fail(GatewayUDPError.transport(error.localizedDescription))
            } else {
                queue.async { self.connection.cancel() }
            }
        case .cancelled:
            break
        default:
            break
        }
    }

    private func receiveLoop() {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: Self.maximumDatagramSize
        ) { [weak self] data, _, _, error in
            guard let self else { return }
            self.queue.async {
                if let error {
                    if self.continuation != nil || self.isActive {
                        self.fail(GatewayUDPError.transport(error.localizedDescription))
                    }
                    return
                }
                guard let data, !data.isEmpty else { return }
                self.handle(datagram: data)
                self.receiveLoop()
            }
        }
    }

    // MARK: - Diagnostics

    /// Keep a small, non-secret trace so a timeout names the exact stage that
    /// failed instead of collapsing every receive/parse/decode error into one
    /// generic 20-second wait.
    private func record(_ event: String) {
        trace.append(event)
        if trace.count > 12 { trace.removeFirst(trace.count - 12) }
    }

    private var diagnosticSuffix: String {
        trace.isEmpty ? "" : " trace=\(trace.joined(separator: " | "))"
    }

    // MARK: - Inbound frames

    private func handle(datagram data: Data) {
        guard data.count >= 2, data[0] == 0 else { return }
        if data[1] == UdpFrameType.confirm.rawValue, stage == .negotiating {
            handleConfirm(data)
            return
        }

        do {
            let cooked = try UdpLibrary.cook(
                data,
                encryptCode: encryptCode,
                userSuppliedCompression: userSuppliedCompression
            )
            record("datagram type=\(data[1]) cooked=\(cooked.count)")
            for packet in UdpLibrary.parse(cooked, state: &udpState) {
                handleUdpPacket(packet)
            }
        } catch {
            // Keep the session alive for later packets, but remember why this
            // one was dropped so the timeout can report the real failure.
            record("cook-error=\(String(describing: error))")
        }
    }

    private func handleUdpPacket(_ packet: UdpLibraryPacket) {
        switch packet {
        case .reliable(let type, let reliableID, let body, let applications):
            record("reliable type=\(type) id=\(reliableID) body=\(body.count) apps=\(applications.count)")
            guard let ack = incomingReliable.receive(
                type: type,
                reliableID: reliableID,
                applications: applications
            ) else { return }
            let packet = UdpLibrary.encodeAck(
                type: ack.type,
                reliableID: ack.reliableID,
                encryptCode: encryptCode,
                userSuppliedCompression: userSuppliedCompression
            )
            rawSend(packet)
            record(
                "ack type=\(ack.type) id=\(ack.reliableID) " +
                "delivered=\(ack.applications.count) duplicate=\(ack.wasDuplicate)"
            )
            for application in ack.applications {
                handleApplication(application)
            }
        case .ack(let type, let reliableID):
            record("ack type=\(type) id=\(reliableID)")
            pendingFrames.removeValue(forKey: reliableID)
        case .ackAll(let type, let reliableID):
            record("ack-all type=\(type) id=\(reliableID)")
            acknowledgeAll(through: reliableID)
        case .application(let data):
            record("direct-app len=\(data.count)")
        case .internalPacket(let type):
            record("internal type=\(type)")
        }
    }

    private func handleApplication(_ application: Data) {
        do {
            let opcode = application.count >= 2
                ? Int16(bitPattern: UInt16(application[0]) | (UInt16(application[1]) << 8))
                : -1
            record("app opcode=\(opcode) len=\(application.count)")
            for event in try gateway.receiveApplicationData(application) {
                switch event {
                case .packet(.loginReply(let reply)) where reply.success:
                    record("login-reply=success")
                    completeLogin()
                case .packet(.loginReply(_)):
                    record("login-reply=rejected")
                    fail(GatewayUDPError.rejected)
                case .rejected(let error):
                    record("decode-error=\(error.localizedDescription)")
                    fail(GatewayUDPError.protocolError(error.localizedDescription + diagnosticSuffix))
                case .world(let packet):
                    record("world-event=\(packet)")
                    worldEventHandler?(packet)
                default:
                    break
                }
            }
        } catch {
            record("decode-error=\(error.localizedDescription)")
            fail(GatewayUDPError.protocolError(error.localizedDescription + diagnosticSuffix))
        }
    }

    /// `AckAll` acknowledges every reliable id up to and including its stamp.
    private func acknowledgeAll(through reliableID: UInt16) {
        for pendingID in Array(pendingFrames.keys) {
            let distance = Int(UInt16(truncatingIfNeeded: reliableID &- pendingID))
            if distance < 0x8000 {
                pendingFrames.removeValue(forKey: pendingID)
            }
        }
    }

    private func handleConfirm(_ data: Data) {
        guard stage == .negotiating else { return }
        let confirm: GatewayConfirmPacket
        do {
            confirm = try GatewayConfirmPacket(data: data)
        } catch {
            fail(GatewayUDPError.protocolError("Invalid Confirm: \(error.localizedDescription)"))
            return
        }
        guard confirm.connectCode == connectCode else { return }
        guard confirm.crcBytes == LoginFrame.crcByteCount else {
            fail(GatewayUDPError.protocolError("Unsupported CRC byte count \(confirm.crcBytes)"))
            return
        }
        stage = .login
        encryptCode = UInt32(bitPattern: confirm.encryptCode)
        userSuppliedCompression = confirm.encryptMethod1 == 1
        record(
            "confirm methods=[\(confirm.encryptMethod1),\(confirm.encryptMethod2)] " +
            "crc=\(confirm.crcBytes) max=\(confirm.maxRawPacketSize) compress=\(userSuppliedCompression)"
        )
        guard confirm.encryptMethod2 == 0 else {
            fail(GatewayUDPError.protocolError("Unsupported second encrypt method \(confirm.encryptMethod2)"))
            return
        }
        udpState.reset()
        incomingReliable.reset()
        gateway = GatewaySession(
            connectCode: connectCode,
            encryptCode: encryptCode,
            compressionEnabled: userSuppliedCompression
        )
        connectRetry?.cancel()
        connectRetry = nil

        do {
            try gateway.setCipher(ticket: ticket)
            let frame = try gateway.beginLogin(hello)
            enqueue(frame)
            installTimeout(20)
        } catch {
            fail(GatewayUDPError.protocolError("PacketLogin failed: \(error.localizedDescription)"))
        }
    }

    // MARK: - Outbound frames

    private func sendConnectPacket() {
        guard stage == .negotiating else { return }
        do {
            let packet = try GatewayConnectPacket(connectCode: connectCode).encoded()
            rawSend(packet)
        } catch {
            fail(GatewayUDPError.protocolError(error.localizedDescription))
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.queue.async {
                guard self.stage == .negotiating else { return }
                self.sendConnectPacket()
            }
        }
        connectRetry?.cancel()
        connectRetry = item
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + Self.retryDelay,
            execute: item
        )
    }

    private func enqueue(_ frame: Data) {
        // With user-supplied compression the flag precedes the reliable id, so
        // the plain LoginFrameHeader parser cannot locate the id.
        let idOffset = userSuppliedCompression ? 3 : 2
        guard frame.count > idOffset + 1, frame[0] == 0,
              frame[1] >= UdpFrameType.reliable1.rawValue,
              frame[1] <= UdpFrameType.reliable4.rawValue
        else { return }
        let id = (UInt16(frame[idOffset]) << 8) | UInt16(frame[idOffset + 1])
        pendingFrames[id] = frame
        rawSend(frame)
        scheduleRetryIfNeeded()
    }

    private func scheduleRetryIfNeeded() {
        guard retryTimer == nil, !pendingFrames.isEmpty else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.queue.async {
                self.retryTimer = nil
                guard (self.continuation != nil || self.isActive), !self.pendingFrames.isEmpty else { return }
                for frame in self.pendingFrames.values { self.rawSend(frame) }
                self.scheduleRetryIfNeeded()
            }
        }
        retryTimer = item
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + Self.retryDelay,
            execute: item
        )
    }

    /// Keeps an idle authenticated connection alive. Sanctuary's gateway drops
    /// connections after 30 s without any received datagram; a periodic
    /// `[0, KeepAlive]` frame resets that timer on the server.
    private func scheduleKeepAlive() {
        guard isActive else { return }
        keepAliveTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.queue.async {
                guard self.isActive else { return }
                let packet = UdpLibrary.encodeKeepAlive(
                    encryptCode: self.encryptCode,
                    userSuppliedCompression: self.userSuppliedCompression
                )
                self.rawSend(packet)
                self.scheduleKeepAlive()
            }
        }
        keepAliveTimer = item
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + Self.keepAliveDelay,
            execute: item
        )
    }

    private func rawSend(_ packet: Data) {
        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            guard let self, let error else { return }
            self.queue.async {
                if self.continuation != nil || self.isActive {
                    self.fail(GatewayUDPError.transport(error.localizedDescription))
                }
            }
        })
    }

    /// Sends the post-login packets Sanctuary's gateway handlers recognize:
    /// locale (world wrapper opcode 88), initialization (tunneled opcode 169),
    /// finished loading (10), and ready (13). LocaleId and unknown fields in
    /// the original client are not available from Sanctuary source, so only
    /// the documented fields are emitted.
    func sendInitialPackets(locale: GameLocale) throws {
        try queue.sync {
            guard gateway.state == .authenticated else {
                throw GatewayUDPError.protocolError("Gateway is not authenticated")
            }

            // Sanctuary routes opcode 88 through PacketTunneledClientWorldPacket
            // and opcodes 169/10/13 through PacketTunneledClientPacket. Sending
            // them unwrapped would not reach any gateway handler.
            var setLocale = PacketWriter()
            GatewayWire.appendInt16(88, to: &setLocale.data)
            setLocale.writeString(locale.rawValue)
            let wrappedLocale = GatewayPacketCodec.encode(
                GatewayTunneledWorldPacket(reliable: true, payload: setLocale.data)
            )
            enqueue(try gateway.send(packet: wrappedLocale))

            var initialization = PacketWriter()
            GatewayWire.appendInt16(169, to: &initialization.data)
            let minutes = Int32(TimeZone.current.secondsFromGMT() / 60)
            initialization.writeInt32(minutes)
            let wrappedInitialization = GatewayPacketCodec.encode(
                GatewayTunneledPacket(reliable: true, payload: initialization.data)
            )
            enqueue(try gateway.send(packet: wrappedInitialization))

            var finished = PacketWriter()
            GatewayWire.appendInt16(10, to: &finished.data)
            let wrappedFinished = GatewayPacketCodec.encode(
                GatewayTunneledPacket(reliable: true, payload: finished.data)
            )
            enqueue(try gateway.send(packet: wrappedFinished))

            var ready = PacketWriter()
            GatewayWire.appendInt16(13, to: &ready.data)
            let wrappedReady = GatewayPacketCodec.encode(
                GatewayTunneledPacket(reliable: true, payload: ready.data)
            )
            enqueue(try gateway.send(packet: wrappedReady))
        }
    }

    func currentState() -> GatewaySessionState {
        queue.sync { gateway.state }
    }

    /// Installs a callback for decoded world packets. It is invoked on the
    /// gateway receive queue; callers must hop to their own UI queue.
    func setWorldEventHandler(_ handler: @escaping (GatewayWorldPacket) -> Void) {
        queue.sync { worldEventHandler = handler }
    }

    // MARK: - Lifecycle

    private func installTimeout(_ timeout: TimeInterval) {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.queue.async {
                guard self.continuation != nil else { return }
                self.record("timeout stage=\(self.stage)")
                self.fail(GatewayUDPError.timeout("\(self.stage) reply;\(self.diagnosticSuffix)"))
            }
        }
        timeoutWork?.cancel()
        timeoutWork = item
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + max(1, timeout),
            execute: item
        )
    }

    private func completeLogin() {
        // Capture the continuation before clearing it. Resuming through the
        // optional property after setting it to nil silently drops the resume
        // and leaves `connect()` waiting until its timeout fires.
        guard let pendingContinuation = continuation else { return }
        self.continuation = nil
        isActive = true
        connectRetry?.cancel()
        timeoutWork?.cancel()
        connectRetry = nil
        timeoutWork = nil
        scheduleKeepAlive()
        pendingContinuation.resume(returning: ())
    }

    /// Closes an authenticated gateway session. Pending reliable frames are
    /// dropped because the server will reject them after the player leaves.
    func close() {
        queue.async {
            self.isActive = false
            self.cancelTimersAndPendingFrames()
            self.worldEventHandler = nil
            self.connection.stateUpdateHandler = nil
            self.connection.cancel()
        }
    }

    private func fail(_ error: GatewayUDPError) {
        let pendingContinuation = continuation
        continuation = nil
        isActive = false
        cancelTimersAndPendingFrames()
        worldEventHandler = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        pendingContinuation?.resume(throwing: error)
    }

    private func cancelTimersAndPendingFrames() {
        connectRetry?.cancel()
        retryTimer?.cancel()
        keepAliveTimer?.cancel()
        timeoutWork?.cancel()
        connectRetry = nil
        retryTimer = nil
        keepAliveTimer = nil
        timeoutWork = nil
        pendingFrames.removeAll()
        incomingReliable.reset()
    }

    deinit {
        cancelTimersAndPendingFrames()
        connection.cancel()
    }
}
