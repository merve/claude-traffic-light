using System.Diagnostics;
using System.Text.Json;
using ClaudeTrafficLight.Core;
using Xunit;

namespace ClaudeTrafficLight.Tests;

/// <summary>
/// Reading, filtering, sorting and aggregation of the <c>~/.claude/status/*.json</c>
/// files the widget and bar both render. Windows port of the macOS StatusStoreTests.
/// Each test gets an isolated temp status directory.
/// </summary>
public sealed class StatusStoreTests : IDisposable
{
    private readonly string _dir;
    private readonly StatusStore _store;

    public StatusStoreTests()
    {
        _dir = Path.Combine(Path.GetTempPath(), "claudestatus-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_dir);
        _store = new StatusStore(_dir);
    }

    public void Dispose()
    {
        try { Directory.Delete(_dir, recursive: true); } catch { /* best effort */ }
    }

    // MARK: - helpers

    private static int LivePid => Environment.ProcessId;

    /// <summary>A pid guaranteed to be dead: start a trivial process and wait for it to exit.</summary>
    private static int DeadPid()
    {
        using var p = Process.Start(new ProcessStartInfo
        {
            FileName = "cmd.exe",
            Arguments = "/c exit",
            CreateNoWindow = true,
            UseShellExecute = false
        })!;
        p.WaitForExit();
        return p.Id;
    }

    private string WriteStatus(string id, string state, string project = "proj", string cwd = "/tmp/proj",
                               long? ts = null, int? pid = null, string? platform = null, string? appPath = null)
    {
        var obj = new Dictionary<string, object>
        {
            ["state"] = state,
            ["project"] = project,
            ["cwd"] = cwd,
            ["ts"] = ts ?? DateTimeOffset.UtcNow.ToUnixTimeSeconds()
        };
        if (pid is not null) obj["session_pid"] = pid.Value;
        if (platform is not null) obj["platform"] = platform;
        if (appPath is not null) obj["app_path"] = appPath;

        string path = Path.Combine(_dir, id + ".json");
        File.WriteAllText(path, JsonSerializer.Serialize(obj));
        return path;
    }

    // MARK: - Load(): basics

    [Fact]
    public void Load_empty_directory_returns_none()
        => Assert.Empty(_store.Load());

    [Fact]
    public void Load_missing_directory_returns_none()
        => Assert.Empty(new StatusStore(Path.Combine(_dir, "nope")).Load());

    [Fact]
    public void Load_parses_all_fields()
    {
        WriteStatus("sess1", "yellow", project: "myproj", cwd: "/tmp/myproj", pid: LivePid, platform: "vscode");
        var s = Assert.Single(_store.Load());
        Assert.Equal("sess1", s.SessionId);
        Assert.Equal(State.Yellow, s.State);
        Assert.Equal("myproj", s.Project);
        Assert.Equal("/tmp/myproj", s.Cwd);
        Assert.Equal("vscode", s.Platform);
    }

    [Fact]
    public void Project_falls_back_to_last_component_of_cwd()
    {
        // No "project" field → last path component of cwd is used.
        string path = Path.Combine(_dir, "sess2.json");
        var obj = new Dictionary<string, object>
        {
            ["state"] = "green",
            ["cwd"] = @"C:\a\b\coolproject",
            ["ts"] = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
            ["session_pid"] = LivePid
        };
        File.WriteAllText(path, JsonSerializer.Serialize(obj));
        Assert.Equal("coolproject", _store.Load().Single().Project);
    }

    [Fact]
    public void Platform_defaults_to_unknown()
    {
        WriteStatus("sess3", "green", pid: LivePid); // no platform field
        Assert.Equal("unknown", _store.Load().Single().Platform);
    }

    [Fact]
    public void AppPath_is_parsed_and_defaults_to_empty()
    {
        WriteStatus("withapp", "yellow", pid: LivePid, platform: "terminal", appPath: @"C:\Windows\System32\wt.exe");
        Assert.Equal(@"C:\Windows\System32\wt.exe", _store.Load().Single(s => s.SessionId == "withapp").AppPath);

        WriteStatus("noapp", "yellow", pid: LivePid); // no app_path field
        Assert.Equal("", _store.Load().Single(s => s.SessionId == "noapp").AppPath);
    }

    [Fact]
    public void Invalid_JSON_is_skipped()
    {
        File.WriteAllText(Path.Combine(_dir, "bad.json"), "{ broken json");
        WriteStatus("ok", "red", pid: LivePid);
        Assert.Single(_store.Load()); // only the valid one
    }

    [Fact]
    public void Unknown_state_is_skipped()
    {
        WriteStatus("weird", "purple", pid: LivePid);
        Assert.Empty(_store.Load());
    }

    [Fact]
    public void Non_JSON_files_are_ignored()
    {
        File.WriteAllText(Path.Combine(_dir, "note.txt"), "hello");
        WriteStatus("ok", "yellow", pid: LivePid);
        Assert.Single(_store.Load());
    }

    // MARK: - pid liveness

    [Fact]
    public void Dead_pid_session_is_dropped_and_its_file_deleted()
    {
        string path = WriteStatus("deadone", "yellow", pid: DeadPid());
        Assert.Empty(_store.Load());
        Assert.False(File.Exists(path), "stale file should be deleted");
    }

    [Fact]
    public void Live_pid_session_is_kept()
    {
        WriteStatus("liveone", "yellow", pid: LivePid);
        Assert.Single(_store.Load());
    }

    [Fact]
    public void IsAlive_reflects_process_liveness()
    {
        Assert.True(Platform.ProcessInfo.IsAlive(LivePid));
        Assert.True(Platform.ProcessInfo.IsAlive(0));   // <= 0 → treated as alive
        Assert.False(Platform.ProcessInfo.IsAlive(DeadPid()));
    }

    // MARK: - old format (no pid) staleness

    [Fact]
    public void Old_format_fresh_record_is_kept()
    {
        WriteStatus("fresh", "yellow", ts: DateTimeOffset.UtcNow.ToUnixTimeSeconds()); // no pid
        Assert.Single(_store.Load());
    }

    [Fact]
    public void Old_format_stale_record_is_dropped_and_deleted()
    {
        long old = DateTimeOffset.UtcNow.ToUnixTimeSeconds() - (long)StatusStore.StaleAfter.TotalSeconds - 60;
        string path = WriteStatus("stale", "yellow", ts: old); // no pid
        Assert.Empty(_store.Load());
        Assert.False(File.Exists(path));
    }

    // MARK: - sorting & aggregate

    [Fact]
    public void Sorting_is_red_first_then_newest()
    {
        long now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        WriteStatus("g", "green", ts: now, pid: LivePid);
        WriteStatus("y", "yellow", ts: now, pid: LivePid);
        WriteStatus("r_old", "red", ts: now - 100, pid: LivePid);
        WriteStatus("r_new", "red", ts: now, pid: LivePid);

        var ordered = _store.Load().Select(s => s.SessionId).ToArray();
        Assert.Equal(new[] { "r_new", "r_old", "y", "g" }, ordered);
    }

    [Fact]
    public void Aggregate_picks_the_highest_priority_state()
    {
        static SessionStatus Mk(State st) =>
            new("x", st, "p", "/", DateTimeOffset.UtcNow, "unknown", "", 0);

        var store = new StatusStore(_dir);
        Assert.Equal(State.Red, store.Aggregate(new[] { Mk(State.Green), Mk(State.Yellow), Mk(State.Red) }));
        Assert.Equal(State.Yellow, store.Aggregate(new[] { Mk(State.Green), Mk(State.Yellow) }));
        Assert.Equal(State.Green, store.Aggregate(new[] { Mk(State.Green) }));
        Assert.Equal(State.Green, store.Aggregate(Array.Empty<SessionStatus>())); // idle when none
    }

    // MARK: - State

    [Fact]
    public void State_priority_order_is_red_over_yellow_over_green()
    {
        Assert.True(State.Red.Priority() > State.Yellow.Priority());
        Assert.True(State.Yellow.Priority() > State.Green.Priority());
    }

    [Fact]
    public void State_emoji_mapping()
    {
        Assert.Equal("🔴", State.Red.Emoji());
        Assert.Equal("🟡", State.Yellow.Emoji());
        Assert.Equal("🟢", State.Green.Emoji());
    }
}
