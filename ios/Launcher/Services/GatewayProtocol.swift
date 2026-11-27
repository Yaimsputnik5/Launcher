import Foundation

// Pure codecs and session state for Sanctuary's client-facing `CGAPI_527`
// gateway protocol. No sockets, no SwiftUI/UIKit, Foundation only.
//
// Source map (Sanctuary fork under /tmp/opencode/sanctuary/src):
// - Sanctuary.Gateway/Program.cs and sanctuary-audit/03-protocol-and-servers.md:
//   the gateway UDP protocol is named "CGAPI_527"; checked-in config sets
//   CrcBytes = 2 and UseCompression = true.
// - Sanctuary.Core/Cryptography/CipherCCM.cs: AES-CCM with a 16-byte tag,
//   13-byte nonce (little-endian UInt64 counter + 5 random bytes), strict
//   increasing receive counter, ciphertext || tag || nonce on the wire, and
//   rejection of all-zero nonce/tag buffers.
// - Sanctuary.Gateway/Handlers/PacketLoginHandler.cs: the ASCII ticket string
//   (Guid.ToString("N") == 32 hex characters from
//   Sanctuary.Login/Handlers/CharacterLoginRequestHandler.cs) is the AES key.
// - Sanctuary.Core/IO/PacketUtils.cs: secure packets end with a one-byte
//   encryption flag (1) and little-endian magic 0xF3D4A5C9; plain packets have
//   no trailer. Sanctuary's GatewayConnection hardcodes _useEncryption = false,
//   so secure sends go through WrapPacket(..., encrypt: true, cipher).
// - Sanctuary.UdpLibrary/UdpConnection.cs, Internal/UdpReliableChannel.cs and
//   Internal/Constants.cs: physical frame = 0x00, packet type, big-endian
//   UInt16 reliable id, application bytes, 2-byte big-endian CRC seeded by
//   EncryptCode. Application bytes beginning with 0x00 get one escape byte.
//   Connect/confirm packets use big-endian Int32 fields.
// - Sanctuary.Packet/ClientGateway/{PacketLogin,PacketLoginReply,
//   PacketTunneledClientPacket,PacketTunneledClientWorldPacket}.cs: short
//   (little-endian Int16) gateway opcodes 1, 2, 5 and 6.
// - Sanctuary.Packet/Custom/{GatewayCharacterLogin,GatewayCharacterLogout,
//   GatewayCharacterReleaseRequest,GatewayCharacterReleaseReply,
//   GatewayLoginReply}.cs: byte opcodes 101-105 on the gateway<->login link.
// - Sanctuary.Packet/PlayerUpdatePacketUpdatePosition.cs (opcode 125) and
//   Sanctuary.Packet/BaseChatPacket.cs + BaseChatPacket/PacketChat.cs
//   (opcode 15, sub-opcode 1) for the two world packets decoded here.
//
// Deliberate boundaries:
// - No AES/CCM test vector exists in Sanctuary. The tests use the public
//   FIPS-197 AES known-answer vectors, a CCM vector computed with an
//   independent AESCCM implementation (13-byte nonce, no AAD), and round trips.
// - zlib compression bytes (flag 1 in GatewayConnection.EncryptUserSupplied)
//   are decoded by the shared UdpLibraryTransport helper when the platform
//   exposes the Compression framework; outbound packets always use raw (0).
// - Reliable resend/ack windows are transport concerns. Outgoing reliable ids
//   are generated here; incoming ids are recorded but not used for replay
//   rejection because Sanctuary accepts retransmits inside its sliding window.
//   Replay protection for encrypted traffic is the CCM nonce counter.

// MARK: - Errors

enum GatewayProtocolError: Error, LocalizedError, Equatable {
    case invalidKeyLength(Int)
    case invalidNonceLength(Int)
    case invalidTagLength(Int)
    case plaintextTooLong(Int)
    case aadTooLong(Int)
    case authenticationFailed
    case counterExhausted
    case invalidCipherTrailer
    case replayRejected(counter: UInt64, last: UInt64)
    case cipherNotInitialized
    case invalidTicketKey(String)

    case physicalFrame(LoginProtocolError)
    case frameTooShort(expected: Int, available: Int)
    case invalidFrameMarker(UInt8)
    case unexpectedFrameType(expected: UInt8, actual: UInt8)
    case invalidZeroEscape
    case crcMismatch(expected: UInt16, actual: UInt16)
    case missingCompressionFlag
    case unsupportedCompression(UInt8)

    case invalidWrapperMagic(UInt32)
    case invalidEncryptionFlag(UInt8)

    case unexpectedOpcode(expected: Int16, actual: Int16)
    case unsupportedOpcode(Int16)
    case unexpectedInternalOpcode(expected: UInt8, actual: UInt8)
    case unsupportedInternalOpcode(UInt8)
    case trailingBytes(Int)
    case wire(ProtocolError)
    case invalidState(expected: String, actual: String)
    case invalidASCII
    case malformedFrame(String)

    var errorDescription: String? {
        switch self {
        case .invalidKeyLength(let count):
            return "AES key must be 16, 24 or 32 bytes; got \(count)."
        case .invalidNonceLength(let count):
            return "CCM nonce must be 13 bytes; got \(count)."
        case .invalidTagLength(let count):
            return "CCM tag must be 16 bytes; got \(count)."
        case .plaintextTooLong(let count):
            return "CCM plaintext length \(count) exceeds the 2-byte length field."
        case .aadTooLong(let count):
            return "CCM AAD length \(count) exceeds the 2-byte encoding limit."
        case .authenticationFailed:
            return "AES-CCM tag verification failed."
        case .counterExhausted:
            return "AES-CCM nonce counter is exhausted."
        case .invalidCipherTrailer:
            return "AES-CCM tag or nonce is all zero."
        case .replayRejected(let counter, let last):
            return "Replay rejected: nonce counter \(counter) <= \(last)."
        case .cipherNotInitialized:
            return "Gateway cipher has not been initialized."
        case .invalidTicketKey(let ticket):
            return "Gateway ticket is not a 32-character ASCII crypto key: \(ticket.count) characters."
        case .physicalFrame(let error):
            return error.errorDescription ?? "Invalid gateway physical frame."
        case .frameTooShort(let expected, let available):
            return "Truncated gateway frame: needed \(expected) byte(s), only \(available) available."
        case .invalidFrameMarker(let value):
            return "Invalid gateway frame marker 0x\(String(value, radix: 16)); expected 0x00."
        case .unexpectedFrameType(let expected, let actual):
            return "Expected gateway frame type \(expected), found \(actual)."
        case .invalidZeroEscape:
            return "Zero-escaped gateway frame does not start with two 0x00 bytes."
        case .crcMismatch(let expected, let actual):
            return String(format: "Gateway frame CRC mismatch: expected 0x%04X, found 0x%04X.", expected, actual)
        case .missingCompressionFlag:
            return "Gateway frame is missing the user-supplied compression flag."
        case .unsupportedCompression(let flag):
            return "Unsupported gateway compression flag \(flag); only raw (0) is decoded."
        case .invalidWrapperMagic(let magic):
            return String(format: "Invalid gateway wrapper magic 0x%08X.", magic)
        case .invalidEncryptionFlag(let flag):
            return "Invalid gateway encryption flag \(flag); expected 1."
        case .unexpectedOpcode(let expected, let actual):
            return "Expected gateway opcode \(expected), found \(actual)."
        case .unsupportedOpcode(let opcode):
            return "Unsupported gateway opcode \(opcode)."
        case .unexpectedInternalOpcode(let expected, let actual):
            return "Expected gateway/login opcode \(expected), found \(actual)."
        case .unsupportedInternalOpcode(let opcode):
            return "Unsupported gateway/login opcode \(opcode)."
        case .trailingBytes(let count):
            return "\(count) trailing byte(s) after gateway packet body."
        case .wire(let error):
            return error.errorDescription ?? "Invalid gateway wire primitive."
        case .invalidState(let expected, let actual):
            return "Invalid gateway session state: expected \(expected), found \(actual)."
        case .invalidASCII:
            return "Gateway protocol name or connect data is not ASCII."
        case .malformedFrame(let detail):
            return "Malformed gateway frame: \(detail)"
        }
    }
}

// MARK: - Wire helpers

private func appendLE64(_ value: UInt64, to data: inout Data) {
    for shift in stride(from: 0, to: 64, by: 8) {
        data.append(UInt8(truncatingIfNeeded: value >> shift))
    }
}

private func readLE64(_ bytes: ArraySlice<UInt8>) -> UInt64? {
    guard bytes.count == 8 else { return nil }
    var value: UInt64 = 0
    for (index, byte) in bytes.enumerated() {
        value |= UInt64(byte) << (8 * index)
    }
    return value
}

private func isAllZero(_ bytes: [UInt8]) -> Bool {
    bytes.allSatisfy { $0 == 0 }
}

private func constantTimeEquals(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
    guard lhs.count == rhs.count else { return false }
    var difference: UInt8 = 0
    for index in lhs.indices {
        difference |= lhs[index] ^ rhs[index]
    }
    return difference == 0
}

/// Sanctuary's connect/confirm fields are big-endian even though application
/// packets are little-endian (UdpConnection.cs).
enum GatewayWire {
    static func appendBE32(_ value: UInt32, to data: inout Data) {
        for shift in stride(from: 24, through: 0, by: -8) {
            data.append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }

    static func readBE32(_ reader: inout PacketReader) throws -> UInt32 {
        try reader.readUInt32().byteSwapped
    }

    static func appendInt16(_ value: Int16, to data: inout Data) {
        data.append(contentsOf: [
            UInt8(truncatingIfNeeded: UInt16(bitPattern: value)),
            UInt8(truncatingIfNeeded: UInt16(bitPattern: value) >> 8)
        ])
    }

    static func readInt16(_ reader: inout PacketReader) throws -> Int16 {
        Int16(bitPattern: try reader.readUInt16())
    }
}

// MARK: - AES block cipher

/// AES-128/192/256 block cipher. The implementation is self-contained so the
/// iOS target needs no CryptoKit/CommonCrypto dependency. Sanctuary uses
/// `System.Security.Cryptography.AesCcm` (CipherCCM.cs); .NET accepts the same
/// three key sizes used here.
struct AESBlock {
    private let rounds: Int
    private let roundKeys: [UInt8]

    private static let sBox: [UInt8] = [
        0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
        0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
        0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
        0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
        0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
        0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
        0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
        0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
        0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
        0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
        0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
        0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
        0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
        0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
        0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
        0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
    ]

