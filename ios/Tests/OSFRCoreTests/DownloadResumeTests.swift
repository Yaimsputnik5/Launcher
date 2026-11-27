import Foundation
import XCTest
@testable import OSFRCore

final class DownloadResumeTests: XCTestCase {
    func testPartialFileSendsRangeAndKeepsExistingBytes() {
        let plan = DownloadResume.plan(
            existingBytes: 1024,
            expectedSize: 4096,
            statusCode: 206,
            contentRange: "bytes 1024-4095/4096",
            contentLength: 3072
        )
        XCTAssertEqual(plan.startingBytes, 1024)
        XCTAssertEqual(plan.totalBytes, 4096)
        XCTAssertFalse(plan.shouldTruncate)
        XCTAssertEqual(plan.rangeHeader, "bytes=1024-")
    }

    func testUnknownTotalUsesExpectedManifestSize() {
        let plan = DownloadResume.plan(
            existingBytes: 128,
            expectedSize: 4096,
            statusCode: 206,
            contentRange: "bytes 128-4095/*",
            contentLength: 3968
        )
        XCTAssertEqual(plan.startingBytes, 128)
        XCTAssertEqual(plan.totalBytes, 4096)
        XCTAssertFalse(plan.shouldTruncate)
    }

    func testServerIgnoringRangeRestartsCleanly() {
        let plan = DownloadResume.plan(
            existingBytes: 512,
            expectedSize: 4096,
            statusCode: 200,
            contentRange: nil,
            contentLength: 4096
        )
        XCTAssertEqual(plan.startingBytes, 0)
        XCTAssertEqual(plan.totalBytes, 4096)
        XCTAssertTrue(plan.shouldTruncate)
        XCTAssertNil(plan.rangeHeader)
    }

    func testMismatchedContentRangeRestartsCleanly() {
        let plan = DownloadResume.plan(
            existingBytes: 512,
            expectedSize: 4096,
            statusCode: 206,
            contentRange: "bytes 0-4095/4096",
            contentLength: 4096
        )
        XCTAssertEqual(plan.startingBytes, 0)
        XCTAssertTrue(plan.shouldTruncate)
    }

    func testOversizedPartialIsNeverResumed() {
        let plan = DownloadResume.plan(
            existingBytes: 5000,
            expectedSize: 4096,
            statusCode: 206,
            contentRange: "bytes 5000-8995/4096",
            contentLength: 3996
        )
        XCTAssertEqual(plan.startingBytes, 0)
        XCTAssertTrue(plan.shouldTruncate)
    }

    func testMalformedContentRangeIsRejected() {
        XCTAssertNil(DownloadResume.parseContentRange("4096"))
        XCTAssertNil(DownloadResume.parseContentRange("bytes 10-5/20"))
        XCTAssertNil(DownloadResume.parseContentRange("bytes abc-20/40"))
        let valid = DownloadResume.parseContentRange("bytes 10-19/20")
        XCTAssertEqual(valid?.start, 10)
        XCTAssertEqual(valid?.end, 19)
        XCTAssertEqual(valid?.total, 20)
    }
}
