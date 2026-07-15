import XCTest
@testable import ClaudeStatusCore

final class UpdateCheckTests: XCTestCase {

    func testParseHandlesPlainAndPrefixedVersions() {
        XCTAssertEqual(UpdateCheck.parse("1.1.0"), [1, 1, 0])
        XCTAssertEqual(UpdateCheck.parse("v1.2.3"), [1, 2, 3])
        XCTAssertEqual(UpdateCheck.parse(" V2.0 "), [2, 0])
        XCTAssertEqual(UpdateCheck.parse("1.2.0-beta.1"), [1, 2, 0])
        XCTAssertNil(UpdateCheck.parse(""))
        XCTAssertNil(UpdateCheck.parse("latest"))
        XCTAssertNil(UpdateCheck.parse("1.x"))
    }

    func testIsNewerComparesNumerically() {
        XCTAssertTrue(UpdateCheck.isNewer(latest: "v1.1.0", current: "1.0.1"))
        XCTAssertTrue(UpdateCheck.isNewer(latest: "1.10.0", current: "1.9.9")) // not lexicographic
        XCTAssertTrue(UpdateCheck.isNewer(latest: "2.0", current: "1.99.99"))
        XCTAssertFalse(UpdateCheck.isNewer(latest: "1.1.0", current: "1.1.0"))
        XCTAssertFalse(UpdateCheck.isNewer(latest: "v1.1", current: "1.1.0")) // padded equal
        XCTAssertFalse(UpdateCheck.isNewer(latest: "1.0.9", current: "1.1.0"))
    }

    // A malformed tag or a dev build without a version must never nag about updates.
    func testUnparseableInputIsNeverNewer() {
        XCTAssertFalse(UpdateCheck.isNewer(latest: "banana", current: "1.0.0"))
        XCTAssertFalse(UpdateCheck.isNewer(latest: "v2.0.0", current: ""))
    }

    func testParseLatestReleasePayload() {
        let json = #"{"tag_name":"v1.1.0","html_url":"https://github.com/merve/claude-traffic-light/releases/tag/v1.1.0"}"#
        let parsed = UpdateCheck.parseLatestRelease(json: Data(json.utf8))
        XCTAssertEqual(parsed?.tag, "v1.1.0")
        XCTAssertEqual(parsed?.url.absoluteString,
                       "https://github.com/merve/claude-traffic-light/releases/tag/v1.1.0")
    }

    func testParseLatestReleaseFallsBackToReleasesPageWithoutHtmlUrl() {
        let parsed = UpdateCheck.parseLatestRelease(json: Data(#"{"tag_name":"v9.9.9"}"#.utf8))
        XCTAssertEqual(parsed?.url, UpdateCheck.releasesPage)
    }

    func testGarbagePayloadReturnsNil() {
        XCTAssertNil(UpdateCheck.parseLatestRelease(json: Data("not json".utf8)))
        XCTAssertNil(UpdateCheck.parseLatestRelease(json: Data("{}".utf8)))
    }
}
