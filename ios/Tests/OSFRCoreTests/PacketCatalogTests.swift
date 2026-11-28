import Foundation
import XCTest
@testable import OSFRCore

/// Source-backed packet routing catalog tests. The catalog is intentionally a
/// map from opcode to class name only: an entry here does not claim that the
/// packet's fields are decoded or that its gameplay semantics are implemented.
final class PacketCatalogTests: XCTestCase {
    private func framed(_ opcode: Int16, _ sub: Int16?, _ payload: [UInt8]) -> Data {
        var data = Data()
        data.append(UInt8(truncatingIfNeeded: UInt16(bitPattern: opcode)))
        data.append(UInt8(truncatingIfNeeded: UInt16(bitPattern: opcode) >> 8))
        if let sub {
            data.append(UInt8(truncatingIfNeeded: UInt16(bitPattern: sub)))
            data.append(UInt8(truncatingIfNeeded: UInt16(bitPattern: sub) >> 8))
        }
        data.append(contentsOf: payload)
        return data
    }

    func testCatalogCoversSanctuaryEffectiveOpcodes() {
        XCTAssertGreaterThan(PacketCatalog.classNames.count, 300)
        let classes = PacketCatalog.classNames.values.flatMap { $0 }
        XCTAssertEqual(Set(classes).count, 352)
        XCTAssertGreaterThan(PacketCatalog.rttiVerifiedClassNames.count, 70)
        XCTAssertTrue(PacketCatalog.isRTTIVerified("FriendListPacket"))
        XCTAssertFalse(PacketCatalog.isRTTIVerified("NotAClientPacket"))
    }

    func testInventoryCarriesSourceFieldMetadata() {
        XCTAssertEqual(SanctuaryPacketInventory.packets.count, 352)
        guard let friend = SanctuaryPacketInventory.metadata(for: "FriendListPacket") else {
            return XCTFail("Missing FriendListPacket metadata")
        }
        XCTAssertEqual(friend.wireType, "short")
        XCTAssertEqual(friend.opcode, 74)
        XCTAssertEqual(friend.subOpcode, 1)
        XCTAssertTrue(friend.rttiVerified)
        XCTAssertTrue(friend.fields.contains { $0.name == "Friends" })
        XCTAssertEqual(SanctuaryPacketInventory.packets.filter { $0.rttiVerified }.count, 73)
    }

    func testTopLevelKnownPacketIsPreservedAsRaw() throws {
        let data = framed(93, nil, [0xde, 0xad, 0xbe, 0xef])
        let packet = try GatewayWorldCodec.decodeAny(data)
        guard case .mapped(let opcode, let sub, let names, let payload) = packet else {
            return XCTFail("Expected mapped packet, got \(packet)")
        }
        XCTAssertEqual(opcode, 93)
        XCTAssertNil(sub)
        XCTAssertTrue(names.contains("PacketLoadWelcomeScreen"))
        XCTAssertEqual(payload, data)

        var observation = GatewayWorldObservation.empty
        observation.apply(packet)
        XCTAssertEqual(observation.mappedPacketCounts["PacketLoadWelcomeScreen"], 1)
        XCTAssertEqual(observation.lastMappedPayload, data)
    }

    func testSubOpcodeKnownPacketIsPreservedAsRaw() throws {
        let data = framed(49, 6, [0x01, 0x02])
        let packet = try GatewayWorldCodec.decodeAny(data)
        guard case .mapped(let opcode, let sub, let names, let payload) = packet else {
            return XCTFail("Expected mapped packet, got \(packet)")
        }
        XCTAssertEqual(opcode, 49)
        XCTAssertEqual(sub, 6)
        XCTAssertTrue(names.contains("QuestAbandonedPacket"))
        XCTAssertEqual(payload, data)
    }

    func testUnknownOpcodeStaysUnknown() throws {
        let data = framed(250, nil, [0x01])
        let packet = try GatewayWorldCodec.decodeAny(data)
        guard case .unknown(let opcode, let payload) = packet else {
            return XCTFail("Expected unknown packet, got \(packet)")
        }
        XCTAssertEqual(opcode, 250)
        XCTAssertEqual(payload, data)
    }
}
