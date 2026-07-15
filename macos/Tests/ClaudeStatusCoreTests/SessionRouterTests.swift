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

    // The hook records the NEAREST .app of the ancestry — for IDE-hosted sessions
    // that's an inner helper bundle. The router must resolve the outer app so we
    // never activate "Code Helper.app" or hardcode a wrong install location.
    func testVSCodeDerivesMainAppFromHelperPath() {
        let helper = "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app"
        XCTAssertEqual(act("vscode", appPath: helper, cwd: "/work/app"),
                       .openInEditor(appPath: "/Applications/Visual Studio Code.app", folder: "/work/app"))
    }

    func testVSCodeInsidersOutsideApplicationsIsRespected() {
        let helper = "/Users/me/Applications/Visual Studio Code - Insiders.app/Contents/Frameworks/Code Helper.app"
        XCTAssertEqual(act("vscode", appPath: helper, cwd: "/w"),
                       .openInEditor(appPath: "/Users/me/Applications/Visual Studio Code - Insiders.app", folder: "/w"))
    }

    func testUnknownPlatformDerivesMainAppFromHelperPath() {
        let helper = "/Applications/Cursor.app/Contents/Frameworks/Cursor Helper.app"
        XCTAssertEqual(act("weird", appPath: helper), .activateApp(path: "/Applications/Cursor.app"))
    }

    func testMainAppBundle() {
        XCTAssertEqual(SessionRouter.mainAppBundle(from: "/Applications/iTerm.app"), "/Applications/iTerm.app")
        XCTAssertEqual(SessionRouter.mainAppBundle(
            from: "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app"),
            "/Applications/Visual Studio Code.app")
        XCTAssertNil(SessionRouter.mainAppBundle(from: ""))
        XCTAssertNil(SessionRouter.mainAppBundle(from: "/usr/local/bin/ghostty"))
    }

    func testUnknownWithAppPathActivatesIt() {
        XCTAssertEqual(act("unknown", appPath: "/Applications/Ghostty.app"),
                       .activateApp(path: "/Applications/Ghostty.app"))
    }

    func testUnknownWithoutAppPathFallsBackToDeepLink() {
        XCTAssertEqual(act("unknown", appPath: "", id: "s0"), .desktopDeepLink(sessionID: "s0"))
    }

    // MARK: - F8: single-source editor candidate list

    func testEditorCandidatesOrderAndContent() {
        XCTAssertEqual(SessionRouter.editorCandidates(home: "/Users/me"), [
            "/Applications/Visual Studio Code.app",
            "/Users/me/Applications/Visual Studio Code.app",
            "/Applications/Cursor.app",
            "/Users/me/Applications/Cursor.app",
        ])
    }

    func testVSCodeFallbackDrawsFromEditorCandidates() {
        // No app_path captured at all → falls back to the FIRST VS Code candidate,
        // same list openProjectFolder walks (normal click and Option-click agree).
        XCTAssertEqual(SessionRouter.action(platform: "vscode", appPath: "", cwd: "/w", sessionID: "s1", home: "/Users/me"),
                       .openInEditor(appPath: "/Applications/Visual Studio Code.app", folder: "/w"))
    }

    func testCursorFallbackDrawsFromEditorCandidates() {
        XCTAssertEqual(SessionRouter.action(platform: "cursor", appPath: "", cwd: "/w", sessionID: "s1", home: "/Users/me"),
                       .openInEditor(appPath: "/Applications/Cursor.app", folder: "/w"))
    }

    // MARK: - F10: mainAppBundle skips an invalid ".app"-suffixed segment

    func testMainAppBundleSkipsInvalidOuterAppFolder() {
        // "/x/tools.app" LOOKS like a bundle (ends in .app) but isn't one; the real
        // bundle is the next .app segment down. isValid rejects only "/x/tools.app".
        let result = SessionRouter.mainAppBundle(from: "/x/tools.app/iTerm.app") { $0 != "/x/tools.app" }
        XCTAssertEqual(result, "/x/tools.app/iTerm.app")
    }

    func testMainAppBundleFallsBackToRawPathWhenNothingValidates() {
        let result = SessionRouter.mainAppBundle(from: "/x/tools.app/iTerm.app") { _ in false }
        XCTAssertEqual(result, "/x/tools.app/iTerm.app") // raw path, unmodified — old behavior
    }

    func testMainAppBundleDefaultValidatorAcceptsFirstAppSegment() {
        // Default validator (no closure passed) preserves the pre-F10 behavior exactly.
        XCTAssertEqual(SessionRouter.mainAppBundle(from: "/Applications/iTerm.app"), "/Applications/iTerm.app")
    }

    // MARK: - Editor deep links (TCC-prompt avoidance)

    func testEditorDeepLinkForVSCodeEncodesThePath() {
        XCTAssertEqual(SessionRouter.editorDeepLink(appPath: "/Applications/Visual Studio Code.app",
                                                    folder: "/Users/me/My Projects/app")?.absoluteString,
                       "vscode://file/Users/me/My%20Projects/app")
    }

    func testEditorDeepLinkKnowsInsidersAndCursorSchemes() {
        XCTAssertEqual(SessionRouter.editorDeepLink(appPath: "/x/Visual Studio Code - Insiders.app",
                                                    folder: "/w")?.scheme, "vscode-insiders")
        XCTAssertEqual(SessionRouter.editorDeepLink(appPath: "/Applications/Cursor.app",
                                                    folder: "/w")?.scheme, "cursor")
    }

    func testEditorDeepLinkRejectsUnknownEditorsAndBadFolders() {
        XCTAssertNil(SessionRouter.editorDeepLink(appPath: "/Applications/Xcode.app", folder: "/w"))
        XCTAssertNil(SessionRouter.editorDeepLink(appPath: "/Applications/Cursor.app", folder: ""))
        XCTAssertNil(SessionRouter.editorDeepLink(appPath: "/Applications/Cursor.app", folder: "relative/path"))
    }

    func testActionThreadsIsValidBundleIntoTerminalRouting() {
        let result = SessionRouter.action(platform: "terminal", appPath: "/x/tools.app/iTerm.app",
                                          cwd: "/w", sessionID: "s1") { $0 != "/x/tools.app" }
        XCTAssertEqual(result, .activateApp(path: "/x/tools.app/iTerm.app"))
    }
}
