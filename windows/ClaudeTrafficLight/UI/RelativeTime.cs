using ClaudeTrafficLight.Core;

namespace ClaudeTrafficLight.UI;

/// <summary>Short relative-time formatting for menu rows ("58s ago", "3m ago").</summary>
public static class RelativeTime
{
    public static string Ago(DateTimeOffset ts, L10n l)
    {
        var delta = DateTimeOffset.UtcNow - ts;
        double s = Math.Max(0, delta.TotalSeconds);

        // Keep it terse and language-neutral; the surrounding label is localized.
        if (s < 60) return $"{(int)s}s ago";
        if (s < 3600) return $"{(int)(s / 60)}m ago";
        if (s < 86400) return $"{(int)(s / 3600)}h ago";
        return $"{(int)(s / 86400)}d ago";
    }
}
