import Foundation
import XCTest
@testable import OSFRCore

/// Regression coverage for the post-login bootstrap and entity lifecycle
/// packets decoded from Sanctuary's authoritative C# layouts.
final class GatewayBootstrapTests: XCTestCase {
    private func base35(_ sub: Int16, body: (inout PacketWriter) -> Void) -> Data {
        var writer = PacketWriter()
        GatewayWire.appendInt16(35, to: &writer.data)
        GatewayWire.appendInt16(sub, to: &writer.data)
        body(&writer)
        return writer.data
    }

    func testBootstrapPacketsDecodeFromSanctuaryFieldOrder() throws {
        var zone = PacketWriter()
        GatewayWire.appendInt16(43, to: &zone.data)
        zone.writeString("Fabled Realms")
        zone.writeInt32(2)
        zone.writeBool(false)
        zone.writeBool(false)
        zone.writeString("sky")
        zone.writeBool(false)
        zone.writeInt32(1001)
        zone.writeInt32(2002)
        zone.writeBool(true)
        zone.writeBool(false)
        guard case .zoneDetails(let details) = try GatewayWorldCodec.decodeAny(zone.data) else {
            return XCTFail("expected zone details")
        }
        XCTAssertEqual(details.name, "Fabled Realms")
        XCTAssertEqual(details.id, 1001)
        XCTAssertEqual(details.geometryID, 2002)
        XCTAssertEqual(details.sky, "sky")

        var environment = PacketWriter()
        GatewayWire.appendInt16(166, to: &environment.data)
        environment.writeString("FabledRealms")
        guard case .initializationParameters(let parameters) = try GatewayWorldCodec.decodeAny(environment.data) else {
            return XCTFail("expected initialization parameters")
        }
        XCTAssertEqual(parameters.environment, "FabledRealms")

        var settings = PacketWriter()
        GatewayWire.appendInt16(144, to: &settings.data)
        settings.writeInt32(1)
        settings.writeInt32(2)
        settings.writeInt32(3)
        settings.writeBool(true)
        settings.writeFloat(1.25)
        guard case .clientGameSettings(let gameSettings) = try GatewayWorldCodec.decodeAny(settings.data) else {
            return XCTFail("expected client game settings")
        }
        XCTAssertEqual(gameSettings.powerHourEffectTag, 3)
        XCTAssertTrue(gameSettings.unknown4)
        XCTAssertEqual(gameSettings.gameTimeScalar, 1.25)

        var time = PacketWriter()
        GatewayWire.appendInt16(52, to: &time.data)
        time.writeInt64(1_700_000_000)
        time.writeInt32(60)
        time.writeBool(false)
        guard case .gameTimeSync(let sync) = try GatewayWorldCodec.decodeAny(time.data) else {
            return XCTFail("expected game time sync")
        }
        XCTAssertEqual(sync.time, 1_700_000_000)
        XCTAssertEqual(sync.serverRate, 60)

        var done = PacketWriter()
        GatewayWire.appendInt16(14, to: &done.data)
        XCTAssertEqual(try GatewayWorldCodec.decodeAny(done.data), .zoneDoneSendingInitialData)

        var preload = PacketWriter()
        GatewayWire.appendInt16(38, to: &preload.data)
        GatewayWire.appendInt16(26, to: &preload.data)
        preload.writeBool(true)
        guard case .preloadCharactersDone(let event) = try GatewayWorldCodec.decodeAny(preload.data) else {
            return XCTFail("expected preload completion")
        }
        XCTAssertTrue(event.preload)

        var combat = PacketWriter()
        GatewayWire.appendInt16(41, to: &combat.data)
        GatewayWire.appendInt16(132, to: &combat.data)
        combat.writeBool(true)
        guard case .overworldCombat(let overworld) = try GatewayWorldCodec.decodeAny(combat.data) else {
            return XCTFail("expected overworld combat")
        }
        XCTAssertTrue(overworld.inWorldCombat)
    }

