using System.Runtime.CompilerServices;
using System.Text.Json;
using Xunit;

namespace ClaudeTrafficLight.Tests;

/// <summary>
/// F4 (legend: WINDOWS-PORT-SPEC.md): the Windows hook event registration
/// (<see cref="Bootstrap.Events"/>) must stay event-for-event in sync with the macOS
/// snippet (macos/hooks/settings-snippet.json) — CONTRIBUTING.md "keep both platforms
/// in sync". This test reads the actual macOS JSON so a drift in either file fails CI
/// instead of silently diverging.
/// </summary>
public class BootstrapEventsTests
{
    private static string RepoRoot([CallerFilePath] string here = "")
        => Path.GetFullPath(Path.Combine(Path.GetDirectoryName(here)!, "..", ".."));

    [Fact]
    public void Windows_events_match_the_macOS_settings_snippet_one_for_one()
    {
        string snippetPath = Path.Combine(RepoRoot(), "macos", "hooks", "settings-snippet.json");
        using var doc = JsonDocument.Parse(File.ReadAllText(snippetPath));
        var hooks = doc.RootElement.GetProperty("hooks");

        // (event, matcher, state) from the macOS snippet, in the same shape as Bootstrap.Events.
        var macEvents = new List<(string Event, string? Matcher, string State)>();
        foreach (var evt in hooks.EnumerateObject())
        {
            foreach (var group in evt.Value.EnumerateArray())
            {
                string? matcher = group.TryGetProperty("matcher", out var m) ? m.GetString() : null;
                string command = group.GetProperty("hooks")[0].GetProperty("command").GetString()!;
                string state = command.Split(' ')[^1]; // "...claude-status-hook.sh <state>"
                macEvents.Add((evt.Name, matcher, state));
            }
        }

        var winEvents = Bootstrap.Events
            .Select(e => (e.Event, e.Matcher, e.State))
            .OrderBy(e => e.Event, StringComparer.Ordinal)
            .ToList();
        macEvents = macEvents.OrderBy(e => e.Event, StringComparer.Ordinal).ToList();

        Assert.Equal(macEvents, winEvents);
    }
}
