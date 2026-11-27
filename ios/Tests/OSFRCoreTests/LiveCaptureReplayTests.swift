import Foundation
import XCTest
@testable import OSFRCore

/// Replays the first real gateway datagram captured from
/// play.opensourcefreerealms.com:20260 after a valid PacketLogin. The reply is a
/// compressed Multi containing KeepAlive and a reliable Group whose first
/// subpacket is PacketLoginReply(success: true).
final class LiveCaptureReplayTests: XCTestCase {
    private let cookedHex =
        "00030400150000730009000000190302" +
        "00010c05000105000000290084000111" +
        "0500010a000000a600040000006c6976" +
        "652e050001270000002b000c00000046" +
        "61626c65645265616c6d730200000000" +
        "00000000000001000000000000000000" +
        "1a050001130000009000040000000700" +
        "00000c010000010000803f"

    func testCapturedGatewayMultiYieldsSuccessfulLoginReply() throws {
        var bytes = [UInt8]()
        var cursor = cookedHex.startIndex
        while cursor < cookedHex.endIndex {
            let next = cookedHex.index(cursor, offsetBy: 2)
            bytes.append(UInt8(cookedHex[cursor..<next], radix: 16)!)
            cursor = next
        }
        let cooked = Data(bytes)
        var state = UdpLibraryReassemblyState()
        var session = GatewaySession(
            connectCode: 0x0cc871ce,
            encryptCode: 0x2ed7135c,
            compressionEnabled: true
        )
        try session.setCipher(ticket: String(repeating: "0", count: 32))
        var foundSuccess = false
        for packet in UdpLibrary.parse(cooked, state: &state) {
            guard case .reliable(_, _, _, let applications) = packet else { continue }
            for application in applications {
                for event in try session.receiveApplicationData(application) {
                    if case .packet(.loginReply(let reply)) = event, reply.success {
                        foundSuccess = true
                    }
                }
            }
        }
        XCTAssertTrue(foundSuccess)
    }
}