    private static let inverseSBox: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 256)
        for (index, value) in sBox.enumerated() {
            table[Int(value)] = UInt8(index)
        }
        return table
    }()

    private static let rcon: [UInt8] = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36]

    init(key: Data) throws {
        let bytes = Array(key)
        guard bytes.count == 16 || bytes.count == 24 || bytes.count == 32 else {
            throw GatewayProtocolError.invalidKeyLength(bytes.count)
        }

        let nk = bytes.count / 4
        let nr = nk + 6
        var words = [[UInt8]](repeating: [0, 0, 0, 0], count: 4 * (nr + 1))

        for index in 0..<nk {
            words[index] = Array(bytes[(index * 4)..<(index * 4 + 4)])
        }

        for index in nk..<words.count {
            var temp = words[index - 1]
            if index % nk == 0 {
                temp = AESBlock.subWord(AESBlock.rotWord(temp))
                temp[0] ^= AESBlock.rcon[index / nk - 1]
            } else if nk > 6 && index % nk == 4 {
                temp = AESBlock.subWord(temp)
            }
            let previous = words[index - nk]
            words[index] = [UInt8](repeating: 0, count: 4)
            for byte in 0..<4 {
                words[index][byte] = previous[byte] ^ temp[byte]
            }
        }

        self.rounds = nr
        self.roundKeys = words.flatMap { $0 }
    }

    func encryptBlock(_ input: [UInt8]) -> [UInt8] {
        precondition(input.count == 16, "AES operates on exactly one 16-byte block")
        var state = input
        addRoundKey(&state, round: 0)
        for round in 1..<rounds {
            subBytes(&state, inverse: false)
            shiftRows(&state, inverse: false)
            mixColumns(&state, inverse: false)
            addRoundKey(&state, round: round)
        }
        subBytes(&state, inverse: false)
        shiftRows(&state, inverse: false)
        addRoundKey(&state, round: rounds)
        return state
    }

    func decryptBlock(_ input: [UInt8]) -> [UInt8] {
        precondition(input.count == 16, "AES operates on exactly one 16-byte block")
        var state = input
        addRoundKey(&state, round: rounds)
        for round in stride(from: rounds - 1, through: 1, by: -1) {
            shiftRows(&state, inverse: true)
            subBytes(&state, inverse: true)
            addRoundKey(&state, round: round)
            mixColumns(&state, inverse: true)
        }
        shiftRows(&state, inverse: true)
        subBytes(&state, inverse: true)
        addRoundKey(&state, round: 0)
        return state
    }

    private func addRoundKey(_ state: inout [UInt8], round: Int) {
        let offset = round * 16
        for index in 0..<16 {
            state[index] ^= roundKeys[offset + index]
        }
    }

    private func subBytes(_ state: inout [UInt8], inverse: Bool) {
        let table = inverse ? AESBlock.inverseSBox : AESBlock.sBox
        for index in 0..<16 {
            state[index] = table[Int(state[index])]
        }
    }

    /// AES state is column-major: state[row + 4 * column].
    private func shiftRows(_ state: inout [UInt8], inverse: Bool) {
        var result = state
        for row in 0..<4 {
            for column in 0..<4 {
                let sourceColumn = inverse
                    ? (column - row + 4) % 4
                    : (column + row) % 4
                result[row + 4 * column] = state[row + 4 * sourceColumn]
            }
        }
        state = result
    }

    private func mixColumns(_ state: inout [UInt8], inverse: Bool) {
        for column in 0..<4 {
            let offset = 4 * column
            let a0 = state[offset]
            let a1 = state[offset + 1]
            let a2 = state[offset + 2]
            let a3 = state[offset + 3]
            if inverse {
                state[offset] = AESBlock.mul(a0, 14) ^ AESBlock.mul(a1, 11) ^ AESBlock.mul(a2, 13) ^ AESBlock.mul(a3, 9)
                state[offset + 1] = AESBlock.mul(a0, 9) ^ AESBlock.mul(a1, 14) ^ AESBlock.mul(a2, 11) ^ AESBlock.mul(a3, 13)
                state[offset + 2] = AESBlock.mul(a0, 13) ^ AESBlock.mul(a1, 9) ^ AESBlock.mul(a2, 14) ^ AESBlock.mul(a3, 11)
                state[offset + 3] = AESBlock.mul(a0, 11) ^ AESBlock.mul(a1, 13) ^ AESBlock.mul(a2, 9) ^ AESBlock.mul(a3, 14)
            } else {
                let all = a0 ^ a1 ^ a2 ^ a3
                state[offset] = a0 ^ all ^ AESBlock.xtime(a0 ^ a1)
                state[offset + 1] = a1 ^ all ^ AESBlock.xtime(a1 ^ a2)
                state[offset + 2] = a2 ^ all ^ AESBlock.xtime(a2 ^ a3)
                state[offset + 3] = a3 ^ all ^ AESBlock.xtime(a3 ^ a0)
            }
        }
    }

    private static func rotWord(_ word: [UInt8]) -> [UInt8] {
        [word[1], word[2], word[3], word[0]]
    }

    private static func subWord(_ word: [UInt8]) -> [UInt8] {
        word.map { sBox[Int($0)] }
    }

    private static func xtime(_ value: UInt8) -> UInt8 {
        (value << 1) ^ ((value & 0x80) != 0 ? 0x1b : 0)
    }

    private static func mul(_ lhs: UInt8, _ rhs: UInt8) -> UInt8 {
        var product: UInt8 = 0
        var left = lhs
        var right = rhs
        for _ in 0..<8 {
            if (right & 1) != 0 {
                product ^= left
            }
            left = xtime(left)
            right >>= 1
        }
        return product
    }
}

// MARK: - AES-CCM

/// CCM with the parameters used by Sanctuary's `CipherCCM`: 13-byte nonce
/// (L = 2), 16-byte tag (M = 16), no AAD on the wire. AAD is accepted for
/// completeness and to exercise the CCM B0 Adata flag.
struct AESCCM {
    static let nonceLength = 13
    static let tagLength = 16

    private let aes: AESBlock

    init(key: Data) throws {
        aes = try AESBlock(key: key)
    }

    func encrypt(nonce: Data, plaintext: Data, aad: Data = Data()) throws -> (ciphertext: Data, tag: Data) {
        let nonceBytes = Array(nonce)
        guard nonceBytes.count == AESCCM.nonceLength else {
            throw GatewayProtocolError.invalidNonceLength(nonceBytes.count)
        }
        let plainBytes = Array(plaintext)
        guard plainBytes.count <= 0xFFFF else {
            throw GatewayProtocolError.plaintextTooLong(plainBytes.count)
        }
        let aadBytes = Array(aad)
        guard aadBytes.count < 0xFF00 else {
            throw GatewayProtocolError.aadTooLong(aadBytes.count)
        }

        let mac = try authenticate(nonceBytes: nonceBytes, payload: plainBytes, aad: aadBytes)
        let (tagMask, stream) = keyStream(nonceBytes: nonceBytes, length: plainBytes.count)
        let ciphertext = zip(plainBytes, stream).map { $0.0 ^ $0.1 }
        let tag = zip(mac, tagMask).map { $0.0 ^ $0.1 }
        return (Data(ciphertext), Data(tag))
    }

    func decrypt(nonce: Data, ciphertext: Data, tag: Data, aad: Data = Data()) throws -> Data {
        let nonceBytes = Array(nonce)
        guard nonceBytes.count == AESCCM.nonceLength else {
            throw GatewayProtocolError.invalidNonceLength(nonceBytes.count)
        }
        let cipherBytes = Array(ciphertext)
        guard cipherBytes.count <= 0xFFFF else {
            throw GatewayProtocolError.plaintextTooLong(cipherBytes.count)
        }
        let tagBytes = Array(tag)
        guard tagBytes.count == AESCCM.tagLength else {
            throw GatewayProtocolError.invalidTagLength(tagBytes.count)
        }
        let aadBytes = Array(aad)
        guard aadBytes.count < 0xFF00 else {
            throw GatewayProtocolError.aadTooLong(aadBytes.count)
        }

        // CCM authenticates the PLAINTEXT (RFC 3610), so recover it with the
        // CTR stream first, then verify the CBC-MAC over those bytes.
        let (tagMask, stream) = keyStream(nonceBytes: nonceBytes, length: cipherBytes.count)
        let plaintext = zip(cipherBytes, stream).map { $0.0 ^ $0.1 }
        let mac = try authenticate(nonceBytes: nonceBytes, payload: plaintext, aad: aadBytes)
        let expectedTag = zip(mac, tagMask).map { $0.0 ^ $0.1 }
        guard constantTimeEquals(expectedTag, tagBytes) else {
            throw GatewayProtocolError.authenticationFailed
        }
        return Data(plaintext)
    }

    private func authenticate(nonceBytes: [UInt8], payload: [UInt8], aad: [UInt8]) throws -> [UInt8] {
        // B0 flags: Adata bit, (M-2)/2 << 3, L-1. With M=16 and L=2 this is
        // 0x39 (or 0x79 when AAD is present).
        let flags: UInt8 = (aad.isEmpty ? 0x00 : 0x40) | 0x38 | 0x01
        let firstBlock = [flags] + nonceBytes + [
            UInt8(truncatingIfNeeded: payload.count >> 8),
            UInt8(truncatingIfNeeded: payload.count)
        ]
        guard firstBlock.count == 16 else {
            throw GatewayProtocolError.invalidNonceLength(nonceBytes.count)
        }

        var blocks: [[UInt8]] = [firstBlock]

        if !aad.isEmpty {
            var encodedAAD: [UInt8] = [
                UInt8(truncatingIfNeeded: aad.count >> 8),
                UInt8(truncatingIfNeeded: aad.count)
            ]
            encodedAAD.append(contentsOf: aad)
            padToBlock(&encodedAAD)
            var offset = 0
            while offset < encodedAAD.count {
                blocks.append(Array(encodedAAD[offset..<(offset + 16)]))
                offset += 16
            }
        }

        var paddedPayload = payload
        padToBlock(&paddedPayload)
        var offset = 0
        while offset < paddedPayload.count {
            blocks.append(Array(paddedPayload[offset..<(offset + 16)]))
            offset += 16
        }

        var state = [UInt8](repeating: 0, count: 16)
        for block in blocks {
            let mixed = zip(state, block).map { $0.0 ^ $0.1 }
            state = aes.encryptBlock(mixed)
        }
        return state
    }

    private func keyStream(nonceBytes: [UInt8], length: Int) -> ([UInt8], [UInt8]) {
        let first = aes.encryptBlock(counterBlock(nonceBytes: nonceBytes, counter: 0))
        var stream: [UInt8] = []
        stream.reserveCapacity(length)
        var counter = 1
        var offset = 0
        while offset < length {
            let block = aes.encryptBlock(counterBlock(nonceBytes: nonceBytes, counter: counter))
            let take = min(16, length - offset)
            stream.append(contentsOf: block[0..<take])
            offset += take
            counter += 1
        }
        return (first, stream)
    }

    /// A_i: flags (L-1), nonce, big-endian counter. A_0 masks the tag.
    private func counterBlock(nonceBytes: [UInt8], counter: Int) -> [UInt8] {
        var block: [UInt8] = [0x01]
        block.append(contentsOf: nonceBytes)
        block.append(UInt8(truncatingIfNeeded: counter >> 8))
        block.append(UInt8(truncatingIfNeeded: counter))
        return block
    }

    private func padToBlock(_ bytes: inout [UInt8]) {
        let remainder = bytes.count % 16
        if remainder != 0 {
            bytes.append(contentsOf: repeatElement(0, count: 16 - remainder))
        }
    }
}

// MARK: - Sanctuary CipherCCM wrapper

/// `Sanctuary.Core.Cryptography.CipherCCM`: one increasing counter per
/// direction, ciphertext || 16-byte tag || 13-byte nonce on the wire.
struct GatewayCipher {
    private let ccm: AESCCM
    private(set) var encryptCounter: UInt64 = 0
    private(set) var decryptCounter: UInt64 = 0

    init(key: Data) throws {
        ccm = try AESCCM(key: key)
    }

    /// `nonceSuffix` overrides the random 5-byte tail for deterministic tests;
    /// production callers must leave it nil.
    mutating func encrypt(_ plaintext: Data, nonceSuffix: Data? = nil) throws -> Data {
        guard encryptCounter < UInt64.max else {
            throw GatewayProtocolError.counterExhausted
        }
        encryptCounter += 1

        let suffix: [UInt8]
        if let nonceSuffix {
            guard nonceSuffix.count == 5 else {
                throw GatewayProtocolError.malformedFrame("nonce suffix must be 5 bytes")
            }
            suffix = Array(nonceSuffix)
        } else {
            var generator = SystemRandomNumberGenerator()
            suffix = (0..<5).map { _ in UInt8.random(in: 0...255, using: &generator) }
        }

        var nonce = Data()
        appendLE64(encryptCounter, to: &nonce)
        nonce.append(contentsOf: suffix)

        let result = try ccm.encrypt(nonce: nonce, plaintext: plaintext)
        var output = result.ciphertext
        output.append(result.tag)
        output.append(nonce)
        return output
    }

