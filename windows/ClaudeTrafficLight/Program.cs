using System.Windows.Forms;
using ClaudeTrafficLight;
using ClaudeTrafficLight.Hook;
using ClaudeTrafficLight.UI;

// Entry point (§12.1): the ONE exe is both the tray app and the Claude Code hook.
//   ClaudeTrafficLight.exe --hook <state>   → hook mode (read stdin JSON, write status, exit)
//   ClaudeTrafficLight.exe --install         → set up hooks + autostart, then launch the tray
//   ClaudeTrafficLight.exe --uninstall        → remove hooks + autostart, then exit
//   ClaudeTrafficLight.exe                    → run the tray app
internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        // --- Hook mode: must be fast and silent (no window). Fires on every tool call. ---
        if (args.Length >= 1 && args[0] == "--hook")
        {
            string state = args.Length >= 2 ? args[1] : "";
            return HookRunner.Run(state);
        }

        if (args.Length >= 1 && args[0] == "--uninstall")
        {
            Bootstrap.Uninstall();
            return 0;
        }

        // Debug: render the tray icon for a state to a PNG (for visual verification).
        //   --render <red|yellow|green|off> <out.png> [size] [waiting]
        if (args.Length >= 3 && args[0] == "--render")
        {
            return DebugRender.Run(args);
        }

        // Debug: show a single balloon notification for a few seconds, no polling/animation.
        if (args.Length >= 1 && args[0] == "--testnotify")
        {
            ApplicationConfiguration.Initialize();
            Application.Run(new NotifyTest());
            return 0;
        }

        // Debug: compose the themed menu into a PNG.  --preview-menu <out.png> [dark|light]
        if (args.Length >= 2 && args[0] == "--preview-menu")
        {
            ApplicationConfiguration.Initialize();
            return PreviewMenu.Run(args);
        }

        // Debug: dump real menu geometry off-screen.  --menuprobe <out.txt>
        if (args.Length >= 1 && args[0] == "--menuprobe")
        {
            ApplicationConfiguration.Initialize();
            return MenuProbe.Run(args);
        }

        // Debug: capture the real flyout form to a PNG.  --capture-flyout <out.png> [dark|light]
        if (args.Length >= 2 && args[0] == "--capture-flyout")
        {
            ApplicationConfiguration.Initialize();
            return PreviewMenu.Capture(args);
        }

        // --- Tray mode ---
        ApplicationConfiguration.Initialize(); // high-DPI (PerMonitorV2) + default font

        // Always (re)install on normal launch so hooks/autostart self-heal; cheap & idempotent.
        try { Bootstrap.Install(); } catch { /* non-fatal */ }

        // Single instance: autostart + a manual launch must not stack two tray icons.
        using var mutex = new Mutex(initiallyOwned: true, "ClaudeTrafficLight_SingleInstance", out bool isNew);
        if (!isNew) return 0;

        Application.Run(new TrayApp());
        return 0;
    }
}
