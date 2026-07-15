using System.Text.Json;

namespace ClaudeTrafficLight.Core;

/// <summary>
/// Manual "Check for Updates" support (mirrors macOS <c>UpdateCheck.swift</c>).
/// Pure logic only — version parsing/comparison and endpoint constants — so it is
/// unit-testable; the network call lives in the UI layer and fires ONLY when the
/// user clicks the menu item. The app makes no network requests on its own.
/// </summary>
public static class UpdateCheck
{
    /// <summary>GitHub repo the releases live in.</summary>
    public const string Repo = "merve/claude-traffic-light";

    /// <summary>Endpoint answering with the latest release (tag_name, html_url).</summary>
    public static string LatestReleaseApi => $"https://api.github.com/repos/{Repo}/releases/latest";

    /// <summary>Where to send the user when a newer version exists (also the
    /// fallback when the API response carries no html_url).</summary>
    public static string ReleasesPage => $"https://github.com/{Repo}/releases/latest";

    /// <summary>
    /// Numeric components of a version string. Tolerates a leading "v" and ignores
    /// anything after a pre-release/build separator ("1.2.0-beta.1" → [1,2,0]).
    /// Null when there is no leading numeric component at all.
    /// </summary>
    public static int[]? Parse(string version)
    {
        string s = version.Trim();
        if (s.StartsWith('v') || s.StartsWith('V')) s = s[1..];
        int cut = s.IndexOfAny(new[] { '-', '+' });
        if (cut >= 0) s = s[..cut];
        if (s.Length == 0) return null;
        var parts = s.Split('.');
        var result = new int[parts.Length];
        for (int i = 0; i < parts.Length; i++)
        {
            if (!int.TryParse(parts[i], out result[i])) return null;
        }
        return result;
    }

    /// <summary>
    /// True when <paramref name="latest"/> is strictly newer than
    /// <paramref name="current"/>. Unparseable input is never "newer" — a malformed
    /// tag or a dev build without a version must not nag the user with a phantom update.
    /// </summary>
    public static bool IsNewer(string latest, string current)
    {
        var l = Parse(latest);
        var c = Parse(current);
        if (l is null || c is null) return false;
        int n = Math.Max(l.Length, c.Length);
        for (int i = 0; i < n; i++)
        {
            int li = i < l.Length ? l[i] : 0;
            int ci = i < c.Length ? c[i] : 0;
            if (li != ci) return li > ci;
        }
        return false;
    }

    /// <summary>
    /// Extracts (tagName, htmlUrl) from a GitHub "latest release" JSON payload.
    /// Null when the payload has no usable tag.
    /// </summary>
    public static (string Tag, string Url)? ParseLatestRelease(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object
                || !root.TryGetProperty("tag_name", out var t)
                || t.ValueKind != JsonValueKind.String
                || string.IsNullOrEmpty(t.GetString()))
                return null;
            string url = root.TryGetProperty("html_url", out var u)
                         && u.ValueKind == JsonValueKind.String
                         && !string.IsNullOrEmpty(u.GetString())
                ? u.GetString()! : ReleasesPage;
            return (t.GetString()!, url);
        }
        catch
        {
            return null;
        }
    }
}
