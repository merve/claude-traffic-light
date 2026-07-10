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

        // The moment a tool that asks the user / waits for approval is about to run,
        // flip the state to red (Claude is waiting for your input).
        string tool = GetString(payload, "tool_name").ToLowerInvariant();
        if (state == "yellow" && (tool.Contains("askuserquestion") || tool.Contains("exitplanmode")))
            state = "red";

        if (state == "end")
        {
            try { File.Delete(path); } catch { /* already gone */ }
            return;
        }

        // Only accept the three real states; anything else is ignored (no file written).
        if (state is not ("red" or "yellow" or "green")) return;

        string cwd = GetString(payload, "cwd");
        string project = string.IsNullOrEmpty(cwd) ? "?" : LastPathComponent(cwd);

        var ancestry = ProcessTree.Detect();

        var data = new Dictionary<string, object>
        {
            ["state"] = state,
            ["project"] = project,
            ["cwd"] = cwd,
            ["ts"] = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
            ["session_pid"] = ancestry.SessionPid,
            ["platform"] = ancestry.Platform,
            ["app_path"] = ancestry.HostPath
        };

        WriteAtomic(path, data);
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

    private static void WriteAtomic(string path, Dictionary<string, object> data)
    {
        string tmp = path + ".tmp";
        var json = JsonSerializer.Serialize(data);
        File.WriteAllText(tmp, json, new UTF8Encoding(false));
        // Atomic replace so the reader never sees a half-written file.
        if (File.Exists(path))
            File.Replace(tmp, path, null);
        else
            File.Move(tmp, path);
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
