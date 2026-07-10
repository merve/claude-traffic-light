using System.Diagnostics;
using System.Text;

namespace ClaudeTrafficLight.Platform;

/// <summary>
/// Walks the process ancestry (via a single Toolhelp snapshot) to determine which
/// environment a Claude Code session runs in, and which pid is the `claude`
/// process. Mirrors the macOS hook's <c>ps</c> chain walk (§3.3 / §12.2): it builds
/// the chain of full command paths and pattern-matches them, so editor/desktop
/// markers win over the shell (cmd/powershell) or console host that merely runs the hook.
/// Everything is wrapped so the hook never throws — worst case is (unknown, 0).
/// </summary>
public static class ProcessTree
{
    public sealed record Ancestry(string Platform, int SessionPid, string HostPath);

    private const int MaxDepth = 10;

    public static Ancestry Detect()
    {
        try
        {
            var (parents, exeNames) = Snapshot();
            int self = Environment.ProcessId;

            // Build the chain (pid, baseExe, fullPath) from our parent upward.
            var chain = new List<(int pid, string exe, string path)>();
            int cur = parents.TryGetValue(self, out var p) ? p : 0;
            int depth = 0;
            while (cur > 1 && depth < MaxDepth)
            {
                string exe = exeNames.TryGetValue(cur, out var e) ? e : "";
                string path = ResolvePath(cur);
                chain.Add((cur, exe, path));
                cur = parents.TryGetValue(cur, out var pp) ? pp : 0;
                depth++;
            }

            string platform = DetectPlatform(chain, out string hostPath);
            int sessionPid = DetectSessionPid(chain);
            return new Ancestry(platform, sessionPid, hostPath);
        }
        catch
        {
            return new Ancestry("unknown", 0, "");
        }
    }

    /// <summary>
    /// Priority-ordered detection: editor / desktop markers take precedence over the
    /// terminal host, because a shell (cmd/powershell) or conhost often sits between
    /// the hook and the real host and must not be mistaken for a terminal session.
    /// </summary>
    private static string DetectPlatform(List<(int pid, string exe, string path)> chain, out string hostPath)
    {
        hostPath = "";
        // One lowercased blob of the whole chain (full paths + base names), like the Mac chain string.
        var sb = new StringBuilder();
        foreach (var (_, exe, path) in chain)
            sb.Append('|').Append((string.IsNullOrEmpty(path) ? exe : path).ToLowerInvariant());
        string blob = sb.ToString();

        // 1) VS Code — the claude-code extension binary or Code.exe anywhere in the chain.
        if (blob.Contains(@".vscode\extensions\anthropic.claude-code")
            || blob.Contains("/.vscode/extensions/anthropic.claude-code")
            || ContainsExe(chain, "code.exe"))
        {
            hostPath = FindPath(chain, "code.exe") ?? hostPath;
            return "vscode";
        }

        // 2) Cursor.
        if (blob.Contains(@".cursor\extensions\anthropic.claude-code")
            || blob.Contains("/.cursor/extensions/anthropic.claude-code")
            || ContainsExe(chain, "cursor.exe"))
        {
            hostPath = FindPath(chain, "cursor.exe") ?? hostPath;
            return "cursor";
        }

        // 3) Claude desktop app — identified by PATH (its install dir), not the bare
        //    "claude.exe" name (the CLI native binary is also called claude.exe).
        if (blob.Contains(@"\anthropicclaude\") || blob.Contains(@"\programs\claude\")
            || blob.Contains("/anthropicclaude/"))
        {
            hostPath = FindPathContaining(chain, "anthropicclaude") ?? FindPathContaining(chain, @"programs\claude") ?? hostPath;
            return "desktop";
        }

        // 4) Terminal host windows (NOT the shell that runs the hook).
        string[] terminals =
        {
            "windowsterminal.exe", "wt.exe", "conhost.exe", "openconsole.exe",
            "alacritty.exe", "wezterm.exe", "wezterm-gui.exe", "kitty.exe",
            "hyper.exe", "mintty.exe", "tabby.exe"
        };
        foreach (var t in terminals)
        {
            if (ContainsExe(chain, t))
            {
                hostPath = FindPath(chain, t) ?? hostPath;
                return "terminal";
            }
        }

        return "unknown";
    }

    /// <summary>
    /// Ordered ancestor pids of <paramref name="pid"/>, nearest first (parent, grandparent, …).
    /// Used to focus a terminal session's window: the claude CLI (node/claude) is a console
    /// process with no window of its own — the terminal window belongs to an ancestor. Never throws.
    /// </summary>
    public static IReadOnlyList<int> AncestorPids(int pid, bool includeSelf = false)
    {
        var result = new List<int>();
        try
        {
            var (parents, _) = Snapshot();
            int cur = includeSelf ? pid : (parents.TryGetValue(pid, out var p0) ? p0 : 0);
            int depth = 0;
            while (cur > 1 && depth < MaxDepth)
            {
                result.Add(cur);
                cur = parents.TryGetValue(cur, out var pp) ? pp : 0;
                depth++;
            }
        }
        catch { /* best effort — an empty list just means "no window to focus" */ }
        return result;
    }

    /// <summary>session_pid = first node.exe / claude.exe ancestor (the CLI process); else direct parent.</summary>
    private static int DetectSessionPid(List<(int pid, string exe, string path)> chain)
    {
        foreach (var (pid, exe, _) in chain)
        {
            if (exe.Equals("node.exe", StringComparison.OrdinalIgnoreCase)
                || exe.Equals("claude.exe", StringComparison.OrdinalIgnoreCase))
                return pid;
        }
        return chain.Count > 0 ? chain[0].pid : 0;
    }

    private static bool ContainsExe(List<(int pid, string exe, string path)> chain, string exe)
        => chain.Any(c => c.exe.Equals(exe, StringComparison.OrdinalIgnoreCase));

    private static string? FindPath(List<(int pid, string exe, string path)> chain, string exe)
        => chain.FirstOrDefault(c => c.exe.Equals(exe, StringComparison.OrdinalIgnoreCase)).path is { Length: > 0 } p ? p : null;

    private static string? FindPathContaining(List<(int pid, string exe, string path)> chain, string needle)
        => chain.FirstOrDefault(c => c.path.Contains(needle, StringComparison.OrdinalIgnoreCase)).path is { Length: > 0 } p ? p : null;

    private static string ResolvePath(int pid)
    {
        try
        {
            using var proc = Process.GetProcessById(pid);
            return proc.MainModule?.FileName ?? "";
        }
        catch
        {
            return ""; // access denied / gone → fall back to base exe name
        }
    }

    private static (Dictionary<int, int> parents, Dictionary<int, string> exeNames) Snapshot()
    {
        var parents = new Dictionary<int, int>();
        var exeNames = new Dictionary<int, string>();

        IntPtr snap = NativeMethods.CreateToolhelp32Snapshot(NativeMethods.TH32CS_SNAPPROCESS, 0);
        if (snap == IntPtr.Zero || snap == new IntPtr(-1))
            return (parents, exeNames);

        try
        {
            var entry = new NativeMethods.PROCESSENTRY32W
            {
                dwSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.PROCESSENTRY32W>()
            };
            if (NativeMethods.Process32FirstW(snap, ref entry))
            {
                do
                {
                    int pid = (int)entry.th32ProcessID;
                    parents[pid] = (int)entry.th32ParentProcessID;
                    exeNames[pid] = entry.szExeFile ?? "";
                } while (NativeMethods.Process32NextW(snap, ref entry));
            }
        }
        finally
        {
            NativeMethods.CloseHandle(snap);
        }
        return (parents, exeNames);
    }
}