    mutating func decrypt(_ framed: Data) throws -> Data {
        let minimum = AESCCM.tagLength + AESCCM.nonceLength
        guard framed.count >= minimum else {
            throw GatewayProtocolError.frameTooShort(expected: minimum, available: framed.count)
        }

        let bytes = Array(framed)
        let nonce = Array(bytes.suffix(AESCCM.nonceLength))
        let tagStart = bytes.count - AESCCM.nonceLength - AESCCM.tagLength
        let tag = Array(bytes[tagStart..<(bytes.count - AESCCM.nonceLength)])
        let ciphertext = Array(bytes[0..<tagStart])

        guard !isAllZero(nonce), !isAllZero(tag) else {
            throw GatewayProtocolError.invalidCipherTrailer
        }
        guard let counter = readLE64(nonce[0..<8]) else {
            throw GatewayProtocolError.malformedFrame("nonce is too short")
        }
        guard counter > decryptCounter else {
            throw GatewayProtocolError.replayRejected(counter: counter, last: decryptCounter)
        }

        let plaintext = try ccm.decrypt(
            nonce: Data(nonce),
            ciphertext: Data(ciphertext),
            tag: Data(tag)
        )
        decryptCounter = counter
        return plaintext
    }
}

// MARK: - Connect / confirm packets

/// `UdpConnection.cs` connect packet. Protocol name is ASCII and NUL
/// terminated; all integers are big-endian.
struct GatewayConnectPacket: Equatable {
    static let protocolVersion: Int32 = 3
    static let protocolName = "CGAPI_527"
    static let maxRawPacketSize: Int32 = 0x2000

    var protocolVersion: Int32
    var connectCode: Int32
    var maxRawPacketSize: Int32
    var protocolName: String

    init(connectCode: Int32,
         protocolVersion: Int32 = GatewayConnectPacket.protocolVersion,
         maxRawPacketSize: Int32 = GatewayConnectPacket.maxRawPacketSize,
         protocolName: String = GatewayConnectPacket.protocolName) {
        self.protocolVersion = protocolVersion
        self.connectCode = connectCode
        self.maxRawPacketSize = maxRawPacketSize
        self.protocolName = protocolName
    }

    func encoded() throws -> Data {
        guard let name = protocolName.data(using: .ascii), !name.isEmpty, !name.contains(0) else {
            throw GatewayProtocolError.invalidASCII
        }
        var data = Data([0x00, UdpFrameType.connect.rawValue])
        GatewayWire.appendBE32(UInt32(bitPattern: protocolVersion), to: &data)
        GatewayWire.appendBE32(UInt32(bitPattern: connectCode), to: &data)
        GatewayWire.appendBE32(UInt32(bitPattern: maxRawPacketSize), to: &data)
        data.append(name)
        data.append(0)
        return data
    }

    init(data: Data) throws {
        let bytes = Array(data)
        guard bytes.count >= 15 else {
            throw GatewayProtocolError.frameTooShort(expected: 15, available: bytes.count)
        }
        guard bytes[0] == 0x00 else { throw GatewayProtocolError.invalidFrameMarker(bytes[0]) }
        guard bytes[1] == UdpFrameType.connect.rawValue else {
            throw GatewayProtocolError.unexpectedFrameType(
                expected: UdpFrameType.connect.rawValue, actual: bytes[1])
        }
        guard bytes[bytes.count - 1] == 0 else {
            throw GatewayProtocolError.malformedFrame("connect name is not NUL terminated")
        }
        let nameBytes = bytes[14..<(bytes.count - 1)]
        guard !nameBytes.isEmpty, !nameBytes.contains(0),
              let name = String(bytes: nameBytes, encoding: .ascii) else {
            throw GatewayProtocolError.invalidASCII
        }

        var reader = PacketReader(Data(bytes[2..<14]))
        protocolVersion = Int32(bitPattern: try GatewayWire.readBE32(&reader))
        connectCode = Int32(bitPattern: try GatewayWire.readBE32(&reader))
        maxRawPacketSize = Int32(bitPattern: try GatewayWire.readBE32(&reader))
        protocolName = name
    }
}

/// `UdpConnection.cs` confirm packet: 17 mandatory bytes plus an optional
/// big-endian Int32 protocol version at offset 17. The live public gateway
/// sends all 21 bytes.
struct GatewayConfirmPacket: Equatable {
    var connectCode: Int32
    var encryptCode: Int32
    var crcBytes: UInt8
    var encryptMethod1: UInt8
    var encryptMethod2: UInt8
    var maxRawPacketSize: Int32
    var protocolVersion: Int32?

    func encoded() -> Data {
        var data = Data([0x00, UdpFrameType.confirm.rawValue])
        GatewayWire.appendBE32(UInt32(bitPattern: connectCode), to: &data)
        GatewayWire.appendBE32(UInt32(bitPattern: encryptCode), to: &data)
        data.append(crcBytes)
        data.append(encryptMethod1)
        data.append(encryptMethod2)
        GatewayWire.appendBE32(UInt32(bitPattern: maxRawPacketSize), to: &data)
        GatewayWire.appendBE32(UInt32(bitPattern: protocolVersion ?? GatewayConnectPacket.protocolVersion), to: &data)
        return data
    }

    init(connectCode: Int32,
         encryptCode: Int32,
         crcBytes: UInt8 = 2,
         encryptMethod1: UInt8 = 0,
         encryptMethod2: UInt8 = 0,
         maxRawPacketSize: Int32 = 0x2000,
         protocolVersion: Int32? = GatewayConnectPacket.protocolVersion) {
        self.connectCode = connectCode
        self.encryptCode = encryptCode
        self.crcBytes = crcBytes
        self.encryptMethod1 = encryptMethod1
        self.encryptMethod2 = encryptMethod2
        self.maxRawPacketSize = maxRawPacketSize
        self.protocolVersion = protocolVersion
    }

    init(data: Data) throws {
        let bytes = Array(data)
        guard bytes.count >= 17 else {
            throw GatewayProtocolError.frameTooShort(expected: 17, available: bytes.count)
        }
        guard bytes[0] == 0x00 else { throw GatewayProtocolError.invalidFrameMarker(bytes[0]) }
        guard bytes[1] == UdpFrameType.confirm.rawValue else {
            throw GatewayProtocolError.unexpectedFrameType(
                expected: UdpFrameType.confirm.rawValue, actual: bytes[1])
        }
        // `UdpConnection.cs` reads the optional version whenever any bytes
        // remain after the mandatory 17. A partial Int32 is malformed; trailing
        // bytes after a complete version are ignored.
        if bytes.count > 17 && bytes.count < 21 {
            throw GatewayProtocolError.frameTooShort(expected: 21, available: bytes.count)
        }

        var reader = PacketReader(Data(bytes[2..<17]))
        connectCode = Int32(bitPattern: try GatewayWire.readBE32(&reader))
        encryptCode = Int32(bitPattern: try GatewayWire.readBE32(&reader))
        crcBytes = try reader.readUInt8()
        encryptMethod1 = try reader.readUInt8()
        encryptMethod2 = try reader.readUInt8()
        maxRawPacketSize = Int32(bitPattern: try GatewayWire.readBE32(&reader))
        if bytes.count >= 21 {
            var versionReader = PacketReader(Data(bytes[17..<21]))
            protocolVersion = Int32(bitPattern: try GatewayWire.readBE32(&versionReader))
        } else {
            protocolVersion = nil
        }
    }
}

// MARK: - Physical frame and application wrapper

/// A reliable gateway frame. `encryptCode` is supplied by the caller because
/// it is negotiated in the UDP confirm packet.
struct GatewayFrame: Equatable {
    var header: LoginFrameHeader
    var compressionEnabled: Bool
    var payload: Data

    init(reliableID: UInt16,
         type: UdpFrameType = .reliable1,
         compressionEnabled: Bool = true,
         payload: Data) {
        header = LoginFrameHeader(type: type, reliableID: reliableID)
        self.compressionEnabled = compressionEnabled
        self.payload = payload
    }

    init(header: LoginFrameHeader, compressionEnabled: Bool = true, payload: Data) {
        self.header = header
        self.compressionEnabled = compressionEnabled
        self.payload = payload
    }
}

enum GatewayFrameCodec {
    /// `PhysicalSend` preserves the two-byte internal header and runs
    /// `EncryptUserSupplied` on everything after it. `GatewayConnection` puts
    /// its 0/1 flag before the reliable id, so the wire layout is
    /// `0x00, type, flag, id_hi, id_lo, payload, CRC`. We always emit raw (0).
    static func encode(_ frame: GatewayFrame, encryptCode: UInt32) -> Data {
        UdpLibrary.encodeReliable(
            type: frame.header.type.rawValue,
            reliableID: frame.header.reliableID,
            encryptCode: encryptCode,
            userSuppliedCompression: frame.compressionEnabled,
            payload: frame.payload
        )
    }

    static func decode(_ data: Data, encryptCode: UInt32, compressionEnabled: Bool = true) throws -> GatewayFrame {
        let cooked: Data
        do {
            cooked = try UdpLibrary.cook(
                data,
                encryptCode: encryptCode,
                userSuppliedCompression: compressionEnabled
            )
        } catch let error as UdpLibraryError {
            throw map(error)
        }

        var state = UdpLibraryReassemblyState()
        let packets = UdpLibrary.parse(cooked, state: &state)
        guard let first = packets.first else {
            throw GatewayProtocolError.malformedFrame("empty cooked packet")
        }
        guard case .reliable(let type, let reliableID, let body, let applications) = first else {
            throw GatewayProtocolError.malformedFrame("not a reliable gateway frame")
        }
        guard let frameType = UdpFrameType(rawValue: type), frameType.isReliableApplicationFrame else {
            throw GatewayProtocolError.unexpectedFrameType(
                expected: UdpFrameType.reliable1.rawValue, actual: type
            )
        }
        // `body` still contains the zero-escape byte when the application
        // payload starts with 0. The parsed applications have it stripped,
        // matching C# ProcessCookedPacket -> CallbackRoutePacket.
        let payload = applications.first ?? body
        return GatewayFrame(
            header: LoginFrameHeader(type: frameType, reliableID: reliableID),
            compressionEnabled: compressionEnabled,
            payload: payload
        )
    }

    private static func map(_ error: UdpLibraryError) -> GatewayProtocolError {
        switch error {
        case .truncated:
            return .physicalFrame(.frameTooShort(expected: 0, available: 0))
        case .badMarker(let value):
            return .physicalFrame(.invalidFrameMarker(value))
        case .crcMismatch(let expected, let actual):
            return .physicalFrame(.crcMismatch(expected: expected, actual: actual))
        case .unsupportedCompression(let flag):
            return .unsupportedCompression(flag)
        case .compressionUnavailable:
            return .malformedFrame("zlib compression is unavailable")
        case .decompressionFailed:
            return .malformedFrame("failed to inflate gateway frame")
        case .invalidZlibHeader:
            return .malformedFrame("invalid zlib header in gateway frame")
        case .zlibChecksumMismatch(let expected, let actual):
            return .malformedFrame(
                "zlib checksum mismatch in gateway frame: expected 0x\(String(expected, radix: 16)), got 0x\(String(actual, radix: 16))"
            )
        case .crcMismatch32(let expected, let actual, let width):
            return .malformedFrame(
                "CRC-\(width) mismatch: expected 0x\(String(expected, radix: 16)), got 0x\(String(actual, radix: 16))"
            )
        case .fragmentTooLarge, .fragmentOverflow:
            return .malformedFrame("invalid reliable fragment")
        case .unsupportedEncryptMethod(let method):
            return .malformedFrame("unsupported encrypt method \(method)")
        case .unsupportedCRCWidth(let width):
            return .malformedFrame("unsupported CRC width \(width)")
        }
    }
}

/// `Sanctuary.Core.IO.PacketUtils`: secure packets carry flag 1 plus the
/// little-endian magic; unencrypted packets have no trailer at all.
enum GatewayPayloadCodec {
    static func wrapSecure(_ packet: Data, cipher: inout GatewayCipher, nonceSuffix: Data? = nil) throws -> Data {
        var data = try cipher.encrypt(packet, nonceSuffix: nonceSuffix)
        data.append(1)
        for shift in stride(from: 0, to: 32, by: 8) {
            data.append(UInt8(truncatingIfNeeded: PacketConstants.magic >> shift))
        }
        return data
    }

