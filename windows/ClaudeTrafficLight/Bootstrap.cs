using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using ClaudeTrafficLight.Core;
using Microsoft.Win32;

namespace ClaudeTrafficLight;

/// <summary>
/// First-run setup / teardown (§10): create the status dir, merge our hook groups
/// into <c>~/.claude/settings.json</c> (idempotent), and register autostart.
/// A single exe is both the tray app and the hook (§12.1), so no separate script.
/// </summary>
public static class Bootstrap
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValueName = "ClaudeTrafficLight";
    public const string HookMarker = "ClaudeTrafficLight"; // exe basename → identifies our commands

    /// <summary>
    /// (Claude Code event, matcher, hook state) → the settings.json groups we own. Must
    /// stay event-for-event in sync with the macOS snippet (macos/hooks/settings-snippet.json)
    /// — CONTRIBUTING.md "keep both platforms in sync"; enforced by BootstrapEventsTests.
    /// </summary>
    internal static readonly (string Event, string? Matcher, string State)[] Events =
    {
        ("UserPromptSubmit", null, "yellow"),
        ("PreToolUse",       "*",  "yellow"),
        ("PermissionRequest", null, "red"),
        ("PostToolUse",      "*",  "yellow"),
        ("PostToolUseFailure", "*", "yellow"),
        ("PermissionDenied", null, "yellow"),
        ("Notification",     null, "red"),
        ("SubagentStart",    null, "subagent-start"),
        ("SubagentStop",     null, "subagent-stop"),
        ("Stop",             null, "green"),
        ("StopFailure",      null, "green"),
        ("SessionEnd",       null, "end"),
    };

    public static string ExePath => Environment.ProcessPath
        ?? Process.GetCurrentProcess().MainModule?.FileName
        ?? "ClaudeTrafficLight.exe";

    /// <summary>Run all install steps. Safe to call on every launch (idempotent).</summary>
    public static void Install()
    {
        Directory.CreateDirectory(Paths.StatusDir);
        MergeSettings();
        EnableAutostart();
    }

    public static void Uninstall()
    {
        RemoveSettings();
        DisableAutostart();
    }

    // MARK: - settings.json

    private static string HookCommand(string state) => $"\"{ExePath}\" --hook {state}";

    public static void MergeSettings()
    {
        JsonObject root = ReadSettings();
        var hooks = root["hooks"] as JsonObject;
        if (hooks is null) { hooks = new JsonObject(); root["hooks"] = hooks; }

        foreach (var (evt, matcher, state) in Events)
        {
            var arr = hooks[evt] as JsonArray;
            if (arr is null) { arr = new JsonArray(); hooks[evt] = arr; }

            // Idempotent: drop any prior group of ours for this event, then add fresh.
            RemoveOurGroups(arr);

            var group = new JsonObject();
            if (matcher is not null) group["matcher"] = matcher;
            group["hooks"] = new JsonArray(new JsonObject
            {
                ["type"] = "command",
                ["command"] = HookCommand(state)
            });
            arr.Add(group);
        }

        WriteSettings(root);
    }

    private static void RemoveSettings()
    {
        if (!File.Exists(Paths.SettingsFile)) return;
        JsonObject root = ReadSettings();
        if (root["hooks"] is not JsonObject hooks) return;

        foreach (var (evt, _, _) in Events)
        {
            if (hooks[evt] is not JsonArray arr) continue;
            RemoveOurGroups(arr);
        }
        WriteSettings(root);
    }

    /// <summary>Remove hook groups whose command references our exe (survives path changes / reinstalls).</summary>
    private static void RemoveOurGroups(JsonArray groups)
    {
        for (int i = groups.Count - 1; i >= 0; i--)
        {
            if (groups[i] is not JsonObject grp) continue;
            if (grp["hooks"] is not JsonArray inner) continue;
            bool ours = inner.Any(h =>
                h is JsonObject ho
                && ho["command"]?.GetValue<string>() is string cmd
                && cmd.Contains("--hook")
                && cmd.Contains(HookMarker, StringComparison.OrdinalIgnoreCase));
            if (ours) groups.RemoveAt(i);
        }
    }

    private static JsonObject ReadSettings()
    {
        try
        {
            if (File.Exists(Paths.SettingsFile))
            {
                var node = JsonNode.Parse(File.ReadAllText(Paths.SettingsFile));
                if (node is JsonObject obj) return obj;
            }
        }
        catch { /* corrupt → start fresh but keep a backup below */ }
        return new JsonObject();
    }

    private static void WriteSettings(JsonObject root)
    {
        Directory.CreateDirectory(Paths.ClaudeDir);
        // Back up the existing file before overwriting.
        if (File.Exists(Paths.SettingsFile))
        {
            try { File.Copy(Paths.SettingsFile, Paths.SettingsFile + ".bak", overwrite: true); } catch { }
        }
        var opts = new JsonSerializerOptions { WriteIndented = true };
        string json = root.ToJsonString(opts);
        string tmp = Paths.SettingsFile + ".tmp";
        File.WriteAllText(tmp, json);
        if (File.Exists(Paths.SettingsFile)) File.Replace(tmp, Paths.SettingsFile, null);
        else File.Move(tmp, Paths.SettingsFile);
    }

    // MARK: - autostart (HKCU Run key)

    public static void EnableAutostart()
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath);
            key?.SetValue(RunValueName, $"\"{ExePath}\"");
        }
        catch { /* non-fatal */ }
    }

    public static void DisableAutostart()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true);
            key?.DeleteValue(RunValueName, throwOnMissingValue: false);
        }
        catch { /* non-fatal */ }
    }

    public static bool IsAutostartEnabled()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath);
            return key?.GetValue(RunValueName) is not null;
        }
        catch { return false; }
    }
}
