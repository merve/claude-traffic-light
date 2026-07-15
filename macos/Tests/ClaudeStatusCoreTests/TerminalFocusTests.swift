import XCTest
@testable import ClaudeStatusCore

final class TerminalFocusTests: XCTestCase {

    func testTerminalAppScriptTargetsTerminalAndTty() {
        let src = TerminalFocus.script(appPath: "/System/Applications/Utilities/Terminal.app",
                                       ttyDevice: "/dev/ttys012")
        XCTAssertNotNil(src)
        XCTAssertTrue(src!.contains("tell application \"Terminal\""))
        XCTAssertTrue(src!.contains("/dev/ttys012"))
    }

    func testITermScriptTargetsBundleIdAndSessions() {
        let src = TerminalFocus.script(appPath: "/Applications/iTerm.app",
                                       ttyDevice: "/dev/ttys003")
        XCTAssertNotNil(src)
        // Addressed by bundle id so the legacy "iTerm" app is never launched by name.
        XCTAssertTrue(src!.contains("com.googlecode.iterm2"))
        XCTAssertTrue(src!.contains("sessions of t"))
        XCTAssertTrue(src!.contains("/dev/ttys003"))
    }

    func testITerm2NamedBundleAlsoSupported() {
        XCTAssertNotNil(TerminalFocus.script(appPath: "/Applications/iTerm2.app",
                                             ttyDevice: "/dev/ttys000"))
    }

    // Non-scriptable terminals → nil, caller falls back to plain activation.
    func testUnsupportedTerminalsReturnNil() {
        for app in ["/Applications/Warp.app", "/Applications/Ghostty.app",
                    "/Applications/kitty.app", "/Applications/WezTerm.app"] {
            XCTAssertNil(TerminalFocus.script(appPath: app, ttyDevice: "/dev/ttys000"), app)
        }
    }
}
