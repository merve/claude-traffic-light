namespace ClaudeTrafficLight.Core;

/// <summary>
/// Detects sessions that have NEWLY turned red (waiting on you) so notifications
/// fire only on the transition, once per session — not on every poll.
///
/// The first call is a "seed": sessions already red at that point do NOT produce
/// a notification (so app launch doesn't spam notifications for pre-existing red
/// sessions); it only records the tracking set.
/// </summary>
public sealed class RedTransitionTracker
{
    private HashSet<string>? _known;

    /// <param name="currentRed">session IDs that are currently red.</param>
    /// <returns>the IDs that turned red in this call (always empty on the first call).</returns>
    public HashSet<string> NewlyRed(HashSet<string> currentRed)
    {
        var previous = _known;
        _known = currentRed;
        if (previous is null) return new HashSet<string>(); // first scan → seed silently
        var fresh = new HashSet<string>(currentRed);
        fresh.ExceptWith(previous);
        return fresh;
    }
}

/// <summary>Maps a session's platform code to a human-readable name.</summary>
public static class PlatformLabel
{
    public static string Label(string platform) => platform switch
    {
        "vscode" => "VS Code",
        "cursor" => "Cursor",
        "desktop" => "Claude",
        "terminal" => "Terminal",
        _ => "Claude"
    };
}
