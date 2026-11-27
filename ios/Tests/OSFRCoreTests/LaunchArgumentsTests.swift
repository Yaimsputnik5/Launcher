import Foundation
import XCTest
@testable import OSFRCore

final class LaunchArgumentsTests: XCTestCase {
    func testRecognizedWebAPILaunchArgumentsAreParsedAndApplied() {
        let arguments = LaunchArguments(
            "Server=play.example.com:20042 SessionId=abc123 " +
            "Internationalization:Locale=en_us Extra=\"two words\""
        )

        XCTAssertEqual(arguments.server, "play.example.com:20042")
        XCTAssertEqual(arguments.sessionID, "abc123")
        XCTAssertEqual(arguments.locale, .en_US)
        XCTAssertEqual(arguments.value(for: "extra"), "two words")
        XCTAssertEqual(arguments.raw, [
            "Server=play.example.com:20042",
            "SessionId=abc123",
            "Internationalization:Locale=en_us",
            "Extra=two words"
        ])
    }

    func testAbsentAndMalformedArgumentsDoNotInventValues() {
        XCTAssertEqual(LaunchArguments(nil).raw, [])
        XCTAssertNil(LaunchArguments("").locale)
        XCTAssertNil(LaunchArguments("Server").server)
        XCTAssertNil(LaunchArguments("Locale=not_a_supported_locale").locale)
    }
}

final class CredentialTransportSecurityTests: XCTestCase {
    func testCredentialsAreRestrictedToHTTPSOrLoopback() {
        XCTAssertTrue(URLHelper.credentialsAllowed(for: URL(string: "https://api.example.com/login")!))
        XCTAssertTrue(URLHelper.credentialsAllowed(for: URL(string: "http://localhost/login")!))
        XCTAssertTrue(URLHelper.credentialsAllowed(for: URL(string: "http://127.0.0.1:8080/login")!))
        XCTAssertFalse(URLHelper.credentialsAllowed(for: URL(string: "http://api.example.com/login")!))
        XCTAssertTrue(URLHelper.credentialsAllowed(for: URL(string: "http://127.1.2.3/login")!))
        XCTAssertFalse(URLHelper.credentialsAllowed(for: URL(string: "http://192.168.1.10/login")!))
        XCTAssertFalse(URLHelper.credentialsAllowed(for: URL(string: "ftp://api.example.com/login")!))
    }

    func testInsecureWarningIsLimitedToRemotePlainHTTP() {
        XCTAssertTrue(URLHelper.requiresInsecureTransportWarning(
            for: URL(string: "http://play.example.com/servermanifest.xml")!
        ))
        XCTAssertFalse(URLHelper.requiresInsecureTransportWarning(
            for: URL(string: "https://play.example.com/servermanifest.xml")!
        ))
        XCTAssertFalse(URLHelper.requiresInsecureTransportWarning(
            for: URL(string: "http://localhost/servermanifest.xml")!
        ))
        XCTAssertFalse(URLHelper.requiresInsecureTransportWarning(
            for: URL(string: "http://127.0.0.1:8080/servermanifest.xml")!
        ))
    }
}