    static func unwrap(_ data: Data, cipher: inout GatewayCipher?) throws -> Data {
        let bytes = Array(data)
        guard bytes.count >= 5 else { return Data(data) }

        var magic: UInt32 = 0
        for (index, byte) in bytes.suffix(4).enumerated() {
            magic |= UInt32(byte) << (8 * index)
        }
        guard magic == PacketConstants.magic else { return Data(data) }

        let flag = bytes[bytes.count - 5]
        guard flag == 1 else { throw GatewayProtocolError.invalidEncryptionFlag(flag) }
        guard var active = cipher else { throw GatewayProtocolError.cipherNotInitialized }

        let plaintext = try active.decrypt(Data(bytes[0..<(bytes.count - 5)]))
        cipher = active
        return plaintext
    }
}

// MARK: - Gateway application packets

enum GatewayOpcode: Int16 {
    case login = 1
    case loginReply = 2
    case tunneled = 5
    case tunneledWorld = 6
}

protocol GatewayMessage {
    static var opcode: GatewayOpcode { get }
    init(fieldsFrom reader: inout PacketReader) throws
    func appendFields(to writer: inout PacketWriter)
}

enum GatewayPacketCodec {
    static func encode<Message: GatewayMessage>(_ message: Message) -> Data {
        var writer = PacketWriter()
        GatewayWire.appendInt16(Message.opcode.rawValue, to: &writer.data)
        message.appendFields(to: &writer)
        return writer.data
    }

    static func decode<Message: GatewayMessage>(_ type: Message.Type, from data: Data) throws -> Message {
        var reader = PacketReader(Data(data))
        let raw = try GatewayWire.readInt16(&reader)
        guard raw == Message.opcode.rawValue else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Message.opcode.rawValue, actual: raw)
        }
        let message: Message
        do {
            message = try Message(fieldsFrom: &reader)
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
        return message
    }

    static func opcode(from data: Data) throws -> GatewayOpcode {
        var reader = PacketReader(Data(data))
        let raw: Int16
        do {
            raw = try GatewayWire.readInt16(&reader)
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard let opcode = GatewayOpcode(rawValue: raw) else {
            throw GatewayProtocolError.unsupportedOpcode(raw)
        }
        return opcode
    }
}

/// `Sanctuary.Packet.ClientGateway.PacketLogin` (opcode 1).
struct GatewaySessionHello: GatewayMessage, Equatable {
    static let opcode: GatewayOpcode = .login

    var ticket: String
    var guid: UInt64
    var version: String
    var unknown: String

    init(ticket: String, guid: UInt64, version: String, unknown: String = "") {
        self.ticket = ticket
        self.guid = guid
        self.version = version
        self.unknown = unknown
    }

    init(fieldsFrom reader: inout PacketReader) throws {
        ticket = try reader.readString()
        guid = try reader.readUInt64()
        version = try reader.readString()
        unknown = try reader.readString()
    }

    func appendFields(to writer: inout PacketWriter) {
        writer.writeString(ticket)
        writer.writeUInt64(guid)
        writer.writeString(version)
        writer.writeString(unknown)
    }
}

/// `Sanctuary.Packet.ClientGateway.PacketLoginReply` (opcode 2).
struct GatewayLoginReply: GatewayMessage, Equatable {
    static let opcode: GatewayOpcode = .loginReply

    var success: Bool

    init(success: Bool) { self.success = success }

    init(fieldsFrom reader: inout PacketReader) throws {
        success = try reader.readBool()
    }

    func appendFields(to writer: inout PacketWriter) {
        writer.writeBool(success)
    }
}

/// `Sanctuary.Packet.ClientGateway.PacketTunneledClientPacket` (opcode 5).
struct GatewayTunneledPacket: GatewayMessage, Equatable {
    static let opcode: GatewayOpcode = .tunneled

    var reliable: Bool
    var payload: Data

    init(reliable: Bool = true, payload: Data) {
        self.reliable = reliable
        self.payload = payload
    }

    init(fieldsFrom reader: inout PacketReader) throws {
        reliable = try reader.readBool()
        payload = try reader.readData()
    }

    func appendFields(to writer: inout PacketWriter) {
        writer.writeBool(reliable)
        writer.writeData(payload)
    }
}

/// `Sanctuary.Packet.ClientGateway.PacketTunneledClientWorldPacket` (opcode 6).
struct GatewayTunneledWorldPacket: GatewayMessage, Equatable {
    static let opcode: GatewayOpcode = .tunneledWorld

    var reliable: Bool
    var payload: Data

    init(reliable: Bool = true, payload: Data) {
        self.reliable = reliable
        self.payload = payload
    }

    init(fieldsFrom reader: inout PacketReader) throws {
        reliable = try reader.readBool()
        payload = try reader.readData()
    }

    func appendFields(to writer: inout PacketWriter) {
        writer.writeBool(reliable)
        writer.writeData(payload)
    }
}

// MARK: - Gateway <-> Login packets (byte opcodes)

enum GatewayInternalOpcode: UInt8 {
    case loginReply = 101
    case characterLogin = 102
    case characterLogout = 103
    case characterReleaseRequest = 104
    case characterReleaseReply = 105
}

protocol GatewayInternalMessage {
    static var opcode: GatewayInternalOpcode { get }
    init(fieldsFrom reader: inout PacketReader) throws
    func appendFields(to writer: inout PacketWriter)
}

enum GatewayInternalCodec {
    static func encode<Message: GatewayInternalMessage>(_ message: Message) -> Data {
        var writer = PacketWriter()
        writer.writeUInt8(Message.opcode.rawValue)
        message.appendFields(to: &writer)
        return writer.data
    }

    static func decode<Message: GatewayInternalMessage>(_ type: Message.Type, from data: Data) throws -> Message {
        var reader = PacketReader(Data(data))
        let raw = try reader.readUInt8()
        guard raw == Message.opcode.rawValue else {
            throw GatewayProtocolError.unexpectedInternalOpcode(
                expected: Message.opcode.rawValue, actual: raw)
        }
        let message: Message
        do {
            message = try Message(fieldsFrom: &reader)
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
        return message
    }

    static func opcode(from data: Data) throws -> GatewayInternalOpcode {
        var reader = PacketReader(Data(data))
        let raw = try reader.readUInt8()
        guard let opcode = GatewayInternalOpcode(rawValue: raw) else {
            throw GatewayProtocolError.unsupportedInternalOpcode(raw)
        }
        return opcode
    }
}

/// `Sanctuary.Packet.Custom.GatewayLoginReply` (opcode 101).
struct GatewayInternalLoginReply: GatewayInternalMessage, Equatable {
    static let opcode: GatewayInternalOpcode = .loginReply

    var success: Bool

    init(success: Bool) { self.success = success }

    init(fieldsFrom reader: inout PacketReader) throws {
        success = try reader.readBool()
    }

    func appendFields(to writer: inout PacketWriter) {
        writer.writeBool(success)
    }
}

/// `Sanctuary.Packet.Custom.GatewayCharacterLogin` (opcode 102).
/// `id` is the database character id; `session` is the gateway login session.
struct GatewayCharacterLogin: GatewayInternalMessage, Equatable {
    static let opcode: GatewayInternalOpcode = .characterLogin

    var id: UInt64
    var session: UInt64

    init(id: UInt64, session: UInt64) {
        self.id = id
        self.session = session
    }

    init(fieldsFrom reader: inout PacketReader) throws {
        id = try reader.readUInt64()
        session = try reader.readUInt64()
    }

    func appendFields(to writer: inout PacketWriter) {
        writer.writeUInt64(id)
        writer.writeUInt64(session)
    }
}

/// `Sanctuary.Packet.Custom.GatewayCharacterLogout` (opcode 103).
struct GatewayCharacterLogout: GatewayInternalMessage, Equatable {
    static let opcode: GatewayInternalOpcode = .characterLogout

    var id: UInt64
    var session: UInt64

    init(id: UInt64, session: UInt64) {
        self.id = id
        self.session = session
    }

    init(fieldsFrom reader: inout PacketReader) throws {
        id = try reader.readUInt64()
        session = try reader.readUInt64()
    }

    func appendFields(to writer: inout PacketWriter) {
        writer.writeUInt64(id)
        writer.writeUInt64(session)
    }
}

/// `Sanctuary.Packet.Custom.GatewayCharacterReleaseRequest` (opcode 104).
struct GatewayCharacterReleaseRequest: GatewayInternalMessage, Equatable {
    static let opcode: GatewayInternalOpcode = .characterReleaseRequest

    var requestID: UInt32
    var id: UInt64
    var idleThresholdMilliseconds: UInt32

    init(requestID: UInt32, id: UInt64, idleThresholdMilliseconds: UInt32) {
        self.requestID = requestID
        self.id = id
        self.idleThresholdMilliseconds = idleThresholdMilliseconds
    }

    init(fieldsFrom reader: inout PacketReader) throws {
        requestID = try reader.readUInt32()
        id = try reader.readUInt64()
        idleThresholdMilliseconds = try reader.readUInt32()
    }

    func appendFields(to writer: inout PacketWriter) {
        writer.writeUInt32(requestID)
        writer.writeUInt64(id)
        writer.writeUInt32(idleThresholdMilliseconds)
    }
}

/// `Sanctuary.Packet.Custom.GatewayCharacterReleaseReply` (opcode 105).
struct GatewayCharacterReleaseReply: GatewayInternalMessage, Equatable {
    static let opcode: GatewayInternalOpcode = .characterReleaseReply

    var requestID: UInt32
    var released: Bool

    init(requestID: UInt32, released: Bool) {
        self.requestID = requestID
        self.released = released
    }

    init(fieldsFrom reader: inout PacketReader) throws {
        requestID = try reader.readUInt32()
        released = try reader.readBool()
    }

    func appendFields(to writer: inout PacketWriter) {
        writer.writeUInt32(requestID)
        writer.writeBool(released)
    }
}

// MARK: - World packets carried by tunneled opcodes

struct GatewayVector3: Equatable {
    var x: Float
    var y: Float
    var z: Float

    init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    func append(to writer: inout PacketWriter) {
        writer.writeFloat(x)
        writer.writeFloat(y)
        writer.writeFloat(z)
    }

    init(reader: inout PacketReader) throws {
        x = try reader.readFloat()
        y = try reader.readFloat()
        z = try reader.readFloat()
    }
}

struct GatewayVector4: Equatable {
    var x: Float
    var y: Float
    var z: Float
    var w: Float

    init(x: Float, y: Float, z: Float, w: Float) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    func append(to writer: inout PacketWriter) {
        writer.writeFloat(x)
        writer.writeFloat(y)
        writer.writeFloat(z)
        writer.writeFloat(w)
    }

    init(reader: inout PacketReader) throws {
        x = try reader.readFloat()
        y = try reader.readFloat()
        z = try reader.readFloat()
        w = try reader.readFloat()
    }
}

/// `Sanctuary.Packet.PlayerUpdatePacketUpdatePosition` (opcode 125).
/// Position and rotation are 3-float "limited" vectors (PacketWriter.Write
/// with `limited: true`).
struct WorldPositionUpdate: Equatable {
    static let opcode: Int16 = 125

    var guid: UInt64
    var position: GatewayVector3
    var rotation: GatewayVector3
    var state: UInt8
    var teleportSequence: UInt8

    init(guid: UInt64,
         position: GatewayVector3,
         rotation: GatewayVector3,
         state: UInt8,
         teleportSequence: UInt8) {
        self.guid = guid
        self.position = position
        self.rotation = rotation
        self.state = state
        self.teleportSequence = teleportSequence
    }

