using System.Diagnostics;

namespace ClaudeTrafficLight.Platform;

/// <summary>Windows equivalents of the macOS <c>kill(pid, 0)</c> liveness and <c>SIGTERM</c> end.</summary>
public static class ProcessInfo
{
    /// <summary>True if a process with this pid is currently running (Windows: <see cref="Process.GetProcessById(int)"/>).</summary>
    public static bool IsAlive(int pid)
    {
        if (pid <= 0) return true; // unknown → treat as alive (fall back to time-based staleness)
        try
        {
            using var p = Process.GetProcessById(pid);
            return !p.HasExited;
        }
        catch (ArgumentException)
        {
            return false; // no such process
        }
        catch
        {
            // Access denied etc. → the process exists but we can't inspect it → assume alive.
            return true;
        }
    }

    /// <summary>End the session's process (macOS SIGTERM → CloseMainWindow, then Kill as last resort).</summary>
    public static void End(int pid)
    {
        if (pid <= 0) return;
        try
        {
            using var p = Process.GetProcessById(pid);
            if (!p.CloseMainWindow())
                p.Kill(entireProcessTree: true);
        }
        catch { /* already gone */ }
    }

    /// <summary>
    /// Bring the session's window to the front. For a terminal session the stored pid is the
    /// claude CLI (node/claude) — a console process with no window of its own; the terminal
    /// window belongs to an ancestor (Windows Terminal / conhost / …). So if the pid itself
    /// has no window, walk up the ancestry and focus the nearest ancestor that does.
    /// Returns false only when nothing in the chain owns a window.
    /// </summary>
    public static bool FocusWindow(int pid)
    {
        if (pid <= 0) return false;
        if (TryFocusProcessWindow(pid)) return true;               // GUI host / app owns a window
        foreach (int ancestor in ProcessTree.AncestorPids(pid))    // console: terminal is up the tree
            if (TryFocusProcessWindow(ancestor)) return true;
        return false;
    }

    private static bool TryFocusProcessWindow(int pid)
    {
        try
        {
            using var p = Process.GetProcessById(pid);
            IntPtr h = p.MainWindowHandle;
            if (h == IntPtr.Zero) return false;
            if (NativeMethods.IsIconic(h))
                NativeMethods.ShowWindow(h, NativeMethods.SW_RESTORE);
            return NativeMethods.SetForegroundWindow(h);
        }
        catch
        {
            return false;
        }
    }
}
