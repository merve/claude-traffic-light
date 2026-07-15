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
    ///   - home: home directory, for the `~/Applications` fallback candidates (F8).
    ///     Defaults to the real home dir; tests inject a fixed value.
    ///   - isValidBundle: F10 — validates a candidate `.app` path is an actual bundle
    ///     (not just a folder that happens to end in ".app"); production callers pass
    ///     a real filesystem check, tests default to "always valid" for determinism.
    public static func action(platform: String, appPath: String, cwd: String, sessionID: String,
                              home: String = NSHomeDirectory(),
                              isValidBundle: (String) -> Bool = { _ in true }) -> OpenAction {
        switch platform {
        case "vscode":
            // Prefer the app the session actually runs in (captured by the hook —
            // handles Insiders builds and installs outside /Applications); the
            // editorCandidates fallback is only used when app_path wasn't captured.
            return .openInEditor(appPath: mainAppBundle(from: appPath, isValid: isValidBundle)
                                    ?? editorCandidates(home: home).first { $0.contains("Visual Studio Code") }!,
                                 folder: cwd)
        case "cursor":
            return .openInEditor(appPath: mainAppBundle(from: appPath, isValid: isValidBundle)
                                    ?? editorCandidates(home: home).first { $0.contains("Cursor") }!,
                                 folder: cwd)
        case "desktop":
            return .desktopDeepLink(sessionID: sessionID)
        case "terminal":
            // The session was started from a terminal → bring that terminal to
            // front (NOT the Claude desktop app). app_path tells us which one.
            if let app = mainAppBundle(from: appPath, isValid: isValidBundle) { return .activateApp(path: app) }
            return .desktopDeepLink(sessionID: sessionID) // last resort when app_path is missing
        default: // unknown — activate the hosting GUI app if we know it, else deep link
            if let app = mainAppBundle(from: appPath, isValid: isValidBundle) { return .activateApp(path: app) }
            return .desktopDeepLink(sessionID: sessionID)
        }
    }

    /// URL-scheme deep link that opens `folder` in the editor at `appPath` WITHOUT the
    /// caller touching the filesystem. Opening the folder as a file URL makes macOS TCC
    /// prompt "would like to access files in your Desktop folder" (and with an ad-hoc
    /// signed app, on every update again) — the URL scheme route never triggers it,
    /// because the editor itself does the file access. nil for editors without a known
    /// scheme; callers fall back to the file-based open.
    public static func editorDeepLink(appPath: String, folder: String) -> URL? {
        guard !folder.isEmpty, folder.hasPrefix("/") else { return nil }
        let scheme: String
        switch (appPath as NSString).lastPathComponent {
        case "Visual Studio Code.app":            scheme = "vscode"
        case "Visual Studio Code - Insiders.app": scheme = "vscode-insiders"
        case "Cursor.app":                        scheme = "cursor"
        default: return nil
        }
        guard let encoded = folder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "\(scheme)://file\(encoded)")
    }

    /// F8 — single source of truth for "generic folder opener" fallback order (VS Code
    /// before Cursor; /Applications before ~/Applications for each). Used by the vscode/
    /// cursor fallback above AND by both `openProjectFolder` copies (AppDelegate,
    /// WidgetController) so a normal click and an Option-click never disagree about which
    /// editor gets opened. `home` is a parameter (not read internally) so this stays a pure,
    /// unit-testable function; callers do the actual `FileManager` existence check.
    public static func editorCandidates(home: String) -> [String] {
        [
            "/Applications/Visual Studio Code.app",
            home + "/Applications/Visual Studio Code.app",
            "/Applications/Cursor.app",
            home + "/Applications/Cursor.app",
        ]
    }

    /// Outermost VALID `.app` bundle in a path. The hook records the nearest `.app`-suffixed
    /// path segment in the process ancestry, which for IDE-hosted sessions is an inner helper
    /// bundle ("…/Visual Studio Code.app/Contents/Frameworks/Code Helper.app") — the app to
    /// activate is the outer one. F10: a `.app`-suffixed segment isn't necessarily a real
    /// bundle (e.g. a folder literally named "tools.app" containing an app) — `isValid` lets
    /// the caller confirm it (e.g. an Info.plist check) before accepting it; a rejected
    /// candidate is skipped in favor of the NEXT `.app` segment, not treated as a dead end.
    /// If no candidate validates, falls back to the raw, unmodified `path` (old behavior)
    /// rather than nil — only a path with no ".app" segment at all returns nil.
    public static func mainAppBundle(from path: String, isValid: (String) -> Bool = { _ in true }) -> String? {
        guard !path.isEmpty else { return nil }
        var bundle = ""
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            bundle += "/" + component
            if component.hasSuffix(".app"), isValid(bundle) {
                return bundle
            }
        }
        return path.contains(".app") ? path : nil
    }
}
