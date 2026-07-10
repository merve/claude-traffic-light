namespace ClaudeTrafficLight.Core;

/// <summary>
/// Action to perform when a session row / notification is clicked.
/// Kept pure (no WinForms / P-Invoke) so the decision logic is unit-testable.
/// The UI layer executes the returned decision (see Platform.AppLauncher).
/// </summary>
public abstract record OpenAction
{
    /// VS Code / Cursor → open the project folder in the editor.
    public sealed record OpenInEditor(string Editor, string Folder) : OpenAction;

    /// Claude desktop — resume the session via deep link.
    public sealed record DesktopDeepLink(string SessionId) : OpenAction;

    /// Bring the session's window (terminal / other) to the front; open the folder if no window.
    public sealed record FocusProcessWindow(int Pid, string FallbackFolder) : OpenAction;
}

/// <summary>Decides what to do based on the session's platform (Windows adaptation of §5).</summary>
public static class SessionRouter
{
    /// <param name="platform">"vscode" | "cursor" | "desktop" | "terminal" | "unknown"</param>
    /// <param name="pid">the session's claude process pid (0 if unknown)</param>
    /// <param name="cwd">project folder</param>
    /// <param name="sessionId">session identifier (for the desktop deep link)</param>
    public static OpenAction Action(string platform, int pid, string cwd, string sessionId) => platform switch
    {
        "vscode" => new OpenAction.OpenInEditor("code", cwd),
        "cursor" => new OpenAction.OpenInEditor("cursor", cwd),
        "desktop" => new OpenAction.DesktopDeepLink(sessionId),
        // terminal / unknown: bring the hosting window to front; fall back to the folder / deep link.
        _ => pid > 0
            ? new OpenAction.FocusProcessWindow(pid, cwd)
            : new OpenAction.DesktopDeepLink(sessionId)
    };
}
