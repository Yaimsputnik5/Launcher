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
//   "LoginUdp_6", CrcBytes=2 and EncryptMethod[0]=None unless compression is
//   explicitly enabled (the checked-in config does not enable it).
// - Sanctuary.Login/LoginConnection.cs: application packets are encrypted with
//   the fixed RC4 key before UdpLibrary framing, and outbound messages always
//   use UdpChannel.Reliable1.
//
// Scope: this implements the client handshake and reliable session request
// path needed for a native launcher. Character select, gateway tunnel and
// resend-window congestion control are deliberately left to higher layers.

enum LoginUDPError: LocalizedError {
    case invalidAddress(String)
    case timeout(String)
    case transport(String)
    case protocolError(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress(let value): return "Invalid login server address: \(value)"
        case .timeout(let stage): return "Timed out waiting for \(stage)."
        case .transport(let detail): return "Login connection failed: \(detail)"
        case .protocolError(let detail): return "Invalid Login UDP packet: \(detail)"
        }
    }
}

/// Result of a Login UDP session handshake and session request.
struct LoginUDPSessionResult: Equatable {
    var reply: LoginProtocol.SessionReply
    var accountInfo: LoginProtocol.AccountInfo?

    init(reply: LoginProtocol.SessionReply) {
        self.reply = reply
        self.accountInfo = try? reply.accountInfo()
    }
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

    private enum Phase {
        case negotiating
        case connected
    }

    private let endpoint: NWEndpoint
    private let queue = DispatchQueue(label: "dev.opensourcefreerealms.login-udp")
    private let connection: NWConnection
    private let connectCode: UInt32
    private let generation: UInt64

    private var phase: Phase = .negotiating
    private var encryptCode: UInt32 = 0
    private var cipher = LoginCipher()
    private var outgoingReliableID: UInt16 = 0
    private var pendingLoginFrame: Data?
    private var continuation: CheckedContinuation<LoginUDPSessionResult, Error>?
    private var connectRetry: DispatchWorkItem?
    private var loginRetry: DispatchWorkItem?
    private var timeoutWork: DispatchWorkItem?

    private init(endpoint: NWEndpoint, generation: UInt64) {
        self.endpoint = endpoint
        self.generation = generation
        connectCode = UInt32(truncatingIfNeeded: Int.random(in: Int.min...Int.max))
        connection = NWConnection(to: endpoint, using: .udp)
    }