    func testPlayerUpdateSubDispatchDecodesDefinitionsStateScaleAndRemoval() throws {
        let definitions = base35(37) { writer in
            var payload = PacketWriter()
            payload.writeInt32(2)
            writer.writeData(payload.data)
        }
        guard case .itemDefinitions(let items) = try GatewayWorldCodec.decodeAny(definitions) else {
            return XCTFail("expected item definitions")
        }
        var reader = PacketReader(items.payload)
        XCTAssertEqual(try reader.readInt32(), 2)

        let state = base35(20) { writer in
            writer.writeUInt64(42)
            writer.writeInt32(7)
        }
        guard case .characterState(let characterState) = try GatewayWorldCodec.decodeAny(state) else {
            return XCTFail("expected character state")
        }
        XCTAssertEqual(characterState.guid, 42)
        XCTAssertEqual(characterState.state, 7)

        let scale = base35(13) { writer in
            writer.writeUInt64(42)
            writer.writeFloat(1.75)
        }
        guard case .scaleUpdate(let scaleUpdate) = try GatewayWorldCodec.decodeAny(scale) else {
            return XCTFail("expected scale update")
        }
        XCTAssertEqual(scaleUpdate.guid, 42)
        XCTAssertEqual(scaleUpdate.scale, 1.75)

        let removal = base35(3) { writer in
            GatewayWire.appendInt16(0, to: &writer.data)
            writer.writeUInt64(42)
        }
        guard case .entityRemoved(let entityRemoval) = try GatewayWorldCodec.decodeAny(removal) else {
            return XCTFail("expected entity removal")
        }
        XCTAssertEqual(entityRemoval.guid, 42)
        XCTAssertEqual(entityRemoval.subSubOpcode, 0)
    }

    func testGracefulRemovalReadsAnimationFields() throws {
        let removal = base35(3) { writer in
            GatewayWire.appendInt16(1, to: &writer.data)
            writer.writeUInt64(99)
            writer.writeBool(true)
            writer.writeInt32(100)
            writer.writeInt32(200)
            writer.writeInt32(300)
            writer.writeInt32(400)
        }
        guard case .entityRemoved(let event) = try GatewayWorldCodec.decodeAny(removal) else {
            return XCTFail("expected entity removal")
        }
        XCTAssertEqual(event.subSubOpcode, 1)
        XCTAssertEqual(event.animate, true)
        XCTAssertEqual(event.delay, 100)
        XCTAssertEqual(event.effectDelay, 200)
        XCTAssertEqual(event.compositeEffectID, 300)
        XCTAssertEqual(event.duration, 400)
    }

    func testObservationAppliesZoneAndLifecyclePackets() throws {
        var observation = GatewayWorldObservation.empty
        var zone = PacketWriter()
        GatewayWire.appendInt16(43, to: &zone.data)
        zone.writeString("North District")
        zone.writeInt32(2)
        zone.writeBool(false)
        zone.writeBool(false)
        zone.writeString("")
        zone.writeBool(false)
        zone.writeInt32(1001)
        zone.writeInt32(2002)
        zone.writeBool(true)
        zone.writeBool(false)
        observation.apply(try GatewayWorldCodec.decodeAny(zone.data))
        XCTAssertEqual(observation.zoneName, "North District")
        XCTAssertEqual(observation.zoneID, 1001)
        XCTAssertEqual(observation.geometryID, 2002)

        var time = PacketWriter()
        GatewayWire.appendInt16(52, to: &time.data)
        time.writeInt64(1234)
        time.writeInt32(30)
        time.writeBool(true)
        observation.apply(try GatewayWorldCodec.decodeAny(time.data))
        XCTAssertEqual(observation.gameTime, 1234)
        XCTAssertEqual(observation.serverRate, 30)
        XCTAssertEqual(observation.useClientTime, true)

        let state = base35(20) { writer in
            writer.writeUInt64(88)
            writer.writeInt32(4)
        }
        let spawn = base35(1) { writer in
            writer.writeUInt64(88)
            GatewayName(
                firstNameID: 1,
                lastNamePrefixID: 2,
                lastNameSuffixID: 3,
                firstName: "Grace",
                lastName: "Hopper"
            ).append(to: &writer)
            writer.writeInt32(10)
            writer.writeInt32(0)
            writer.writeInt32(0)
            writer.writeInt32(0)
            writer.writeFloat(1)
            writer.writeFloat(2)
            writer.writeFloat(3)
            writer.writeFloat(1)
            writer.writeFloat(0)
            writer.writeFloat(0)
            writer.writeFloat(0)
            writer.writeFloat(1)
        }
        observation.apply(try GatewayWorldCodec.decodeAny(spawn))
        observation.apply(try GatewayWorldCodec.decodeAny(state))
        XCTAssertEqual(observation.names[88], "Grace Hopper")
        XCTAssertEqual(observation.positions[88]?.state, 4)

        let scale = base35(13) { writer in
            writer.writeUInt64(88)
            writer.writeFloat(2.5)
        }
        observation.apply(try GatewayWorldCodec.decodeAny(scale))
        XCTAssertEqual(observation.scales[88], 2.5)

        let removal = base35(3) { writer in
            GatewayWire.appendInt16(0, to: &writer.data)
            writer.writeUInt64(88)
        }
        observation.apply(try GatewayWorldCodec.decodeAny(removal))
        XCTAssertNil(observation.positions[88])
        XCTAssertNil(observation.names[88])
        XCTAssertNil(observation.scales[88])
    }
}
