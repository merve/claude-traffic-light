using ClaudeTrafficLight.Core;
using Xunit;

namespace ClaudeTrafficLight.Tests;

/// <summary>Mirror of the macOS UpdateCheckTests — the comparison rules must match.</summary>
public class UpdateCheckTests
{
    [Theory]
    [InlineData("1.1.0", new[] { 1, 1, 0 })]
    [InlineData("v1.2.3", new[] { 1, 2, 3 })]
    [InlineData(" V2.0 ", new[] { 2, 0 })]
    [InlineData("1.2.0-beta.1", new[] { 1, 2, 0 })]
    public void Parse_handles_plain_and_prefixed_versions(string input, int[] expected)
        => Assert.Equal(expected, UpdateCheck.Parse(input));

    [Theory]
    [InlineData("")]
    [InlineData("latest")]
    [InlineData("1.x")]
    public void Parse_rejects_non_numeric_input(string input)
        => Assert.Null(UpdateCheck.Parse(input));

    [Theory]
    [InlineData("v1.1.0", "1.0.1", true)]
    [InlineData("1.10.0", "1.9.9", true)]  // numeric, not lexicographic
    [InlineData("2.0", "1.99.99", true)]
    [InlineData("1.1.0", "1.1.0", false)]
    [InlineData("v1.1", "1.1.0", false)]   // padded equal
    [InlineData("1.0.9", "1.1.0", false)]
    [InlineData("banana", "1.0.0", false)] // malformed tag never nags
    [InlineData("v2.0.0", "", false)]      // dev build without a version never nags
    public void IsNewer_compares_numerically(string latest, string current, bool expected)
        => Assert.Equal(expected, UpdateCheck.IsNewer(latest, current));

    [Fact]
    public void ParseLatestRelease_extracts_tag_and_url()
    {
        var parsed = UpdateCheck.ParseLatestRelease(
            "{\"tag_name\":\"v1.1.0\",\"html_url\":\"https://github.com/merve/claude-traffic-light/releases/tag/v1.1.0\"}");
        Assert.Equal("v1.1.0", parsed?.Tag);
        Assert.Equal("https://github.com/merve/claude-traffic-light/releases/tag/v1.1.0", parsed?.Url);
    }

    [Fact]
    public void ParseLatestRelease_falls_back_to_releases_page_without_html_url()
        => Assert.Equal(UpdateCheck.ReleasesPage,
                        UpdateCheck.ParseLatestRelease("{\"tag_name\":\"v9.9.9\"}")?.Url);

    [Theory]
    [InlineData("not json")]
    [InlineData("{}")]
    public void Garbage_payload_returns_null(string json)
        => Assert.Null(UpdateCheck.ParseLatestRelease(json));
}
