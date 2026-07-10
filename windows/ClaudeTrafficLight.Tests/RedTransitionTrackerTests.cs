using ClaudeTrafficLight.Core;
using Xunit;

namespace ClaudeTrafficLight.Tests;

/// <summary>
/// The gate that makes a notification fire only when a session NEWLY turns red — once per
/// transition, never on the seed scan. Windows port of the macOS RedTransitionTrackerTests.
/// </summary>
public class RedTransitionTrackerTests
{
    private static HashSet<string> Set(params string[] ids) => new(ids);

    [Fact]
    public void First_scan_seeds_silently()
    {
        var t = new RedTransitionTracker();
        // Sessions already red at launch produce NO notification (avoid spam).
        Assert.Empty(t.NewlyRed(Set("a", "b")));
    }

    [Fact]
    public void A_newly_red_session_triggers()
    {
        var t = new RedTransitionTracker();
        t.NewlyRed(Set());                    // seed
        Assert.True(Set("a").SetEquals(t.NewlyRed(Set("a"))));
    }

    [Fact]
    public void Only_the_new_ones_are_reported()
    {
        var t = new RedTransitionTracker();
        t.NewlyRed(Set("a"));                 // seed: a is already red
        Assert.True(Set("b").SetEquals(t.NewlyRed(Set("a", "b")))); // only b is new
    }

    [Fact]
    public void Staying_red_does_not_retrigger()
    {
        var t = new RedTransitionTracker();
        t.NewlyRed(Set());
        Assert.True(Set("a").SetEquals(t.NewlyRed(Set("a"))));
        Assert.Empty(t.NewlyRed(Set("a")));   // still red → no re-trigger
    }

    [Fact]
    public void Leaving_and_reentering_red_retriggers()
    {
        var t = new RedTransitionTracker();
        t.NewlyRed(Set());
        Assert.True(Set("a").SetEquals(t.NewlyRed(Set("a"))));
        Assert.Empty(t.NewlyRed(Set()));                            // a no longer red
        Assert.True(Set("a").SetEquals(t.NewlyRed(Set("a"))));      // red again → re-trigger
    }

    [Fact]
    public void Multiple_new_at_once()
    {
        var t = new RedTransitionTracker();
        t.NewlyRed(Set());
        Assert.True(Set("a", "b", "c").SetEquals(t.NewlyRed(Set("a", "b", "c"))));
    }
}

/// <summary>Platform code → human label shown on session rows (widget + bar).</summary>
public class PlatformLabelTests
{
    [Theory]
    [InlineData("vscode", "VS Code")]
    [InlineData("cursor", "Cursor")]
    [InlineData("desktop", "Claude")]
    [InlineData("terminal", "Terminal")]
    public void Known_platforms(string code, string label)
        => Assert.Equal(label, PlatformLabel.Label(code));

    [Theory]
    [InlineData("unknown")]
    [InlineData("")]
    [InlineData("weird")]
    public void Unknown_falls_back_to_Claude(string code)
        => Assert.Equal("Claude", PlatformLabel.Label(code));
}
