import Foundation

/// Detects sessions that have NEWLY turned red (waiting on you) so notifications
/// fire only on the transition, once per session — not on every poll.
///
/// The first call is a "seed": sessions already red at that point do NOT produce
/// a notification (so app launch doesn't spam notifications for pre-existing red
/// sessions); it only records the tracking set.
public final class RedTransitionTracker {
    private var known: Set<String>? = nil

    public init() {}

    /// - Parameter currentRed: session IDs that are currently red.
    /// - Returns: the IDs that turned red in this call (always empty on the first call).
    public func newlyRed(_ currentRed: Set<String>) -> Set<String> {
        defer { known = currentRed }
        guard let previous = known else { return [] } // first scan → seed silently
        return currentRed.subtracting(previous)
    }
}

/// Maps a session's platform code to a human-readable name.
public enum PlatformLabel {
    public static func label(_ platform: String) -> String {
        switch platform {
        case "vscode":   return "VS Code"
        case "cursor":   return "Cursor"
        case "desktop":  return "Claude"
        case "terminal": return "Terminal"
        default:         return "Claude"
        }
    }
}