    func encoded() -> Data {
        var writer = PacketWriter()
        GatewayWire.appendInt16(Self.opcode, to: &writer.data)
        writer.writeUInt64(guid)
        position.append(to: &writer)
        rotation.append(to: &writer)
        writer.writeUInt8(state)
        writer.writeUInt8(teleportSequence)
        return writer.data
    }

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        do {
            guid = try reader.readUInt64()
            position = try GatewayVector3(reader: &reader)
            rotation = try GatewayVector3(reader: &reader)
            state = try reader.readUInt8()
            teleportSequence = try reader.readUInt8()
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `Sanctuary.Packet.PlayerUpdatePacketJump` (opcode 164). The server accepts
/// this companion to a position update while a jump/vertical move is predicted.
struct GatewayJumpUpdate: Equatable {
    static let opcode: Int16 = 164

    var guid: UInt64
    var position: GatewayVector3
    var rotation: GatewayVector3
    var state: UInt8
    var teleportSequence: UInt8
    var verticalVelocity: Float

    func encoded() -> Data {
        var writer = PacketWriter()
        GatewayWire.appendInt16(Self.opcode, to: &writer.data)
        writer.writeUInt64(guid)
        position.append(to: &writer)
        rotation.append(to: &writer)
        writer.writeUInt8(state)
        writer.writeUInt8(teleportSequence)
        writer.writeFloat(verticalVelocity)
        return writer.data
    }
}

/// `Sanctuary.Packet.PlayerUpdatePacketCameraUpdate` (opcode 126). Sanctuary
/// parses it and currently ignores the values, but the original client sends it
/// with movement updates.
struct GatewayCameraUpdate: Equatable {
    static let opcode: Int16 = 126

    var position: GatewayVector3
    var rotation: GatewayVector3

    func encoded() -> Data {
        var writer = PacketWriter()
        GatewayWire.appendInt16(Self.opcode, to: &writer.data)
        position.append(to: &writer)
        rotation.append(to: &writer)
        return writer.data
    }
}

/// `Sanctuary.Packet.BasePlayerUpdatePacket` (35) entity spawns.
///
/// Only the fields needed to place a packet-backed marker are decoded: the
/// remainder of these large spawn packets is deliberately left unread. C# source:
/// `BasePlayerUpdatePacket/PlayerUpdatePacketAddPc.cs` (sub 1) and
/// `PlayerUpdatePacketAddNpc.cs` (sub 2). Both write a full four-float Vector4
/// position followed by a four-float Quaternion rotation.
struct GatewayEntityAddition: Equatable {
    static let opcode: Int16 = 35

    var guid: UInt64
    var subOpcode: Int16
    var name: String
    var modelID: Int32
    var position: GatewayVector4
    var rotation: GatewayVector4

    var isNPC: Bool { subOpcode == 2 }

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        do {
            let opcode = try GatewayWire.readInt16(&reader)
            guard opcode == Self.opcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
            }
            subOpcode = try GatewayWire.readInt16(&reader)
            guard subOpcode == 1 || subOpcode == 2 else {
                throw GatewayProtocolError.malformedFrame("unknown player-update sub-opcode \(subOpcode)")
            }

            guid = try reader.readUInt64()
            if subOpcode == 1 {
                let name = try GatewayName(reader: &reader)
                self.name = [name.firstName, name.lastName].filter { !$0.isEmpty }.joined(separator: " ")
                modelID = try reader.readInt32()
                _ = try reader.readInt32() // chat bubble foreground
                _ = try reader.readInt32() // chat bubble background
                _ = try reader.readInt32() // chat bubble size
            } else {
                let nameID = try reader.readInt32()
                modelID = try reader.readInt32()
                _ = try reader.readBool()
                name = "NPC \(nameID)"
                _ = try reader.readInt32() // chat bubble foreground
                _ = try reader.readInt32() // chat bubble background
                _ = try reader.readInt32() // chat bubble size
                _ = try reader.readFloat() // scale
            }
            position = try GatewayVector4(reader: &reader)
            rotation = try GatewayVector4(reader: &reader)
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
    }
}

/// `Sanctuary.Packet.Common.CharacterAttachmentData`, used by the equipment
/// packets below. All three strings use the standard Int32 byte-count prefix.
struct GatewayAttachment: Equatable, Sendable {
    var modelName: String
    var textureAlias: String
    var tintAlias: String
    var tintID: Int32
    var compositeEffectID: Int32
    var slot: Int32

    init(
        modelName: String,
        textureAlias: String,
        tintAlias: String,
        tintID: Int32,
        compositeEffectID: Int32,
        slot: Int32
    ) {
        self.modelName = modelName
        self.textureAlias = textureAlias
        self.tintAlias = tintAlias
        self.tintID = tintID
        self.compositeEffectID = compositeEffectID
        self.slot = slot
    }

    init(reader: inout PacketReader) throws {
        modelName = try reader.readString()
        textureAlias = try reader.readString()
        tintAlias = try reader.readString()
        tintID = try reader.readInt32()
        compositeEffectID = try reader.readInt32()
        slot = try reader.readInt32()
    }
}

/// `BasePlayerUpdatePacket` sub 6 (`PlayerUpdatePacketEquipItemChange`).
struct GatewayEquipItemChange: Equatable, Sendable {
    static let opcode: Int16 = 35
    static let subOpcode: Int16 = 6

    var guid: UInt64
    var id: Int32
    var attachment: GatewayAttachment
    var profileID: Int32
    var itemClassID: Int32
    var wieldType: Int32

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        do {
            let opcode = try GatewayWire.readInt16(&reader)
            guard opcode == Self.opcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
            }
            let sub = try GatewayWire.readInt16(&reader)
            guard sub == Self.subOpcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.subOpcode, actual: sub)
            }
            guid = try reader.readUInt64()
            id = try reader.readInt32()
            attachment = try GatewayAttachment(reader: &reader)
            profileID = try reader.readInt32()
            itemClassID = try reader.readInt32()
            wieldType = try reader.readInt32()
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BasePlayerUpdatePacket` sub 7 (`PlayerUpdatePacketEquippedItemsChange`).
struct GatewayEquippedItemsChange: Equatable, Sendable {
    static let opcode: Int16 = 35
    static let subOpcode: Int16 = 7

    var guid: UInt64
    var attachments: [GatewayAttachment]
    var unknown: Int32

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        do {
            let opcode = try GatewayWire.readInt16(&reader)
            guard opcode == Self.opcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
            }
            let sub = try GatewayWire.readInt16(&reader)
            guard sub == Self.subOpcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.subOpcode, actual: sub)
            }
            guid = try reader.readUInt64()
            let count = try reader.readInt32()
            guard count >= 0, count <= 1_024 else {
                throw GatewayProtocolError.malformedFrame("implausible attachment count \(count)")
            }
            var decoded: [GatewayAttachment] = []
            decoded.reserveCapacity(Int(count))
            for _ in 0..<Int(count) {
                decoded.append(try GatewayAttachment(reader: &reader))
            }
            attachments = decoded
            unknown = try reader.readInt32()
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BasePlayerUpdatePacket` sub 14. The C# writer emits the appearance ID
/// before the GUID, unlike most player-update packets.
struct GatewayTemporaryAppearance: Equatable, Sendable {
    static let opcode: Int16 = 35
    static let subOpcode: Int16 = 14

    var temporaryAppearance: Int32
    var guid: UInt64

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        do {
            let opcode = try GatewayWire.readInt16(&reader)
            guard opcode == Self.opcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
            }
            let sub = try GatewayWire.readInt16(&reader)
            guard sub == Self.subOpcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.subOpcode, actual: sub)
            }
            temporaryAppearance = try reader.readInt32()
            guid = try reader.readUInt64()
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BasePlayerUpdatePacket` sub 15.
struct GatewayRemoveTemporaryAppearance: Equatable, Sendable {
    static let opcode: Int16 = 35
    static let subOpcode: Int16 = 15

    var guid: UInt64
    var unused: Int32

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        do {
            let opcode = try GatewayWire.readInt16(&reader)
            guard opcode == Self.opcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
            }
            let sub = try GatewayWire.readInt16(&reader)
            guard sub == Self.subOpcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.subOpcode, actual: sub)
            }
            guid = try reader.readUInt64()
            unused = try reader.readInt32()
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BasePlayerUpdatePacket` sub 31 (weapon-flair slot override).
struct GatewaySlotCompositeEffectOverride: Equatable, Sendable {
    static let opcode: Int16 = 35
    static let subOpcode: Int16 = 31

