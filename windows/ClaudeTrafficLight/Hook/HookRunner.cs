using System.Text;
using System.Text.Json;
using ClaudeTrafficLight.Core;
using ClaudeTrafficLight.Platform;

namespace ClaudeTrafficLight.Hook;

/// <summary>
/// The <c>--hook &lt;state&gt;</c> code path (§3 / §12.1). Claude Code runs this on
/// events and pipes a JSON payload (session_id, cwd, tool_name, …) over stdin.
/// It updates <c>%USERPROFILE%\.claude\status\&lt;session_id&gt;.json</c> and exits.
/// Every step is defensive: a hook must never throw or block Claude Code.
/// </summary>
public static class HookRunner
{
    /// <summary>Entries older than this are pruned from the subagent set (F11) — keep in
    /// sync with StatusStore.staleAfter, so a missed SubagentStop can't wedge yellow forever.</summary>
    private static readonly TimeSpan SubagentStaleAfter = TimeSpan.FromMinutes(30);

    /// <returns>process exit code (always 0 — a failing hook must not break the session).</returns>
    public static int Run(string state)
    {
        try
        {
            RunCore(state);
        }
        catch { /* swallow — never break the host */ }
        return 0;
    }

    private static void RunCore(string state)
    {
        string statusDir = Paths.StatusDir;
        Directory.CreateDirectory(statusDir);

        JsonElement payload = ReadStdinJson();

        string sessionId = GetString(payload, "session_id");
        if (string.IsNullOrEmpty(sessionId)) sessionId = "unknown";
        string safe = Sanitize(sessionId);
        string path = Path.Combine(statusDir, safe + ".json");

        if (state == "end")
        {
            try { File.Delete(path); } catch { /* already gone */ }
            try { File.Delete(path + ".lock"); } catch { /* already gone */ }
            return;
        }

        // Concurrency: with parallel subagents, several hook processes fire at once for
        // the SAME session file. The whole read-modify-write below runs under an exclusive
        // lock, and the temp file is per-writer — a shared ".tmp" name let one process
        // install another's HALF-WRITTEN json (torn write), which the app then couldn't
        // parse (row vanished) and the next hook read as "no previous file" (cwd pin reset).
        using var _lock = AcquireLock(path + ".lock");

        var prev = ReadPrev(path);
        DateTimeOffset now = DateTimeOffset.UtcNow;
        var subagents = PruneSubagents(prev.Subagents, now);

        // --- F11: subagent tracking --------------------------------------------------
        // A background subagent's own Stop paints the shared session green even though
        // the user's actual request is still running; the next tool event flips it back
        // yellow. That reads as flicker to the user, so we track active subagent ids and
        // keep the real Stop yellow while any are still running (see below). subagent-stop
        // never touches color or any other field — it rewrites the file verbatim (via
        // JsonNode, so even fields this build doesn't know about survive) with only the
        // subagent set replaced. Parity: the macOS hook's dict(prev) does the same.
        if (state == "subagent-stop")
        {
            string stopId = GetString(payload, "agent_id");
            if (!string.IsNullOrEmpty(stopId)) subagents.Remove(stopId);
            if (!prev.Exists) return; // nothing on disk to update
            RewriteSubagentsOnly(path, subagents);
            return;
        }

        // subagent-start always repaints yellow regardless of whatever was there before,
        // then falls through the normal pipeline below so project/cwd/platform/trust are
        // (re)derived exactly like any other write.
        if (state == "subagent-start")
        {
            string startId = GetString(payload, "agent_id");
            if (string.IsNullOrEmpty(startId)) startId = $"_anon_{now.ToUnixTimeMilliseconds()}_{Guid.NewGuid():N}";
            subagents[startId] = now.ToUnixTimeSeconds();
            state = "yellow";
        }

        string eventName = GetString(payload, "hook_event_name");

        // The moment a tool that asks the user / waits for approval is about to run
        // (PreToolUse), flip the state to red (Claude is waiting for your input).
        // ONLY on PreToolUse: PostToolUse carries the same tool_name but fires when the
        // user has just ANSWERED — repainting red there kept the light red until the next
        // unrelated event, long after the question was gone.
        string tool = GetString(payload, "tool_name").ToLowerInvariant();
        if (state == "yellow" && eventName == "PreToolUse"
            && (tool.Contains("askuserquestion") || tool.Contains("exitplanmode")))
            state = "red";

        // Plain-text questions (parity with macOS hook): AskUserQuestion goes red via
        // the PreToolUse upgrade above, but Claude often asks in prose and just stops.
        // On Stop, if the last assistant text ends with a question, the user is being
        // asked something → red, not green. Any parse problem → keep green.
        if (state == "green" && eventName == "Stop")
        {
            string tail = LastAssistantText(GetString(payload, "transcript_path")).TrimEnd();
            // markdown/quote closers: backtick, straight/curly double+single quotes,
            // guillemet, CJK bracket closers, fullwidth paren close (F6 — a closing
            // quote right after "?" must not hide the question mark from EndsWith()).
            const string closers = "*_)]}`\"'’»”‘」』）";
            while (tail.Length > 0 && closers.Contains(tail[^1]))
                tail = tail[..^1].TrimEnd();

            if (tail.EndsWith('?') || tail.EndsWith('？'))
            {
                // A trailing "?" alone isn't enough ("...or should I drop the table?" also
                // ends with "?" but is a real blocking question). Anchor the courtesy check
                // to the LAST SENTENCE only (F1): split on real sentence enders, require the
                // courtesy phrase to sit at the START of that sentence, and keep the whole
                // sentence close to the phrase's own length. That accepts "Anything else?" /
                // "Başka bir şey var mı?" but rejects compound questions that merely contain
                // a courtesy-shaped substring in the middle ("Soll ich sonst noch die
                // Prod-Config ändern?").
                string sentence = LastSentence(tail).ToLowerInvariant()
                    .Replace("İ", "i").Replace("̇", "");
                string[] courtesy =
                {
                    // en
                    "anything else", "is there anything", "any other question",
                    "what else can i",
                    // tr
                    "başka bir şey var m", "başka istediğin",
                    "başka bir isteğ", "başka sorunuz",
                    "yardımcı olabileceğim başka",
                    // es
                    "algo más", "alguna otra cosa",
                    // de
                    "noch etwas", "sonst noch",
                    // fr
                    "autre chose",
                    // it
                    "qualcos'altro", "altre domande",
                    // pt
                    "mais alguma coisa", "algo mais",
                    // ru (both yo/e spellings)
                    "что-нибудь ещё", "что-нибудь еще", "что-то ещё", "что-то еще",
                    // ja
                    "他に何か", "ほかに何か",
                    // zh
                    "还有什么", "还需要什么", "其他需要",
                    // ko
                    "더 필요한", "다른 필요한", "더 도와드릴"
                };
                bool matched = courtesy.Any(k => sentence.StartsWith(k) && sentence.Length <= k.Length + 40);
                if (!matched)
                    state = "red";
            }
        }

        // Notification filtering (parity with macOS hook): Notification carries many
        // types; only "a question/approval is waiting for YOU" may go red. The allowlist
        // is inverted on purpose (F2): a future/unknown type, or a Claude Code version
        // where the field never arrives, must NOT be able to paint a false mid-turn red —
        // the cheap direction here is "don't write" (real permission waits already go red
        // via the separate PermissionRequest event).
        if (eventName == "Notification")
        {
            string ntype = GetString(payload, "notification_type").ToLowerInvariant();
            if (ntype is "permission_prompt" or "elicitation_dialog" or "agent_needs_input")
            { /* genuinely waiting on the user → red stands */ }
            else if (ntype == "idle_prompt")
            {
                // mid-turn idle (prev yellow/red) escalates to red; after a completed
                // response (prev green) an idle chat is simply "your turn" — never
                // repaint green → red on idle.
                if (prev.State == "green") return;
            }
            else if (ntype is "elicitation_complete" or "elicitation_response")
            {
                state = "yellow"; // dialog answered → work continues
            }
            else
            {
                return; // unknown or missing type: never repaint
            }
        }

        // F11 (cont.): a real Stop while subagents are still active stays yellow — but
        // only when no question was detected above (a question always outranks it).
        if (state == "green" && eventName == "Stop" && subagents.Count > 0)
            state = "yellow";

        // Only accept the three real states; anything else is ignored (no file written).
        if (state is not ("red" or "yellow" or "green")) return;

        // The session's identity is pinned to where it STARTED. Claude Code's payload `cwd`
        // follows the session's live working directory — the agent's shell often `cd`s into
        // a subfolder mid-task, and without pinning the row gets renamed and a click opens
        // that subfolder in a NEW editor window instead of focusing the window the session
        // actually lives in. First non-empty cwd wins; later values are ignored.
        string cwd = prev.Cwd is { Length: > 0 } ? prev.Cwd : GetString(payload, "cwd");
        string project = string.IsNullOrEmpty(cwd) ? "?" : LastPathComponent(cwd);

        var ancestry = ProcessTree.Detect();

        // Trust gate (F3 / F5 / F9). Red must mean "a question is visible in a chat the
        // user is actually in". When an IDE reloads it silently resumes old sessions
        // headlessly; the resumed process immediately re-fires the pending-question
        // Notification, which would paint a red the user can never find or answer.
        //
        // `trusted` is granted ONLY by an event that actually proves the user is present:
        //   - hook_event_name == "UserPromptSubmit" (the user just typed), or
        //   - the session is attached to a visible console (F9: Windows has no tty concept;
        //     ancestry.Platform == "terminal" is the closest signal, but it under-counts a
        //     VS Code integrated-terminal session (classified "vscode", not "terminal") —
        //     that gap is intentionally covered by UserPromptSubmit trust instead of a
        //     native console-attachment probe, since a live panel session earns trust on its
        //     first user message either way), or
        //   - platform == "desktop" (the Desktop app is always an open, visible window —
        //     unlike vscode/cursor, no ghost-resume-on-reload failure mode is proven here), or
        //   - the previous write under the SAME pid was already trusted (inherited).
        // Anything else carries the previous trust forward unchanged (default false, so a
        // brand-new pid starts untrusted until one of the proofs above fires). An untrusted
        // red is written as green: nothing the user can see or act on is pending.
        bool hasVisibleConsole = ancestry.Platform == "terminal";
        bool prevPidMatches = ancestry.SessionPid > 0 && prev.Pid == ancestry.SessionPid;
        bool inherited = prevPidMatches && prev.Trusted;

        bool trusted = eventName == "UserPromptSubmit" || hasVisibleConsole
                       || ancestry.Platform == "desktop" || inherited;

        if (state == "red" && !trusted) state = "green";

        var data = new Dictionary<string, object>
        {
            ["state"] = state,
            ["project"] = project,
            ["cwd"] = cwd,
            ["ts"] = now.ToUnixTimeSeconds(),
            ["session_pid"] = ancestry.SessionPid,
            ["platform"] = ancestry.Platform,
            ["app_path"] = ancestry.HostPath,
            ["trusted"] = trusted,
            ["subagents"] = subagents
        };

        WriteAtomic(path, data);
    }

