using ClaudeTrafficLight.Core;
using Xunit;

namespace ClaudeTrafficLight.Tests;

/// <summary>Code-embedded localization tables. Windows port of the macOS LocalizationTests.</summary>
public class LocalizationTests
{
    [Fact]
    public void Unknown_language_falls_back_to_English()
    {
        Assert.False(L10n.Tables.ContainsKey("xx"));
        Assert.Equal("en", (L10n.Tables.GetValueOrDefault("xx") ?? L10n.English).LocaleId);
    }

    [Fact]
    public void Label_maps_each_state()
    {
        var l = L10n.English;
        Assert.Equal(l.Asking, l.Label(State.Red));
        Assert.Equal(l.Working, l.Label(State.Yellow));
        Assert.Equal(l.Done, l.Label(State.Green));
    }

    [Fact]
    public void Turkish_table_exists()
    {
        var tr = L10n.Tables["tr"];
        Assert.Equal("tr", tr.LocaleId);
        Assert.Equal("Claude seni bekliyor", tr.NotifyTitle);
    }

    [Fact]
    public void Current_returns_a_valid_table()
    {
        var l = L10n.Current;
        Assert.False(string.IsNullOrEmpty(l.LocaleId));
        Assert.False(string.IsNullOrEmpty(l.Working));
    }

    // Every language table must fill every string field (catch a missing translation).
    [Fact]
    public void All_tables_have_non_empty_fields()
    {
        var stringProps = typeof(L10n).GetProperties().Where(p => p.PropertyType == typeof(string));
        foreach (var (code, l) in L10n.Tables)
            foreach (var prop in stringProps)
            {
                var value = (string?)prop.GetValue(l);
                Assert.False(string.IsNullOrEmpty(value), $"[{code}] '{prop.Name}' must not be empty");
            }
    }

    [Theory]
    [InlineData("en")]
    [InlineData("tr")]
    [InlineData("es")]
    [InlineData("de")]
    [InlineData("fr")]
    [InlineData("it")]
    [InlineData("pt")]
    [InlineData("ru")]
    [InlineData("ja")]
    [InlineData("zh")]
    [InlineData("ko")]
    public void Expected_language_is_present(string code)
        => Assert.True(L10n.Tables.ContainsKey(code), $"missing table for {code}");
}
