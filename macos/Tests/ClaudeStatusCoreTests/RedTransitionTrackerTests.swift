import XCTest
@testable import ClaudeStatusCore

final class RedTransitionTrackerTests: XCTestCase {

    func testFirstScanSeedsSilently() {
        let t = RedTransitionTracker()
        // Sessions already red at launch produce NO notification (avoid spam).
        XCTAssertEqual(t.newlyRed(["a", "b"]), [])
    }

    func testNewRedTriggers() {
        let t = RedTransitionTracker()
        _ = t.newlyRed([])                    // seed
        XCTAssertEqual(t.newlyRed(["a"]), ["a"])
    }

    func testOnlyNewOnesReported() {
        let t = RedTransitionTracker()
        _ = t.newlyRed(["a"])                 // seed: a is already red
        XCTAssertEqual(t.newlyRed(["a", "b"]), ["b"]) // only b is new
    }

    func testStayingRedDoesNotRetrigger() {
        let t = RedTransitionTracker()
        _ = t.newlyRed([])
        XCTAssertEqual(t.newlyRed(["a"]), ["a"])
        XCTAssertEqual(t.newlyRed(["a"]), [])  // still red → no re-trigger
    }

    func testLeavingAndReenteringRedRetriggers() {
        let t = RedTransitionTracker()
        _ = t.newlyRed([])
        XCTAssertEqual(t.newlyRed(["a"]), ["a"])
        XCTAssertEqual(t.newlyRed([]), [])     // a is no longer red
        XCTAssertEqual(t.newlyRed(["a"]), ["a"]) // red again → re-trigger
    }

    func testMultipleNewAtOnce() {
        let t = RedTransitionTracker()
        _ = t.newlyRed([])
        XCTAssertEqual(t.newlyRed(["a", "b", "c"]), ["a", "b", "c"])
    }
}

final class PlatformLabelTests: XCTestCase {
    func testKnownPlatforms() {
        XCTAssertEqual(PlatformLabel.label("vscode"), "VS Code")
        XCTAssertEqual(PlatformLabel.label("cursor"), "Cursor")
        XCTAssertEqual(PlatformLabel.label("desktop"), "Claude")
        XCTAssertEqual(PlatformLabel.label("terminal"), "Terminal")
    }

    func testUnknownFallsBackToClaude() {
        XCTAssertEqual(PlatformLabel.label("unknown"), "Claude")
        XCTAssertEqual(PlatformLabel.label(""), "Claude")
        XCTAssertEqual(PlatformLabel.label("weird"), "Claude")
    }
}