    /// Authenticates a WebAPI session with the Sanctuary Login UDP listener.
    /// `address` accepts `host`, `host:port`, and bracketed IPv6 forms.
    static func authenticate(
        address: String,
        sessionID: String,
        fingerprint: String,
        timeout: TimeInterval = 12
    ) async throws -> LoginUDPSessionResult {
        guard let (host, port) = ServerStatusClient.parse(address) else {
            throw LoginUDPError.invalidAddress(address)
        }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw LoginUDPError.invalidAddress(address)
        }
        let session = LoginUDPSession(
            endpoint: NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort),
            generation: 1
        )
        return try await session.run(sessionID: sessionID, fingerprint: fingerprint, timeout: timeout)
    }

    /// Authenticates using an already-parsed host/port pair.
    static func authenticate(
        host: String,
        port: UInt16,
        sessionID: String,
        fingerprint: String,
        timeout: TimeInterval = 12
    ) async throws -> LoginUDPSessionResult {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw LoginUDPError.invalidAddress("\(host):\(port)")
        }
        let session = LoginUDPSession(
            endpoint: NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort),
            generation: 1
        )
        return try await session.run(sessionID: sessionID, fingerprint: fingerprint, timeout: timeout)
    }

    private func run(
        sessionID: String,
        fingerprint: String,
        timeout: TimeInterval
    ) async throws -> LoginUDPSessionResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.continuation = continuation
                self.currentSessionID = sessionID
                self.currentFingerprint = fingerprint
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
            finish(.failure(.transport(error.localizedDescription)))
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
                    self.finish(.failure(.transport(error.localizedDescription)))
                    return
                }
                guard let data, !data.isEmpty else {
                    self.finish(.failure(.transport("Connection closed")))
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
        switch data[1] {
        case 2:
            handleConfirm(data)
        case 17...20:
            // Ack for our reliable request. The login request is tiny, so we
            // keep retransmitting until a reply arrives rather than modeling
            // the full sliding window.
            break
        case 9...12:
            handleReliable(data)
        default:
            break
        }
    }

    private func handleConfirm(_ data: Data) {
        // 0, Confirm, ConnectCode, EncryptCode, CrcBytes, EncryptMethod[2],
        // MaxRawPacketSize, optional ProtocolVersion. UdpConnection.cs accepts
        // the shorter 17-byte form from older peers.
        guard data.count >= 17 else {
            finish(.failure(.protocolError("Truncated Confirm packet")))
            return
        }
        guard readBE32(data, offset: 2) == connectCode else { return }
        guard data[10] == Self.crcBytes else {
            finish(.failure(.protocolError("Unsupported CRC byte count \(data[10])")))
            return
        }
        encryptCode = readBE32(data, offset: 6)
        phase = .connected
        connectRetry?.cancel()
        connectRetry = nil
        // The remote EncryptCode seeds the UDP CRC. Application RC4 state is
        // independent and was initialized with the fixed login key.
        sendSessionRequest()
    }

    private func handleReliable(_ data: Data) {
        do {
            let frame = try LoginFrame.decode(data, encryptCode: encryptCode)
            sendAck(for: frame.header)
            let plaintext = cipher.decryptPacket(frame.ciphertext)
            guard let message = try? LoginPacket.decodeAny(from: plaintext) else { return }
            if case .sessionReply(let reply) = message {
                loginRetry?.cancel()
                loginRetry = nil
                finish(.success(LoginUDPSessionResult(reply: reply)))
            }
        } catch {
            // A malformed datagram is ignored; the overall timeout keeps the
            // caller from hanging if every packet is corrupt.
            _ = error
        }
    }

    // MARK: - Sending

    private func sendConnectPacket() {
        guard phase == .negotiating else { return }
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
                guard self.continuation != nil, self.phase == .negotiating else { return }
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
        guard pendingLoginFrame == nil, continuation != nil else { return }
        let request = LoginProtocol.SessionRequest(
            sessionID: currentSessionID,
            fingerprint: currentFingerprint
        )
        let packet = LoginPacket.encode(request)
        let header = LoginFrameHeader(type: .reliable1, reliableID: outgoingReliableID)
        let frame = LoginFrame.encode(
            header: header,
            encryptCode: encryptCode,
            ciphertext: cipher.encryptPacket(packet)
        )
        pendingLoginFrame = frame
        rawSend(frame)
        scheduleLoginRetry()
    }

    // Set immediately before the first send; stored on the serial queue.
    private var currentSessionID = ""
    private var currentFingerprint = ""

    private func scheduleLoginRetry() {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.queue.async {
                guard self.continuation != nil, let frame = self.pendingLoginFrame else { return }
                self.rawSend(frame)
                self.scheduleLoginRetry()
            }
        }
        loginRetry?.cancel()
        loginRetry = item
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + Self.connectAttemptDelay,
            execute: item
        )
    }

    private func sendAck(for header: LoginFrameHeader) {
        let channel = Int(header.type.rawValue - UdpFrameType.reliable1.rawValue)
        guard channel >= 0, channel < 4 else { return }
        let ackType = 17 + UInt8(channel)
        var packet = Data([0, ackType])
        appendBE16(header.reliableID, to: &packet)
        let crc = UInt16(truncatingIfNeeded: CRC32.checksum(packet, encryptCode: encryptCode))
        appendBE16(crc, to: &packet)
        rawSend(packet)
    }

    private func rawSend(_ packet: Data) {
        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            guard let self, let error else { return }
            self.queue.async {
                self.finish(.failure(.transport(error.localizedDescription)))
            }
        })
    }

    // MARK: - Lifecycle

    private func installTimeout(_ timeout: TimeInterval) {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.queue.async {
                guard self.continuation != nil else { return }
                self.finish(.failure(.timeout(self.phase == .negotiating ? "Login UDP confirm" : "Login reply")))
            }
        }
        timeoutWork?.cancel()
        timeoutWork = item
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + max(1, timeout),
            execute: item
        )
    }

    private func finish(_ result: Result<LoginUDPSessionResult, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        connectRetry?.cancel()
        loginRetry?.cancel()
        timeoutWork?.cancel()
        connectRetry = nil
        loginRetry = nil
        timeoutWork = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        switch result {
        case .success(let value): continuation.resume(returning: value)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    deinit {
        connectRetry?.cancel()
        loginRetry?.cancel()
        timeoutWork?.cancel()
        connection.cancel()
    }

    // MARK: - Byte helpers

    private func readBE32(_ data: Data, offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        var value: UInt32 = 0
        for index in 0..<4 {
            value = (value << 8) | UInt32(data[offset + index])
        }
        return value
    }

    private func appendBE16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }

    private func appendBE32(_ value: Int32, to data: inout Data) {
        appendBE32(UInt32(bitPattern: value), to: &data)
    }

    private func appendBE32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value >> 24))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }
}
