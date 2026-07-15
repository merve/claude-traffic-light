import Foundation

/// Builds the AppleScript that selects the exact terminal tab/session running a
/// given tty. Activating a terminal app by path alone just raises whichever
/// window macOS last used — wrong when several Claude sessions run in separate
/// windows/tabs of the same app. Pure string logic (no AppKit/OSA) so the
/// selection is unit-testable; callers execute the returned source.
public enum TerminalFocus {

    /// - Parameters:
    ///   - appPath: the terminal's .app bundle path (from the session's app_path).
    ///   - ttyDevice: the session's tty as `/dev/ttysNNN` (see `TTYDevice.parse`).
    /// - Returns: AppleScript source, or nil when the app has no scriptable
    ///   tab model we support (Warp, ghostty, kitty, …) — callers should fall
    ///   back to plain app activation.
    public static func script(appPath: String, ttyDevice: String) -> String? {
        switch (appPath as NSString).lastPathComponent {
        case "Terminal.app":
            return terminalAppScript(tty: ttyDevice)
        case "iTerm.app", "iTerm2.app":
            return itermScript(tty: ttyDevice)
        default:
            return nil
        }
    }

    private static func terminalAppScript(tty: String) -> String {
        """
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set frontmost of w to true
                        set selected of t to true
                        return true
                    end if
                end repeat
            end repeat
            return false
        end tell
        """
    }

    /// Addressed by bundle id so we never launch the legacy "iTerm" app by name.
    private static func itermScript(tty: String) -> String {
        """
        tell application id "com.googlecode.iterm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            select w
                            select t
                            select s
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
            return false
        end tell
        """
    }
}
