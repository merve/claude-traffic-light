using System.Text.Json;

namespace ClaudeTrafficLight.Core;

/// <summary>Traffic-light state of a single Claude session.</summary>
public enum State
{
    Red,    // asking a question / waiting for permission — waiting on you
    Yellow, // working
    Green   // finished, your turn
}

public static class StateExtensions
{
    /// <summary>Priority: higher = needs more attention. Used when aggregating.</summary>
    public static int Priority(this State s) => s switch
    {
        State.Red => 3,
        State.Yellow => 2,
        State.Green => 1,
        _ => 0
    };

    public static string Emoji(this State s) => s switch
    {
        State.Red => "🔴",
        State.Yellow => "🟡",
        State.Green => "🟢",
        _ => ""
    };

    /// <summary>Parse the JSON "state" string; null if invalid.</summary>
    public static State? Parse(string? raw) => raw switch
    {
        "red" => State.Red,
        "yellow" => State.Yellow,
        "green" => State.Green,
        _ => null
    };
}

/// <summary>Status record of a single Claude session (maps to one status file).</summary>
public sealed record SessionStatus(
    string SessionId,
    State State,
    string Project,
    string Cwd,
    DateTimeOffset Ts,
    string Platform,   // "desktop" | "vscode" | "cursor" | "terminal" | "unknown"
    string AppPath,    // path of the hosting app (if any) — used to focus it on click
    int Pid);          // the running `claude` process (0 if unknown) — used to end the session

/// <summary>Reads and aggregates the <c>%USERPROFILE%\.claude\status\*.json</c> files.</summary>
public sealed class StatusStore
{
    /// <summary>Records older than this are considered stale (stuck session) and hidden.</summary>
    public static readonly TimeSpan StaleAfter = TimeSpan.FromMinutes(30);

    public string StatusDir { get; }

    /// <summary>When <paramref name="statusDir"/> is null, <c>%USERPROFILE%\.claude\status</c> is used.</summary>
    public StatusStore(string? statusDir = null)
    {
        StatusDir = statusDir ?? Paths.StatusDir;
    }

    /// <summary>Reads all valid (non-stale, live) sessions in the directory.</summary>
    public List<SessionStatus> Load()
    {
        var results = new List<SessionStatus>();
        string[] files;
        try
        {
            files = Directory.GetFiles(StatusDir, "*.json");
        }
        catch
        {
            return results;
        }

        var now = DateTimeOffset.UtcNow;

        foreach (var path in files)
        {
            JsonElement obj;
            try
            {
                obj = ReadJsonWithRetry(path);
            }
            catch
            {
                continue; // unreadable / invalid JSON — skip (row reappears next poll)
            }

            if (obj.ValueKind != JsonValueKind.Object) continue;

            var state = StateExtensions.Parse(GetString(obj, "state"));
            if (state is null) continue;

            var ts = ParseTs(obj);

            // Liveness: if the session's claude process is gone (chat closed), drop
            // it and delete the now-useless file (keep disk clean).
            int pid = GetInt(obj, "session_pid");
            if (pid > 0)
            {
                if (!Platform.ProcessInfo.IsAlive(pid))
                {
                    TryDelete(path);
                    continue;
                }
            }
            else
            {
                // Old format (no pid) → fall back to time-based staleness check.
                if (now - ts > StaleAfter)
                {
                    TryDelete(path);
                    continue;
                }
            }

            string cwd = GetString(obj, "cwd") ?? "";
            string project = GetString(obj, "project")
                ?? (string.IsNullOrEmpty(cwd) ? "?" : LastPathComponent(cwd));
            string sessionId = Path.GetFileNameWithoutExtension(path);
            string platform = GetString(obj, "platform") ?? "unknown";
            string appPath = GetString(obj, "app_path") ?? "";

            results.Add(new SessionStatus(sessionId, state.Value, project, cwd, ts, platform, appPath, pid));
        }

        // Sort by priority (red on top); ties broken by newest first.
        results.Sort((a, b) =>
        {
            if (a.State.Priority() != b.State.Priority())
                return b.State.Priority().CompareTo(a.State.Priority());
            return b.Ts.CompareTo(a.Ts);
        });
        return results;
    }

    /// <summary>Aggregate state shown on the bar icon. Green (idle) when there are no sessions.</summary>
    public State Aggregate(IReadOnlyList<SessionStatus> sessions)
    {
        var best = State.Green;
        bool any = false;
        foreach (var s in sessions)
        {
            if (!any || s.State.Priority() > best.Priority()) { best = s.State; any = true; }
        }
        return any ? best : State.Green;
    }

    // MARK: - helpers

    private static string? GetString(JsonElement obj, string key)
        => obj.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    private static int GetInt(JsonElement obj, string key)
    {
        if (!obj.TryGetProperty(key, out var v)) return 0;
        return v.ValueKind switch
        {
            JsonValueKind.Number => v.TryGetInt32(out var n) ? n : 0,
            JsonValueKind.String => int.TryParse(v.GetString(), out var n) ? n : 0,
            _ => 0
        };
    }

    private static DateTimeOffset ParseTs(JsonElement obj)
    {
        double secs = 0;
        if (obj.TryGetProperty("ts", out var v))
        {
            if (v.ValueKind == JsonValueKind.Number && v.TryGetDouble(out var d)) secs = d;
            else if (v.ValueKind == JsonValueKind.String && double.TryParse(v.GetString(), out var ds)) secs = ds;
        }
        return DateTimeOffset.FromUnixTimeSeconds((long)secs);
    }

    private static string LastPathComponent(string p)
    {
        p = p.TrimEnd('/', '\\');
        int i = p.LastIndexOfAny(new[] { '/', '\\' });
        return i >= 0 ? p[(i + 1)..] : p;
    }

    /// <summary>
    /// Reads and parses a status file, retrying once after a short beat on IO errors:
    /// the hook's ReplaceFile can transiently lock the file, and skipping it would make
    /// the session row blink out of the list for a whole poll cycle.
    /// </summary>
    private static JsonElement ReadJsonWithRetry(string path)
    {
        for (int i = 0; ; i++)
        {
            try
            {
                using var doc = JsonDocument.Parse(File.ReadAllText(path));
                return doc.RootElement.Clone();
            }
            catch (IOException) when (i < 1)
            {
                Thread.Sleep(15);
            }
        }
    }

    /// <summary>Deletes a dead session's status file together with its hook-side
    /// <c>.lock</c> companion (the hook serializes concurrent writers through it;
    /// when the session dies without a SessionEnd, only we ever clean that up).</summary>
    private static void TryDelete(string path)
    {
        try { File.Delete(path); } catch { /* ignore */ }
        try { File.Delete(path + ".lock"); } catch { /* ignore */ }
    }
}