    /// <summary>Sentence containing the last character of <paramref name="text"/>. Scans
    /// backward from the character BEFORE the last one (the last char is the question
    /// mark itself, not a sentence boundary) for a sentence-ending delimiter.</summary>
    internal static string LastSentence(string text)
    {
        const string enders = ".!?？。\n";
        int start = 0;
        for (int i = text.Length - 2; i >= 0; i--)
        {
            if (enders.Contains(text[i])) { start = i + 1; break; }
        }
        return text[start..].Trim();
    }

    /// <summary>Drops subagent entries older than <see cref="SubagentStaleAfter"/> so a
    /// missed SubagentStop can't wedge the light yellow forever (F11 drift safety).</summary>
    private static Dictionary<string, double> PruneSubagents(Dictionary<string, double> raw, DateTimeOffset now)
    {
        double nowSeconds = now.ToUnixTimeSeconds();
        var result = new Dictionary<string, double>();
        foreach (var (id, ts) in raw)
            if (nowSeconds - ts <= SubagentStaleAfter.TotalSeconds)
                result[id] = ts;
        return result;
    }

    /// <summary>
    /// subagent-stop's write path: reload the file as a mutable JsonNode, replace ONLY the
    /// "subagents" key, and write it back — every other field (including ones a newer
    /// format version added that this build doesn't know about) survives verbatim.
    /// </summary>
    private static void RewriteSubagentsOnly(string path, Dictionary<string, double> subagents)
    {
        System.Text.Json.Nodes.JsonObject root;
        try
        {
            root = System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(path)) as System.Text.Json.Nodes.JsonObject
                   ?? new System.Text.Json.Nodes.JsonObject();
        }
        catch
        {
            return; // vanished/corrupt between ReadPrev and now — nothing sane to update
        }
        var sa = new System.Text.Json.Nodes.JsonObject();
        foreach (var (id, ts) in subagents) sa[id] = ts;
        root["subagents"] = sa;

