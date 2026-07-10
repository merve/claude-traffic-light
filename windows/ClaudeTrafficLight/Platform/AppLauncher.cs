using System.Diagnostics;
using ClaudeTrafficLight.Core;

namespace ClaudeTrafficLight.Platform;

/// <summary>Executes an <see cref="OpenAction"/> decided by <see cref="SessionRouter"/> (§5 / §12.3).</summary>
public static class AppLauncher
{
    public static void Execute(OpenAction action)
    {
        switch (action)
        {
            case OpenAction.OpenInEditor(var editor, var folder):
                if (!OpenInEditor(editor, folder))
                    OpenFolderFallback(folder); // editor not installed → generic opener
                break;

            case OpenAction.DesktopDeepLink(var sessionId):
                OpenDesktopDeepLink(sessionId);
                break;

            case OpenAction.FocusProcessWindow(var pid, var folder):
                if (!ProcessInfo.FocusWindow(pid))
                    OpenTerminalFallback(folder); // window gone → open a terminal there (never VS Code)
                break;
        }
    }

    /// <summary>Open a folder in a CLI editor (code / cursor) via its PATH launcher, no console flash.
    /// Returns false when the editor's launcher is not found on PATH.</summary>
    private static bool OpenInEditor(string editor, string folder)
    {
        if (string.IsNullOrEmpty(folder)) return false;
        string? launcher = Which(editor);
        if (launcher is null) return false;
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "cmd.exe",
                Arguments = $"/c \"\"{launcher}\" \"{folder}\"\"",
                UseShellExecute = false,
                CreateNoWindow = true
            };
            Process.Start(psi);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static void OpenDesktopDeepLink(string sessionId)
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = $"claude://resume?session={Uri.EscapeDataString(sessionId)}",
                UseShellExecute = true
            });
        }
        catch { /* Claude desktop / scheme not registered — nothing else we can do */ }
    }

    /// <summary>
    /// Fallback for a terminal / unknown session whose window we could not focus: open a
    /// terminal at the project folder (Windows Terminal → Explorer). Deliberately never opens
    /// an editor, so a terminal session is never mis-routed into VS Code.
    /// </summary>
    private static void OpenTerminalFallback(string folder)
    {
        if (string.IsNullOrEmpty(folder)) return;
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "wt.exe",                     // Windows Terminal, opened at the folder
                Arguments = $"-d \"{folder}\"",
                UseShellExecute = true
            });
            return;
        }
        catch { /* Windows Terminal not installed → fall through to Explorer */ }
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = $"\"{folder}\"",
                UseShellExecute = true
            });
        }
        catch { /* give up */ }
    }

    /// <summary>Generic folder opener: try VS Code → Cursor → Explorer (mirrors the macOS fallback order).</summary>
    private static void OpenFolderFallback(string folder)
    {
        if (string.IsNullOrEmpty(folder)) return;
        if (OpenInEditor("code", folder)) return;
        if (OpenInEditor("cursor", folder)) return;
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = $"\"{folder}\"",
                UseShellExecute = true
            });
        }
        catch { /* give up */ }
    }

    /// <summary>Resolve a command to its full path by scanning %PATH% with %PATHEXT% (like `where`), no subprocess.</summary>
    private static string? Which(string command)
    {
        try
        {
            var pathDirs = (Environment.GetEnvironmentVariable("PATH") ?? "")
                .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries);
            var exts = (Environment.GetEnvironmentVariable("PATHEXT") ?? ".COM;.EXE;.BAT;.CMD")
                .Split(';', StringSplitOptions.RemoveEmptyEntries);

            foreach (var dir in pathDirs)
            {
                foreach (var ext in exts)
                {
                    string candidate = Path.Combine(dir.Trim(), command + ext);
                    if (File.Exists(candidate)) return candidate;
                }
                // Also allow an explicit extension already in the command name.
                string asIs = Path.Combine(dir.Trim(), command);
                if (File.Exists(asIs)) return asIs;
            }
        }
        catch { /* fall through */ }
        return null;
    }
}
