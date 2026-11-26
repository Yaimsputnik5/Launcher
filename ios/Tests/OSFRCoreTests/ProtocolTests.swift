import Foundation
import XCTest
@testable import OSFRCore

final class ProtocolTests: XCTestCase {
    func testPacketMagic() {
        XCTAssertEqual(PacketConstants.magic, 0xF3D4A5C9)
    }

    func testEveryPrimitiveRoundTrips() throws {
        var writer = PacketWriter()
        writer.writeUInt8(0x7F)
        writer.writeUInt16(0x1234)
        writer.writeUInt32(0x89ABCDEF)
        writer.writeUInt64(0x0123_4567_89AB_CDEF)
        writer.writeInt32(-123_456)
        writer.writeInt64(-9_876_543_210)
        writer.writeFloat(3.5)
        writer.writeBool(true)
        writer.writeBool(false)
        writer.writeString("hello")
        writer.writeData(Data([0x00, 0x01, 0xFF]))

        var reader = PacketReader(writer.data)
        XCTAssertEqual(try reader.readUInt8(), 0x7F)
        XCTAssertEqual(try reader.readUInt16(), 0x1234)
        XCTAssertEqual(try reader.readUInt32(), 0x89ABCDEF)
        XCTAssertEqual(try reader.readUInt64(), 0x0123_4567_89AB_CDEF)
        XCTAssertEqual(try reader.readInt32(), -123_456)
        XCTAssertEqual(try reader.readInt64(), -9_876_543_210)
        XCTAssertEqual(try reader.readFloat(), 3.5)
        XCTAssertEqual(try reader.readBool(), true)
        XCTAssertEqual(try reader.readBool(), false)
        XCTAssertEqual(try reader.readString(), "hello")
        XCTAssertEqual(try reader.readData(), Data([0x00, 0x01, 0xFF]))
        XCTAssertEqual(reader.remaining, 0)
        XCTAssertTrue(reader.isAtEnd)
    }

    func testNilAndEmptyStringWriteZeroLength() throws {
        var writer = PacketWriter()
        writer.writeString(nil)
        writer.writeString("")
        XCTAssertEqual(writer.data, Data(repeating: 0, count: 8))

        var reader = PacketReader(writer.data)
        XCTAssertEqual(try reader.readString(), "")
        XCTAssertEqual(try reader.readString(), "")
    }

    func testStringLengthIsUTF8ByteCount() throws {
        let value = "héllo 🌍"
        var writer = PacketWriter()
        writer.writeString(value)

        XCTAssertEqual(writer.data.count, 4 + value.utf8.count)
        XCTAssertEqual(Array(writer.data.prefix(4)), littleEndian(Int32(value.utf8.count)))

        var reader = PacketReader(writer.data)
        XCTAssertEqual(try reader.readString(), value)
    }

    func testReaderThrowsOnTruncatedData() {
        var reader = PacketReader(Data([0x01, 0x02]))
        XCTAssertEqual(try? reader.readUInt8(), 0x01)
        XCTAssertThrowsError(try reader.readUInt32()) { error in
            XCTAssertEqual(error as? ProtocolError, .truncated(expected: 4, available: 1))
        }
        XCTAssertEqual(reader.offset, 1)

        var stringReader = PacketReader(Data([0x03, 0x00, 0x00, 0x00, 0x61]))
        XCTAssertThrowsError(try stringReader.readString())

        var payloadReader = PacketReader(Data([0x02, 0x00, 0x00, 0x00, 0xAA]))
        XCTAssertThrowsError(try payloadReader.readData())

        var negativeReader = PacketReader(Data([0xFF, 0xFF, 0xFF, 0xFF]))
        XCTAssertThrowsError(try negativeReader.readString())
    }

    func testCRC32StandardVector() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF43926)
    }

    /// Independent vector for the four little-endian seed bytes fed into the
    /// initial CRC state, as done by `UdpMisc.Crc32`.
    func testCRC32EncryptCodeSeeding() {
        let data = Data("123456789".utf8)
        XCTAssertEqual(CRC32.checksum(data, encryptCode: 0x01020304), 0x22000193)
        XCTAssertNotEqual(CRC32.checksum(data, encryptCode: 0), CRC32.checksum(data))
    }

    func testRC4KnownVector() {
        var cipher = RC4(key: Data("Key".utf8))
        let ciphertext = cipher.process(Data("Plaintext".utf8))
        XCTAssertEqual(hex(ciphertext), "BBF316E8D940AF0AD3")
    }

    func testRC4KeystreamContinuesAcrossCalls() {
        var cipher = RC4(key: Data("Key".utf8))
        var combined = cipher.process(Data("Plain".utf8))
        combined.append(cipher.process(Data("text".utf8)))
        XCTAssertEqual(hex(combined), "BBF316E8D940AF0AD3")
    }

    func testRC4LoginKeyIsBase64() {
        XCTAssertEqual(RC4.loginKey.count, 16)
        XCTAssertEqual(RC4.loginKey.base64EncodedString(), RC4.loginKeyBase64)
    }

    func testGuidHelperPlayerRoundTrip() {
        let id: UInt64 = 123_456
        let guid = GuidHelper.playerGuid(id)
        XCTAssertEqual(GuidHelper.playerId(guid), id)
        XCTAssertNil(GuidHelper.playerId(GuidHelper.npcGuid(counter: 1, instanceId: 1)))
    }

    func testGuidHelperLowNibbleTypes() {
        XCTAssertEqual(GuidHelper.playerGuid(7) & GuidHelper.typeMask, 1)
        XCTAssertEqual(GuidHelper.guidType(GuidHelper.playerGuid(7)), .player)

        let npc = GuidHelper.npcGuid(counter: 2, instanceId: 3)
        XCTAssertEqual(npc & GuidHelper.typeMask, 2)
        XCTAssertEqual(GuidHelper.guidType(npc), .npc)
        XCTAssertEqual(npc, (UInt64(2) << 36) | (UInt64(3) << 8) | (UInt64(1) << 4) | 2)

        let location = GuidHelper.locationTargetGuid(42)
        XCTAssertEqual(location & GuidHelper.typeMask, 3)
        XCTAssertEqual(GuidHelper.guidType(location), .locationTarget)
    }

    // MARK: - Helpers

    private func littleEndian(_ value: Int32) -> [UInt8] {
        let bits = UInt32(bitPattern: value)
        return (0..<4).map { UInt8(truncatingIfNeeded: bits >> (8 * $0)) }
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }
}
