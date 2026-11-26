import Foundation
import XCTest
@testable import OSFRCore

final class DefaultServerTests: XCTestCase {
    func testMatchesTheDesktopLauncherBootstrapURL() {
        XCTAssertEqual(AppConstants.defaultServerURLs, ["https://opensourcefreerealms.com"])
        XCTAssertEqual(DefaultServer.url, "https://opensourcefreerealms.com")
        XCTAssertEqual(DefaultServer.manifestName, "servermanifest.xml")
        XCTAssertNoThrow(try URLHelper.baseURL(DefaultServer.url))
    }

    func testPresetUsesHTTPSAndStableIdentity() throws {
        let info = DefaultServer.info()

        XCTAssertEqual(info.id, DefaultServer.id)
        XCTAssertEqual(info.name, "OSFR Public Server")
        XCTAssertEqual(info.url, DefaultServer.url)
        XCTAssertEqual(info.webAPIURL, "https://api.opensourcefreerealms.com/")
        XCTAssertEqual(info.loginServer, "play.opensourcefreerealms.com:20042")

        let base = try URLHelper.baseURL(info.url)
        XCTAssertEqual(base.scheme, "https")
        XCTAssertFalse(info.url.contains("@"))
        XCTAssertFalse(info.rememberPassword)

        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(ServerInfo.self, from: data)
        XCTAssertEqual(decoded, info)
    }
}
