namespace ClaudeTrafficLight.Core;

/// <summary>Shared filesystem locations. The status dir must match the macOS contract.</summary>
public static class Paths
{
    /// <summary><c>%USERPROFILE%\.claude</c> — Claude Code uses the home dir on Windows too.</summary>
    public static string ClaudeDir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude");

    /// <summary><c>%USERPROFILE%\.claude\status</c> — one <c>&lt;session_id&gt;.json</c> per session.</summary>
    public static string StatusDir => Path.Combine(ClaudeDir, "status");

    /// <summary><c>%USERPROFILE%\.claude\settings.json</c> — where hook groups are merged.</summary>
    public static string SettingsFile => Path.Combine(ClaudeDir, "settings.json");
}
