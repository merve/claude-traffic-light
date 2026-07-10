import Foundation

/// Action to perform when a session row / notification is clicked.
/// Kept pure (no AppKit) so the decision logic is unit-testable.
public enum OpenAction: Equatable {
    case desktopDeepLink(sessionID: String)             // Claude desktop — resume the session
    case activateApp(path: String)                      // bring a .app to front (e.g. a terminal)
    case openInEditor(appPath: String, folder: String)  // VS Code / Cursor → open the folder
}

/// Decides what to do based on the session's platform (and hosting .app path,
/// if any). The UI layer executes the returned decision.
public enum SessionRouter {

    /// - Parameters:
    ///   - platform: "vscode" | "cursor" | "desktop" | "terminal" | "unknown"
    ///   - appPath: hosting .app path captured by the hook (empty if unknown)
    ///   - cwd: project folder
    ///   - sessionID: session identifier (for the desktop deep link)
    public static func action(platform: String, appPath: String,
                              cwd: String, sessionID: String) -> OpenAction {
        switch platform {
        case "vscode":
            return .openInEditor(appPath: "/Applications/Visual Studio Code.app", folder: cwd)
        case "cursor":
            return .openInEditor(appPath: "/Applications/Cursor.app", folder: cwd)
        case "desktop":
            return .desktopDeepLink(sessionID: sessionID)
        case "terminal":
            // The session was started from a terminal → bring that terminal to
            // front (NOT the Claude desktop app). app_path tells us which one.
            if !appPath.isEmpty { return .activateApp(path: appPath) }
            return .desktopDeepLink(sessionID: sessionID) // last resort when app_path is missing
        default: // unknown — activate the hosting GUI app if we know it, else deep link
            if !appPath.isEmpty { return .activateApp(path: appPath) }
            return .desktopDeepLink(sessionID: sessionID)
        }
    }
}