        string tmp = $"{path}.tmp.{Environment.ProcessId}";
        File.WriteAllText(tmp, root.ToJsonString(), new UTF8Encoding(false));
        ReplaceWithRetry(tmp, path);
    }

    /// <summary>
    /// Previous status-file record. Old-format files without a "trusted" key default to
    /// UNTRUSTED (F5 — the old "default true" was dead/backwards: an old-format file with
    /// no pid match never inherits anyway, so the permissive default only ever hurt).
    /// Missing/unreadable file → empty record (no state, pid 0, untrusted, no subagents).
    /// </summary>
    private readonly record struct PrevRecord(
        bool Exists, string State, int Pid, bool Trusted, string Cwd,
        Dictionary<string, double> Subagents);

    private static PrevRecord ReadPrev(string path)
    {
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(path));
            var root = doc.RootElement;
            string state = GetString(root, "state");
            int pid = root.TryGetProperty("session_pid", out var p) && p.TryGetInt32(out var v) ? v : 0;
            bool trusted = root.TryGetProperty("trusted", out var t) && t.ValueKind == JsonValueKind.True;
            string cwd = GetString(root, "cwd");
            var subagents = new Dictionary<string, double>();
            if (root.TryGetProperty("subagents", out var sa) && sa.ValueKind == JsonValueKind.Object)
                foreach (var prop in sa.EnumerateObject())
                    if (prop.Value.TryGetDouble(out var sv)) subagents[prop.Name] = sv;
            return new PrevRecord(true, state, pid, trusted, cwd, subagents);
        }
        catch
        {
            return new PrevRecord(false, "", 0, false, "", new Dictionary<string, double>());
        }
    }

    /// <summary>
    /// Text of the last assistant message in the transcript (JSONL, append-only —
    /// reading the tail is enough). Empty string on any problem.
    /// </summary>
    private static string LastAssistantText(string transcriptPath)
    {
        try
        {
            if (string.IsNullOrEmpty(transcriptPath) || !File.Exists(transcriptPath)) return "";
            using var fs = File.OpenRead(transcriptPath);
            long start = Math.Max(0, fs.Length - 262144);
            fs.Seek(start, SeekOrigin.Begin);
            using var reader = new StreamReader(fs, Encoding.UTF8);
            string text = "";
            string? line;
            while ((line = reader.ReadLine()) != null)
            {
                try
                {
                    using var doc = JsonDocument.Parse(line);
                    var root = doc.RootElement;
                    if (GetString(root, "type") != "assistant") continue;
                    if (!root.TryGetProperty("message", out var msg)
                        || !msg.TryGetProperty("content", out var content)
                        || content.ValueKind != JsonValueKind.Array) continue;
                    var parts = new List<string>();
                    foreach (var block in content.EnumerateArray())
                        if (GetString(block, "type") == "text")
                            parts.Add(GetString(block, "text"));
                    if (parts.Any(p => p.Trim().Length > 0))
                        text = string.Join("\n", parts); // keep overwriting → last one wins
                }
                catch { /* partial/invalid line — skip */ }
            }
            return text;
        }
        catch
        {
            return "";
        }
    }

    private static JsonElement ReadStdinJson()
    {
        try
        {
            using var stdin = Console.OpenStandardInput();
            using var reader = new StreamReader(stdin, Encoding.UTF8);
            string text = reader.ReadToEnd();
            if (string.IsNullOrWhiteSpace(text)) return default;
            using var doc = JsonDocument.Parse(text);
            return doc.RootElement.Clone();
        }
        catch
        {
            return default; // unreadable / not JSON → treat as empty object
        }
    }

    /// <summary>
    /// Exclusive cross-process lock via the .lock file (FileShare.None). Short retry loop —
    /// writers hold it for well under a millisecond; if it can't be had within ~2s something
    /// is wedged and we proceed unlocked rather than stall Claude Code (worst case is the
    /// pre-lock behavior). Never returns null-with-throw: any failure → proceed unlocked.
    /// </summary>
    private static IDisposable? AcquireLock(string lockPath)
    {
        for (int i = 0; i < 200; i++)
        {
            try
            {
                return new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            }
            catch (IOException) { Thread.Sleep(10); }
            catch { return null; }
        }
        return null;
    }

    private static void WriteAtomic(string path, Dictionary<string, object> data)
    {
        // Per-writer temp name: a shared ".tmp" lets concurrent hooks install each
        // other's half-written files (see the lock comment in RunCore).
        string tmp = $"{path}.tmp.{Environment.ProcessId}";
        var json = JsonSerializer.Serialize(data);
        File.WriteAllText(tmp, json, new UTF8Encoding(false));
        ReplaceWithRetry(tmp, path);
    }

    /// <summary>
    /// Atomic replace so the reader never sees a half-written file. Unlike POSIX rename,
    /// Windows ReplaceFile fails with a sharing violation if the tray/widget poll happens
    /// to be reading the destination at that instant — without the retry the write (a
    /// whole state transition) would be silently dropped by the hook's catch-all.
    /// </summary>
    private static void ReplaceWithRetry(string tmp, string path)
    {
        for (int i = 0; ; i++)
        {
            try
            {
                if (File.Exists(path)) File.Replace(tmp, path, null);
                else File.Move(tmp, path);
                return;
            }
            catch (IOException) when (i < 20)
            {
                Thread.Sleep(10);
            }
        }
    }

    private static string GetString(JsonElement obj, string key)
        => obj.ValueKind == JsonValueKind.Object
           && obj.TryGetProperty(key, out var v)
           && v.ValueKind == JsonValueKind.String
            ? v.GetString() ?? "" : "";

    private static string Sanitize(string id)
    {
        var sb = new StringBuilder(id.Length);
        foreach (char c in id)
            if (char.IsLetterOrDigit(c) || c is '-' or '_') sb.Append(c);
        return sb.Length > 0 ? sb.ToString() : "unknown";
    }

    private static string LastPathComponent(string p)
    {
        p = p.TrimEnd('/', '\\');
        int i = p.LastIndexOfAny(new[] { '/', '\\' });
        return i >= 0 ? p[(i + 1)..] : p;
    }
}