    var guid: UInt64
    var slot: Int32
    var compositeEffect: Int32

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        do {
            let opcode = try GatewayWire.readInt16(&reader)
            guard opcode == Self.opcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
            }
            let sub = try GatewayWire.readInt16(&reader)
            guard sub == Self.subOpcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.subOpcode, actual: sub)
            }
            guid = try reader.readUInt64()
            slot = try reader.readInt32()
            compositeEffect = try reader.readInt32()
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BasePlayerUpdatePacket` sub 61 (active wield stance).
struct GatewayActiveWieldType: Equatable, Sendable {
    static let opcode: Int16 = 35
    static let subOpcode: Int16 = 61

    var guid: UInt64
    var wieldType: Int32

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        do {
            let opcode = try GatewayWire.readInt16(&reader)
            guard opcode == Self.opcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
            }
            let sub = try GatewayWire.readInt16(&reader)
            guard sub == Self.subOpcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.subOpcode, actual: sub)
            }
            guid = try reader.readUInt64()
            wieldType = try reader.readInt32()
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `Sanctuary.Packet.PacketClientBeginZoning` (opcode 31). The server sends
/// this before a zone change; `teleportSequence` must be echoed by movement.
struct GatewayClientBeginZoning: Equatable, Sendable {
    static let opcode: Int16 = 31

    var name: String
    var type: Int32
    var position: GatewayVector4
    var rotation: GatewayVector4
    var sky: String
    var tutorial: Bool
    var teleportSequence: UInt8
    var id: Int32
    var updateRadius: Float
    var geometryID: Int32
    var overrideUpdateRadius: Bool
    var waitForZoneReadyPacket: Bool

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        do {
            let opcode = try GatewayWire.readInt16(&reader)
            guard opcode == Self.opcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
            }
            name = try reader.readString()
            type = try reader.readInt32()
            position = try GatewayVector4(reader: &reader)
            rotation = try GatewayVector4(reader: &reader)
            sky = try reader.readString()
            tutorial = try reader.readBool()
            teleportSequence = try reader.readUInt8()
            id = try reader.readInt32()
            updateRadius = try reader.readFloat()
            geometryID = try reader.readInt32()
            overrideUpdateRadius = try reader.readBool()
            waitForZoneReadyPacket = try reader.readBool()
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `BaseClientUpdatePacket` sub 12 (`ClientUpdatePacketUpdateLocation`).
struct GatewayUpdateLocation: Equatable, Sendable {
    static let opcode: Int16 = 38
    static let subOpcode: Int16 = 12

    var position: GatewayVector4
    var rotation: GatewayVector4
    var teleport: Bool
    var teleportSequence: UInt8

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        do {
            let opcode = try GatewayWire.readInt16(&reader)
            guard opcode == Self.opcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
            }
            let sub = try GatewayWire.readInt16(&reader)
            guard sub == Self.subOpcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.subOpcode, actual: sub)
            }
            position = try GatewayVector4(reader: &reader)
            rotation = try GatewayVector4(reader: &reader)
            teleport = try reader.readBool()
            teleportSequence = try reader.readUInt8()
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// The nested payload of `PacketSendSelfToClient` is a raw `ClientPcData` in
/// Sanctuary.Packet.Common. The fields through `Name` are decoded exactly so
/// the remote view can use server-provided identity and placement. The rest of
/// the record is retained verbatim rather than approximated.
struct ClientPcData: Equatable {
    var launchTicket: UInt64
    var guid: UInt64
    var model: Int32
    var head: String
    var hair: String
    var hairColor: Int32
    var eyeColor: Int32
    var skinTone: String
    var facePaint: String
    var modelCustomization: String
    var headID: Int32
    var hairID: Int32
    var skinToneID: Int32
    var facePaintID: Int32
    var modelCustomizationID: Int32
    var position: GatewayVector4
    var rotation: GatewayVector4
    var name: GatewayName
    var rawPayload: Data

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        do {
            launchTicket = try reader.readUInt64()
            guid = try reader.readUInt64()
            model = try reader.readInt32()
            head = try reader.readString()
            hair = try reader.readString()
            hairColor = try reader.readInt32()
            eyeColor = try reader.readInt32()
            skinTone = try reader.readString()
            facePaint = try reader.readString()
            modelCustomization = try reader.readString()
            headID = try reader.readInt32()
            hairID = try reader.readInt32()
            skinToneID = try reader.readInt32()
            facePaintID = try reader.readInt32()
            modelCustomizationID = try reader.readInt32()
            position = try GatewayVector4(reader: &reader)
            rotation = try GatewayVector4(reader: &reader)
            name = try GatewayName(reader: &reader)
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        rawPayload = data
    }
}

/// `Sanctuary.Packet.PacketSendSelfToClient` (opcode 12): an Int32-prefixed
/// nested world packet. The server uses this to deliver the authenticated
/// player's own spawn data through the tunnel.
struct GatewaySendSelf: Equatable {
    static let opcode: Int16 = 12

    var payload: Data
    var client: ClientPcData

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        do {
            let opcode = try GatewayWire.readInt16(&reader)
            guard opcode == Self.opcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
            }
            payload = try reader.readData()
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
        client = try ClientPcData(data: payload)
    }
}

/// `Sanctuary.Packet.PacketSendZoneDetails` (opcode 43).
struct GatewayZoneDetails: Equatable {
    static let opcode: Int16 = 43

    var name: String
    var type: Int32
    var tutorial: Bool
    var unknown2: Bool
    var sky: String
    var isInArena: Bool
    var id: Int32
    var geometryID: Int32
    var isInStartingSocialZone: Bool
    var unknown6: Bool

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        do {
            let opcode = try GatewayWire.readInt16(&reader)
            guard opcode == Self.opcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
            }
            name = try reader.readString()
            type = try reader.readInt32()
            tutorial = try reader.readBool()
            unknown2 = try reader.readBool()
            sky = try reader.readString()
            isInArena = try reader.readBool()
            id = try reader.readInt32()
            geometryID = try reader.readInt32()
            isInStartingSocialZone = try reader.readBool()
            unknown6 = try reader.readBool()
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `Sanctuary.Packet.PacketGameTimeSync` (opcode 52). The same packet is used
/// for the client request and the server reply; the handler ignores the request
/// values and answers with authoritative server time.
struct GatewayGameTimeSync: Equatable {
    static let opcode: Int16 = 52

    var time: Int64
    var serverRate: Int32
    var useClientTime: Bool

    init(time: Int64, serverRate: Int32, useClientTime: Bool) {
        self.time = time
        self.serverRate = serverRate
        self.useClientTime = useClientTime
    }

    func encoded() -> Data {
        var writer = PacketWriter()
        GatewayWire.appendInt16(Self.opcode, to: &writer.data)
        writer.writeInt64(time)
        writer.writeInt32(serverRate)
        writer.writeBool(useClientTime)
        return writer.data
    }

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        do {
            let opcode = try GatewayWire.readInt16(&reader)
            guard opcode == Self.opcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
            }
            time = try reader.readInt64()
            serverRate = try reader.readInt32()
            useClientTime = try reader.readBool()
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `Sanctuary.Packet.PacketInitializationParameters` (opcode 166). The C#
/// writer caps the UTF-8 byte count at 64 but still uses a length prefix.
struct GatewayInitializationParameters: Equatable {
    static let opcode: Int16 = 166

    var environment: String

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        do {
            let opcode = try GatewayWire.readInt16(&reader)
            guard opcode == Self.opcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
            }
            environment = try reader.readString()
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `Sanctuary.Packet.PacketClientGameSettings` (opcode 144).
struct GatewayClientGameSettings: Equatable {
    static let opcode: Int16 = 144

    var unknown: Int32
    var unknown2: Int32
    var powerHourEffectTag: Int32
    var unknown4: Bool
    var gameTimeScalar: Float

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        do {
            let opcode = try GatewayWire.readInt16(&reader)
            guard opcode == Self.opcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
            }
            unknown = try reader.readInt32()
            unknown2 = try reader.readInt32()
            powerHourEffectTag = try reader.readInt32()
            unknown4 = try reader.readBool()
            gameTimeScalar = try reader.readFloat()
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `Sanctuary.Packet.PacketZoneDoneSendingInitialData` (opcode 14).
struct GatewayZoneDoneSendingInitialData: Equatable {
    static let opcode: Int16 = 14

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `ClientUpdatePacketDoneSendingPreloadCharacters` (base 38, sub 26).
struct GatewayPreloadCharactersDone: Equatable {
    static let opcode: Int16 = 38
    static let subOpcode: Int16 = 26

    var preload: Bool

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        do {
            let opcode = try GatewayWire.readInt16(&reader)
            guard opcode == Self.opcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
            }
            let sub = try GatewayWire.readInt16(&reader)
            guard sub == Self.subOpcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.subOpcode, actual: sub)
            }
            preload = try reader.readBool()
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `EncounterOverworldCombatPacket` (base 41, sub 132).
struct GatewayOverworldCombat: Equatable {
    static let opcode: Int16 = 41
    static let subOpcode: Int16 = 132

    var inWorldCombat: Bool

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        do {
            let opcode = try GatewayWire.readInt16(&reader)
            guard opcode == Self.opcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
            }
            let sub = try GatewayWire.readInt16(&reader)
            guard sub == Self.subOpcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.subOpcode, actual: sub)
            }
            inWorldCombat = try reader.readBool()
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `PlayerUpdatePacketItemDefinitions` (base 35, sub 37). The payload is an
/// Int32-prefixed byte array whose contents are `ClientItemDefinition` records.
struct GatewayItemDefinitions: Equatable {
    static let opcode: Int16 = 35
    static let subOpcode: Int16 = 37

    var payload: Data

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        do {
            let opcode = try GatewayWire.readInt16(&reader)
            guard opcode == Self.opcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
            }
            let sub = try GatewayWire.readInt16(&reader)
            guard sub == Self.subOpcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.subOpcode, actual: sub)
            }
            payload = try reader.readData()
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `PlayerUpdatePacketRemovePlayer` (base 35, sub 3). Graceful removals carry
/// an extra sub-sub-opcode and animation fields.
struct GatewayEntityRemoval: Equatable {
    static let opcode: Int16 = 35
    static let subOpcode: Int16 = 3

    var subSubOpcode: Int16
    var guid: UInt64
    var graceful: Bool?
    var animate: Bool?
    var delay: Int32?
    var effectDelay: Int32?
    var compositeEffectID: Int32?
    var duration: Int32?

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        do {
            let opcode = try GatewayWire.readInt16(&reader)
            guard opcode == Self.opcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
            }
            let sub = try GatewayWire.readInt16(&reader)
            guard sub == Self.subOpcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.subOpcode, actual: sub)
            }
            subSubOpcode = try GatewayWire.readInt16(&reader)
            guid = try reader.readUInt64()
            if subSubOpcode == 1 {
                graceful = true
                animate = try reader.readBool()
                delay = try reader.readInt32()
                effectDelay = try reader.readInt32()
                compositeEffectID = try reader.readInt32()
                duration = try reader.readInt32()
            } else {
                graceful = false
            }
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `PlayerUpdatePacketUpdateCharacterState` (base 35, sub 20).
struct GatewayCharacterState: Equatable {
    static let opcode: Int16 = 35
    static let subOpcode: Int16 = 20

    var guid: UInt64
    var state: Int32

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        do {
            let opcode = try GatewayWire.readInt16(&reader)
            guard opcode == Self.opcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
            }
            let sub = try GatewayWire.readInt16(&reader)
            guard sub == Self.subOpcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.subOpcode, actual: sub)
            }
            guid = try reader.readUInt64()
            state = try reader.readInt32()
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `PlayerUpdatePacketUpdateScale` (base 35, sub 13).
struct GatewayScaleUpdate: Equatable {
    static let opcode: Int16 = 35
    static let subOpcode: Int16 = 13

    var guid: UInt64
    var scale: Float

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        do {
            let opcode = try GatewayWire.readInt16(&reader)
            guard opcode == Self.opcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
            }
            let sub = try GatewayWire.readInt16(&reader)
            guard sub == Self.subOpcode else {
                throw GatewayProtocolError.unexpectedOpcode(expected: Self.subOpcode, actual: sub)
            }
            guid = try reader.readUInt64()
            scale = try reader.readFloat()
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

/// `Sanctuary.Packet.Common.NameData`: three Int32 name ids then two strings.
struct GatewayName: Equatable {
    var firstNameID: Int32
    var lastNamePrefixID: Int32
    var lastNameSuffixID: Int32
    var firstName: String
    var lastName: String

    init(firstNameID: Int32,
         lastNamePrefixID: Int32,
         lastNameSuffixID: Int32,
         firstName: String,
         lastName: String) {
        self.firstNameID = firstNameID
        self.lastNamePrefixID = lastNamePrefixID
        self.lastNameSuffixID = lastNameSuffixID
        self.firstName = firstName
        self.lastName = lastName
    }

    func append(to writer: inout PacketWriter) {
        writer.writeInt32(firstNameID)
        writer.writeInt32(lastNamePrefixID)
        writer.writeInt32(lastNameSuffixID)
        writer.writeString(firstName)
        writer.writeString(lastName)
    }

    init(reader: inout PacketReader) throws {
        firstNameID = try reader.readInt32()
        lastNamePrefixID = try reader.readInt32()
        lastNameSuffixID = try reader.readInt32()
        firstName = try reader.readString()
        lastName = try reader.readString()
    }
}

/// `Sanctuary.Packet.BaseChatPacket` (15) / `PacketChat` (sub-opcode 1).
/// Channel values come from `Sanctuary.Packet.Common.Chat.ChatChannel`
/// (`short`): WorldArea == 8 adds a trailing AreaNameId.
struct GatewayChatMessage: Equatable {
    enum Channel: Int16, CaseIterable, Identifiable {
        case worldSay = 0
        case tell = 1
        case system = 2
        case whisper = 3
        case groupSay = 4
        case worldShout = 5
        case worldTrade = 6
        case worldLfg = 7
        case worldArea = 8
        case guildSay = 9
        case worldMembersOnly = 10

        var id: Int16 { rawValue }

        var displayName: String {
            switch self {
            case .worldSay: return "Say"
            case .tell: return "Tell"
            case .system: return "System"
            case .whisper: return "Whisper"
            case .groupSay: return "Group"
            case .worldShout: return "Shout"
            case .worldTrade: return "Trade"
            case .worldLfg: return "LFG"
            case .worldArea: return "Area"
            case .guildSay: return "Guild"
            case .worldMembersOnly: return "Members"
            }
        }
    }

    static let opcode: Int16 = 15
    static let subOpcode: Int16 = 1

    var channel: Channel
    var fromGUID: UInt64
    var toGUID: UInt64
    var fromName: GatewayName
    var toName: GatewayName
    var message: String
    var position: GatewayVector4
    var guildGUID: UInt64
    var languageID: Int32
    var areaNameID: Int32?

    init(channel: Channel,
         fromGUID: UInt64,
         toGUID: UInt64,
         fromName: GatewayName,
         toName: GatewayName,
         message: String,
         position: GatewayVector4,
         guildGUID: UInt64,
         languageID: Int32,
         areaNameID: Int32? = nil) {
        self.channel = channel
        self.fromGUID = fromGUID
        self.toGUID = toGUID
        self.fromName = fromName
        self.toName = toName
        self.message = message
        self.position = position
        self.guildGUID = guildGUID
        self.languageID = languageID
        self.areaNameID = areaNameID
    }

    func encoded() -> Data {
        var writer = PacketWriter()
        GatewayWire.appendInt16(Self.opcode, to: &writer.data)
        GatewayWire.appendInt16(Self.subOpcode, to: &writer.data)
        GatewayWire.appendInt16(channel.rawValue, to: &writer.data)
        writer.writeUInt64(fromGUID)
        writer.writeUInt64(toGUID)
        fromName.append(to: &writer)
        toName.append(to: &writer)
        writer.writeString(message)
        position.append(to: &writer)
        writer.writeUInt64(guildGUID)
        writer.writeInt32(languageID)
        if channel == .worldArea {
            writer.writeInt32(areaNameID ?? 0)
        }
        return writer.data
    }

    init(data: Data) throws {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        guard opcode == Self.opcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.opcode, actual: opcode)
        }
        let subOpcode = try GatewayWire.readInt16(&reader)
        guard subOpcode == Self.subOpcode else {
            throw GatewayProtocolError.unexpectedOpcode(expected: Self.subOpcode, actual: subOpcode)
        }
        do {
            let rawChannel = try GatewayWire.readInt16(&reader)
            guard let decodedChannel = Channel(rawValue: rawChannel) else {
                throw GatewayProtocolError.malformedFrame("unknown chat channel \(rawChannel)")
            }
            channel = decodedChannel
            fromGUID = try reader.readUInt64()
            toGUID = try reader.readUInt64()
            fromName = try GatewayName(reader: &reader)
            toName = try GatewayName(reader: &reader)
            message = try reader.readString()
            position = try GatewayVector4(reader: &reader)
            guildGUID = try reader.readUInt64()
            languageID = try reader.readInt32()
            areaNameID = channel == .worldArea ? try reader.readInt32() : nil
        } catch let error as ProtocolError {
            throw GatewayProtocolError.wire(error)
        }
        guard reader.isAtEnd else { throw GatewayProtocolError.trailingBytes(reader.remaining) }
    }
}

enum GatewayWorldPacket: Equatable {
    case positionUpdate(WorldPositionUpdate)
    case chat(GatewayChatMessage)
    case entityAdded(GatewayEntityAddition)
    case entityRemoved(GatewayEntityRemoval)
    case characterState(GatewayCharacterState)
    case scaleUpdate(GatewayScaleUpdate)
    case itemDefinitions(GatewayItemDefinitions)
    case sendSelf(GatewaySendSelf)
    case zoneDetails(GatewayZoneDetails)
    case initializationParameters(GatewayInitializationParameters)
    case clientGameSettings(GatewayClientGameSettings)
    case gameTimeSync(GatewayGameTimeSync)
    case zoneDoneSendingInitialData
    case preloadCharactersDone(GatewayPreloadCharactersDone)
    case overworldCombat(GatewayOverworldCombat)
    case equipItemChange(GatewayEquipItemChange)
    case equippedItemsChange(GatewayEquippedItemsChange)
    case temporaryAppearance(GatewayTemporaryAppearance)
    case removeTemporaryAppearance(GatewayRemoveTemporaryAppearance)
    case slotCompositeEffectOverride(GatewaySlotCompositeEffectOverride)
    case activeWieldType(GatewayActiveWieldType)
    case beginZoning(GatewayClientBeginZoning)
    case updateLocation(GatewayUpdateLocation)
    case unknown(Int16, Data)
}

enum GatewayWorldCodec {
    static func decodeAny(_ data: Data) throws -> GatewayWorldPacket {
        var reader = PacketReader(Data(data))
        let opcode = try GatewayWire.readInt16(&reader)
        switch opcode {
        case WorldPositionUpdate.opcode:
            return .positionUpdate(try WorldPositionUpdate(data: data))
        case GatewayChatMessage.opcode:
            let sub = try GatewayWire.readInt16(&reader)
            return sub == GatewayChatMessage.subOpcode
                ? .chat(try GatewayChatMessage(data: data))
                : .unknown(opcode, data)
        case GatewayEntityAddition.opcode:
            let sub = try GatewayWire.readInt16(&reader)
            switch sub {
            case 1, 2:
                return .entityAdded(try GatewayEntityAddition(data: data))
            case GatewayEntityRemoval.subOpcode:
                return .entityRemoved(try GatewayEntityRemoval(data: data))
            case GatewayCharacterState.subOpcode:
                return .characterState(try GatewayCharacterState(data: data))
            case GatewayScaleUpdate.subOpcode:
                return .scaleUpdate(try GatewayScaleUpdate(data: data))
            case GatewayItemDefinitions.subOpcode:
                return .itemDefinitions(try GatewayItemDefinitions(data: data))
            case GatewayEquipItemChange.subOpcode:
                return .equipItemChange(try GatewayEquipItemChange(data: data))
            case GatewayEquippedItemsChange.subOpcode:
                return .equippedItemsChange(try GatewayEquippedItemsChange(data: data))
            case GatewayTemporaryAppearance.subOpcode:
                return .temporaryAppearance(try GatewayTemporaryAppearance(data: data))
            case GatewayRemoveTemporaryAppearance.subOpcode:
                return .removeTemporaryAppearance(try GatewayRemoveTemporaryAppearance(data: data))
            case GatewaySlotCompositeEffectOverride.subOpcode:
                return .slotCompositeEffectOverride(try GatewaySlotCompositeEffectOverride(data: data))
            case GatewayActiveWieldType.subOpcode:
                return .activeWieldType(try GatewayActiveWieldType(data: data))
            default:
                return .unknown(opcode, data)
            }
        case GatewaySendSelf.opcode:
            return .sendSelf(try GatewaySendSelf(data: data))
        case GatewayZoneDetails.opcode:
            return .zoneDetails(try GatewayZoneDetails(data: data))
        case GatewayInitializationParameters.opcode:
            return .initializationParameters(try GatewayInitializationParameters(data: data))
        case GatewayClientGameSettings.opcode:
            return .clientGameSettings(try GatewayClientGameSettings(data: data))
        case GatewayGameTimeSync.opcode:
            return .gameTimeSync(try GatewayGameTimeSync(data: data))
        case GatewayZoneDoneSendingInitialData.opcode:
            return .zoneDoneSendingInitialData
        case GatewayClientBeginZoning.opcode:
            return .beginZoning(try GatewayClientBeginZoning(data: data))
        case 38:
            let sub = try GatewayWire.readInt16(&reader)
            switch sub {
            case GatewayPreloadCharactersDone.subOpcode:
                return .preloadCharactersDone(try GatewayPreloadCharactersDone(data: data))
            case GatewayUpdateLocation.subOpcode:
                return .updateLocation(try GatewayUpdateLocation(data: data))
            default:
                return .unknown(opcode, data)
            }
        case 41:
            let sub = try GatewayWire.readInt16(&reader)
            return sub == GatewayOverworldCombat.subOpcode
                ? .overworldCombat(try GatewayOverworldCombat(data: data))
                : .unknown(opcode, data)
        default:
            return .unknown(opcode, data)
        }
    }
}

/// Packet-backed view state. Every value here comes from a decoded gateway
/// world packet; it is deliberately empty until the server sends something.
struct GatewayWorldObservation: Equatable, Sendable {
    struct Position: Equatable, Identifiable, Sendable {
        let guid: UInt64
        var position: ZoneVector
        var rotation: ZoneVector
        var state: UInt8
        var teleportSequence: UInt8
        var receivedAt: Date

        var id: UInt64 { guid }
    }

    struct ChatMessage: Equatable, Identifiable, Sendable {
        let id: UInt64
        let channel: Int16
        let fromName: String
        let message: String
        let receivedAt: Date
    }

    var positions: [UInt64: Position] = [:]
    /// Names are only populated by decoded spawn or self packets. Position-only
    /// updates must never fabricate a name.
    var names: [UInt64: String] = [:]
    var chatMessages: [ChatMessage] = []
    var playerGUID: UInt64?
    var zoneName: String?
    var zoneID: Int32?
    var geometryID: Int32?
    var environment: String?
    var gameTime: Int64?
    var serverRate: Int32?
    var useClientTime: Bool?
    var powerHourEffectTag: Int32?
    var clientSettingsUnknown4: Bool?
    var gameTimeScalar: Float?
    var scales: [UInt64: Float] = [:]
    var equipment: [UInt64: [GatewayAttachment]] = [:]
    var temporaryAppearances: [UInt64: Int32] = [:]
    var compositeEffectOverrides: [UInt64: [Int32: Int32]] = [:]
    var activeWieldTypes: [UInt64: Int32] = [:]
    var teleportSequences: [UInt64: UInt8] = [:]
    var ownTeleportSequence: UInt8?
    var pendingZoneName: String?
    var pendingZoneID: Int32?
    var pendingZoneGeometryID: Int32?
    var inWorldCombat: Bool?
    var itemDefinitionCount: Int?
    var preloadCharactersDone = false
    var zoneDataComplete = false
    var lastEvent: String?

    private var nextChatID: UInt64 = 1

    static let empty = GatewayWorldObservation()

    var positionCount: Int { positions.count }
    var chatCount: Int { chatMessages.count }

    mutating func apply(_ packet: GatewayWorldPacket, now: Date = Date()) {
        switch packet {
        case .positionUpdate(let update):
            positions[update.guid] = Position(
                guid: update.guid,
                position: ZoneVector(
                    x: Double(update.position.x),
                    y: Double(update.position.y),
                    z: Double(update.position.z),
                    w: 0
                ),
                rotation: ZoneVector(
                    x: Double(update.rotation.x),
                    y: Double(update.rotation.y),
                    z: Double(update.rotation.z),
                    w: 0
                ),
                state: update.state,
                teleportSequence: update.teleportSequence,
                receivedAt: now
            )
            if update.teleportSequence != 0 { scales[update.guid] = nil }
            lastEvent = "Position update · GUID \(update.guid)"
        case .chat(let chat):
            let message = ChatMessage(
                id: nextChatID,
                channel: chat.channel.rawValue,
                fromName: Self.displayName(chat.fromName),
                message: chat.message,
                receivedAt: now
            )
            nextChatID = nextChatID &+ 1
            chatMessages.append(message)
            if chatMessages.count > 32 { chatMessages.removeFirst(chatMessages.count - 32) }
            lastEvent = "Chat · \(message.fromName)"
        case .entityAdded(let addition):
            names[addition.guid] = addition.name
            positions[addition.guid] = Position(
                guid: addition.guid,
                position: ZoneVector(
                    x: Double(addition.position.x),
                    y: Double(addition.position.y),
                    z: Double(addition.position.z),
                    w: Double(addition.position.w)
                ),
                rotation: ZoneVector(
                    x: Double(addition.rotation.x),
                    y: Double(addition.rotation.y),
                    z: Double(addition.rotation.z),
                    w: Double(addition.rotation.w)
                ),
                state: 0,
                teleportSequence: 0,
                receivedAt: now
            )
            lastEvent = "Spawn · \(addition.name)"
        case .entityRemoved(let removal):
            positions.removeValue(forKey: removal.guid)
            names.removeValue(forKey: removal.guid)
            scales.removeValue(forKey: removal.guid)
            lastEvent = "Remove · GUID \(removal.guid)"
        case .characterState(let state):
            if var position = positions[state.guid] {
                position.state = UInt8(truncatingIfNeeded: state.state)
                position.receivedAt = now
                positions[state.guid] = position
            }
            lastEvent = "State \(state.state) · GUID \(state.guid)"
        case .scaleUpdate(let scale):
            scales[scale.guid] = scale.scale
            lastEvent = "Scale \(scale.scale) · GUID \(scale.guid)"
        case .itemDefinitions(let definitions):
            var reader = PacketReader(definitions.payload)
            let count = (try? reader.readInt32()) ?? 0
            itemDefinitionCount = count >= 0 ? Int(count) : 0
            lastEvent = "Item definitions · \(itemDefinitionCount ?? 0)"
        case .sendSelf(let wrapped):
            let client = wrapped.client
            playerGUID = client.guid
            let name = Self.displayName(client.name)
            names[client.guid] = name
            positions[client.guid] = Position(
                guid: client.guid,
                position: ZoneVector(
                    x: Double(client.position.x),
                    y: Double(client.position.y),
                    z: Double(client.position.z),
                    w: Double(client.position.w)
                ),
                rotation: ZoneVector(
                    x: Double(client.rotation.x),
                    y: Double(client.rotation.y),
                    z: Double(client.rotation.z),
                    w: Double(client.rotation.w)
                ),
                state: 0,
                teleportSequence: 0,
                receivedAt: now
            )
            lastEvent = "Self · \(name)"
        case .zoneDetails(let zone):
            zoneName = zone.name
            zoneID = zone.id
            geometryID = zone.geometryID
            lastEvent = "Zone · \(zone.name)"
        case .initializationParameters(let parameters):
            environment = parameters.environment
            lastEvent = "Environment · \(parameters.environment)"
        case .clientGameSettings(let settings):
            powerHourEffectTag = settings.powerHourEffectTag
            gameTimeScalar = settings.gameTimeScalar
            clientSettingsUnknown4 = settings.unknown4
            lastEvent = "Game settings · scalar \(settings.gameTimeScalar)"
        case .gameTimeSync(let sync):
            gameTime = sync.time
            serverRate = sync.serverRate
            useClientTime = sync.useClientTime
            lastEvent = "Game time · \(sync.time)"
        case .zoneDoneSendingInitialData:
            zoneDataComplete = true
            lastEvent = "Zone initial data complete"
        case .preloadCharactersDone(let done):
            preloadCharactersDone = done.preload
            lastEvent = "Preload characters · \(done.preload)"
        case .overworldCombat(let combat):
            inWorldCombat = combat.inWorldCombat
            lastEvent = "World combat · \(combat.inWorldCombat)"
        case .equipItemChange(let change):
            var slots = equipment[change.guid] ?? []
            if let index = slots.firstIndex(where: { $0.slot == change.attachment.slot }) {
                if change.attachment.modelName.isEmpty {
                    slots.remove(at: index)
                } else {
                    slots[index] = change.attachment
                }
            } else if !change.attachment.modelName.isEmpty {
                slots.append(change.attachment)
            }
            equipment[change.guid] = slots
            lastEvent = "Equip \(change.id) · GUID \(change.guid)"
        case .equippedItemsChange(let change):
            equipment[change.guid] = change.attachments
            lastEvent = "Equipment · \(change.attachments.count) slots · GUID \(change.guid)"
        case .temporaryAppearance(let appearance):
            temporaryAppearances[appearance.guid] = appearance.temporaryAppearance
            lastEvent = "Appearance \(appearance.temporaryAppearance) · GUID \(appearance.guid)"
        case .removeTemporaryAppearance(let removal):
            temporaryAppearances.removeValue(forKey: removal.guid)
            lastEvent = "Appearance restored · GUID \(removal.guid)"
        case .slotCompositeEffectOverride(let override):
            var slots = compositeEffectOverrides[override.guid] ?? [:]
            if override.compositeEffect == 0 {
                slots.removeValue(forKey: override.slot)
            } else {
                slots[override.slot] = override.compositeEffect
            }
            compositeEffectOverrides[override.guid] = slots
            lastEvent = "Flair \(override.compositeEffect) · slot \(override.slot) · GUID \(override.guid)"
        case .activeWieldType(let wield):
            activeWieldTypes[wield.guid] = wield.wieldType
            lastEvent = "Wield \(wield.wieldType) · GUID \(wield.guid)"
        case .beginZoning(let zoning):
            pendingZoneName = zoning.name
            pendingZoneID = zoning.id
            pendingZoneGeometryID = zoning.geometryID
            ownTeleportSequence = zoning.teleportSequence
            if let guid = playerGUID {
                teleportSequences[guid] = zoning.teleportSequence
                scales[guid] = nil
                if var current = positions[guid] {
                    current.position = ZoneVector(
                        x: Double(zoning.position.x),
                        y: Double(zoning.position.y),
                        z: Double(zoning.position.z),
                        w: Double(zoning.position.w)
                    )
                    current.rotation = ZoneVector(
                        x: Double(zoning.rotation.x),
                        y: Double(zoning.rotation.y),
                        z: Double(zoning.rotation.z),
                        w: Double(zoning.rotation.w)
                    )
                    current.teleportSequence = zoning.teleportSequence
                    current.receivedAt = now
                    positions[guid] = current
                }
            }
            lastEvent = "Zoning · \(zoning.name) · seq \(zoning.teleportSequence)"
        case .updateLocation(let location):
            ownTeleportSequence = location.teleportSequence
            if let guid = playerGUID {
                teleportSequences[guid] = location.teleportSequence
                if location.teleport { scales[guid] = nil }
                if var current = positions[guid] {
                    current.position = ZoneVector(
                        x: Double(location.position.x),
                        y: Double(location.position.y),
                        z: Double(location.position.z),
                        w: Double(location.position.w)
                    )
                    current.rotation = ZoneVector(
                        x: Double(location.rotation.x),
                        y: Double(location.rotation.y),
                        z: Double(location.rotation.z),
                        w: Double(location.rotation.w)
                    )
                    current.teleportSequence = location.teleportSequence
                    current.receivedAt = now
                    positions[guid] = current
                }
            }
            lastEvent = "Location · seq \(location.teleportSequence) · teleport \(location.teleport)"
        case .unknown(let opcode, _):
            lastEvent = "Unparsed world opcode \(opcode)"
        }
    }

    private static func displayName(_ name: GatewayName) -> String {
        let parts = [name.firstName, name.lastName].filter { !$0.isEmpty }
        return parts.isEmpty ? "Unknown" : parts.joined(separator: " ")
    }
}

// MARK: - Typed events and session

enum GatewayPacket: Equatable {
    case login(GatewaySessionHello)
    case loginReply(GatewayLoginReply)
    case tunneled(GatewayTunneledPacket)
    case tunneledWorld(GatewayTunneledWorldPacket)
    case unknown(Int16, Data)
}

enum GatewaySessionState: Equatable {
    case ready
    case awaitingLoginReply(GatewaySessionHello)
    case authenticated
    case failed
}

enum GatewaySessionEvent: Equatable {
    case stateChanged(GatewaySessionState)
    case packet(GatewayPacket)
    case world(GatewayWorldPacket)
    case rejected(GatewayProtocolError)
}

/// Transport-agnostic gateway session. A transport feeds physical UDP frames
/// into `receive(frame:)` and sends the bytes returned by `beginLogin`/`send`.
struct GatewaySession {
    var state: GatewaySessionState = .ready
    let connectCode: Int32
    let encryptCode: UInt32
    let compressionEnabled: Bool

    private var cipher: GatewayCipher?
    private var outgoingReliableID: UInt16 = 0
    private var receivedReliableIDs: [UInt16] = []

    init(connectCode: Int32, encryptCode: UInt32, compressionEnabled: Bool = true) {
        self.connectCode = connectCode
        self.encryptCode = encryptCode
        self.compressionEnabled = compressionEnabled
    }

    /// Sanctuary initializes AES-CCM with `Encoding.ASCII.GetBytes(key)` where
    /// key is the 32-hex-character server ticket from the login reply.
    mutating func setCipher(ticket: String) throws {
        guard ticket.utf8.count == 32, ticket.utf8.allSatisfy({ $0 < 0x80 }) else {
            throw GatewayProtocolError.invalidTicketKey(ticket)
        }
        try setCipher(key: Data(ticket.utf8))
    }

    mutating func setCipher(key: Data) throws {
        cipher = try GatewayCipher(key: key)
    }

    /// The first application packet is sent unencrypted: Sanctuary initializes
    /// its cipher only after parsing PacketLogin.
    mutating func beginLogin(_ hello: GatewaySessionHello) throws -> Data {
        guard case .ready = state else {
            throw GatewayProtocolError.invalidState(expected: "ready", actual: "\(state)")
        }
        let frame = try makeFrame(packet: GatewayPacketCodec.encode(hello), secure: false)
        state = .awaitingLoginReply(hello)
        return frame
    }

    /// World/gameplay packets use the secure wrapper after a successful login.
    mutating func send(packet: Data, nonceSuffix: Data? = nil) throws -> Data {
        let body = try wrapPayload(packet, secure: true, nonceSuffix: nonceSuffix)
        return makeFrame(body: body, reliableID: allocateReliableID())
    }

    /// Wraps one logical application packet once. Callers that fragment at the
    /// UdpLibrary layer wrap here first, then encode each chunk with a
    /// transport-owned stamp so every fragment gets its own ACK.
    mutating func wrapPayload(
        _ packet: Data,
        secure: Bool,
        nonceSuffix: Data? = nil
    ) throws -> Data {
        guard !secure || state == .authenticated else {
            throw GatewayProtocolError.invalidState(expected: "authenticated", actual: "\(state)")
        }
        guard secure else { return packet }
        guard var active = cipher else { throw GatewayProtocolError.cipherNotInitialized }
        let body = try GatewayPayloadCodec.wrapSecure(
            packet,
            cipher: &active,
            nonceSuffix: nonceSuffix
        )
        cipher = active
        return body
    }

    func makeFrame(body: Data, reliableID: UInt16) -> Data {
        GatewayFrameCodec.encode(
            GatewayFrame(
                reliableID: reliableID,
                compressionEnabled: compressionEnabled,
                payload: body
            ),
            encryptCode: encryptCode
        )
    }

    private mutating func allocateReliableID() -> UInt16 {
        let id = outgoingReliableID
        outgoingReliableID = outgoingReliableID &+ 1
        return id
    }

    mutating func send<Message: GatewayMessage>(_ message: Message, nonceSuffix: Data? = nil) throws -> Data {
        try send(packet: GatewayPacketCodec.encode(message), nonceSuffix: nonceSuffix)
    }

    mutating func makeFrame(packet: Data, secure: Bool, nonceSuffix: Data? = nil) throws -> Data {
        let body = try wrapPayload(packet, secure: secure, nonceSuffix: nonceSuffix)

        // Sanctuary's UdpReliableChannel initializes ReliableIncomingId to 0
        // and only delivers a packet whose stamp equals the next expected id.
        // The very first gateway frame therefore has to use id 0; using 1
        // makes the server ACK the datagram but buffer it forever, which
        // presents as a login handshake timeout.
        return makeFrame(body: body, reliableID: allocateReliableID())
    }

    /// Feed a physical frame; errors are reported as events rather than thrown
    /// so a transport loop can continue processing later packets.
    mutating func receive(frame: Data) -> [GatewaySessionEvent] {
        do {
            let parsed = try GatewayFrameCodec.decode(
                frame,
                encryptCode: encryptCode,
                compressionEnabled: compressionEnabled
            )
            receivedReliableIDs.append(parsed.header.reliableID)
            return try receiveApplicationData(parsed.payload)
        } catch let error as GatewayProtocolError {
            return [.rejected(error)]
        } catch let error as ProtocolError {
            return [.rejected(.wire(error))]
        } catch {
            return [.rejected(.malformedFrame(String(describing: error)))]
        }
    }

    /// Feed an already-unframed application payload. Useful for tests and for
    /// transports that have their own framing layer.
    mutating func receiveApplicationData(_ data: Data) throws -> [GatewaySessionEvent] {
        let plaintext = try GatewayPayloadCodec.unwrap(data, cipher: &cipher)
        let opcode = try GatewayPacketCodec.opcode(from: plaintext)
        var events: [GatewaySessionEvent] = []

        switch opcode {
        case .login:
            let message = try GatewayPacketCodec.decode(GatewaySessionHello.self, from: plaintext)
            events.append(.packet(.login(message)))
        case .loginReply:
            let message = try GatewayPacketCodec.decode(GatewayLoginReply.self, from: plaintext)
            events.append(.packet(.loginReply(message)))
            if case .awaitingLoginReply = state {
                state = message.success ? .authenticated : .failed
                events.append(.stateChanged(state))
            }
        case .tunneled:
            let message = try GatewayPacketCodec.decode(GatewayTunneledPacket.self, from: plaintext)
            events.append(.packet(.tunneled(message)))
            events.append(contentsOf: decodeWorld(message.payload))
        case .tunneledWorld:
            let message = try GatewayPacketCodec.decode(GatewayTunneledWorldPacket.self, from: plaintext)
            events.append(.packet(.tunneledWorld(message)))
            events.append(contentsOf: decodeWorld(message.payload))
        }

        return events
    }

    private func decodeWorld(_ payload: Data) -> [GatewaySessionEvent] {
        // A tunneled payload is one world packet. `PacketSendSelfToClient` is
        // terminal: its nested payload is a raw ClientPcData record, not
        // another framed world packet, so it must not be reinterpreted by
        // opcode 125/35 etc.
        guard let decoded = try? GatewayWorldCodec.decodeAny(payload) else {
            return []
        }
        return [.world(decoded)]
    }
}
