using ClaudeTrafficLight.Hook;
using Xunit;

namespace ClaudeTrafficLight.Tests;

/// <summary>
/// F1 (legend: WINDOWS-PORT-SPEC.md): the courtesy-close check must anchor to the LAST
/// SENTENCE of the assistant's final message, not an arbitrary trailing character window —
/// otherwise a compound question that merely contains a courtesy-shaped substring reads as
/// "done" instead of "waiting on you" (the exact regression this table catches: the German
/// row below reads as a real question despite containing "sonst noch"). Mirrors the macOS
/// hook's Python <c>last_sentence()</c> (macos/hooks/claude-status-hook.sh) 1:1 — see
/// macos/Tests/hook-tests.sh for the full-pipeline equivalent.
///
/// The rest of the hook decision pipeline (Notification allowlist, trust gate, subagent
/// tracking) is validated by the same table against the real hook process, not in-process
/// here — <see cref="HookRunner.RunCore"/>'s stdin path reads
/// <see cref="Console.OpenStandardInput"/> directly (not <see cref="Console.In"/>), so it
/// isn't in-process-redirectable without an added test seam (follow-up cleanup: move the
/// decision logic into Core/ per CONTRIBUTING.md, then encode the full table here).
/// </summary>
public class HookRunnerTests
{
    [Theory]
    [InlineData("İşlemleri tamamladım. Başka bir şey var mı?", "Başka bir şey var mı?")]
    [InlineData("All done. Is there anything else I can help you with?",
                "Is there anything else I can help you with?")]
    [InlineData("Is there anything in the logs that explains this, or should I drop the table?",
                "Is there anything in the logs that explains this, or should I drop the table?")]
    [InlineData("Soll ich sonst noch die Prod-Config ändern?",
                "Soll ich sonst noch die Prod-Config ändern?")]
    [InlineData("İki yol var. Hangisiyle devam edeyim?", "Hangisiyle devam edeyim?")]
    [InlineData("完了しました。他に何かありますか？", "他に何かありますか？")]
    public void LastSentence_isolates_only_the_final_sentence(string tail, string expected)
        => Assert.Equal(expected, HookRunner.LastSentence(tail));

    // The German row above is the whole point of F1: pure substring-anywhere matching
    // against "sonst noch" (a real courtesy phrase) would wrongly call this a courtesy
    // close. Anchoring to the last sentence's START rejects it because the phrase sits in
    // the middle of a real compound question, not at the sentence's own beginning.
    [Fact]
    public void German_compound_question_does_not_start_with_the_courtesy_phrase()
    {
        string sentence = HookRunner.LastSentence("Soll ich sonst noch die Prod-Config ändern?")
            .ToLowerInvariant();
        Assert.DoesNotContain("sonst noch", sentence.Substring(0, Math.Min(sentence.Length, "sonst noch".Length)));
        Assert.False(sentence.StartsWith("sonst noch"));
    }
}
