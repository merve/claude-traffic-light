import XCTest
@testable import ClaudeStatusCore

final class SessionRouterTests: XCTestCase {

    private func act(_ platform: String, appPath: String = "", cwd: String = "/proj", id: String = "s1") -> OpenAction {
        SessionRouter.action(platform: platform, appPath: appPath, cwd: cwd, sessionID: id)
    }

    func testVSCodeOpensFolderInVSCode() {
        XCTAssertEqual(act("vscode", cwd: "/work/app"),
                       .openInEditor(appPath: "/Applications/Visual Studio Code.app", folder: "/work/app"))
    }

    func testCursorOpensFolderInCursor() {
        XCTAssertEqual(act("cursor", cwd: "/work/app"),
                       .openInEditor(appPath: "/Applications/Cursor.app", folder: "/work/app"))
    }

    func testDesktopUsesDeepLink() {
        XCTAssertEqual(act("desktop", id: "abc"), .desktopDeepLink(sessionID: "abc"))
    }

    // THE BUG: a terminal session with a known app_path must bring its terminal
    // to front — NOT the Claude desktop app (deep link).
    func testTerminalActivatesItsOwnApp() {
        XCTAssertEqual(act("terminal", appPath: "/Applications/iTerm.app"),
                       .activateApp(path: "/Applications/iTerm.app"))
        XCTAssertEqual(act("terminal", appPath: "/System/Applications/Utilities/Terminal.app"),
                       .activateApp(path: "/System/Applications/Utilities/Terminal.app"))
    }

    func testTerminalIsNotRoutedToDesktopWhenAppPathKnown() {
        let a = act("terminal", appPath: "/Applications/Warp.app", id: "xyz")
        XCTAssertNotEqual(a, .desktopDeepLink(sessionID: "xyz"))
    }

    func testTerminalWithoutAppPathFallsBackToDeepLink() {
        XCTAssertEqual(act("terminal", appPath: "", id: "s9"), .desktopDeepLink(sessionID: "s9"))
    }

    func testUnknownWithAppPathActivatesIt() {
        XCTAssertEqual(act("unknown", appPath: "/Applications/Ghostty.app"),
                       .activateApp(path: "/Applications/Ghostty.app"))
    }

    func testUnknownWithoutAppPathFallsBackToDeepLink() {
        XCTAssertEqual(act("unknown", appPath: "", id: "s0"), .desktopDeepLink(sessionID: "s0"))
    }
}
