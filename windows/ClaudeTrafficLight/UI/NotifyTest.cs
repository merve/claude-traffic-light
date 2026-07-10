using System.Windows.Forms;
using ClaudeTrafficLight.Core;

namespace ClaudeTrafficLight.UI;

/// <summary>Debug (--testnotify): show one balloon with an icon, then exit. Isolates the
/// notification path from polling/animation to check whether balloons render at all.</summary>
public sealed class NotifyTest : ApplicationContext
{
    private readonly NotifyIcon _tray;
    private IntPtr _hicon;

    public NotifyTest()
    {
        var icon = TrafficLightIcon.RenderTrayIcon(State.Red, 1.0, 0, 32, out _hicon);
        _tray = new NotifyIcon { Visible = true, Icon = icon, Text = "Claude Traffic Light — test" };

        // Give the shell a moment to register the icon, then fire the balloon.
        var t = new System.Windows.Forms.Timer { Interval = 800 };
        t.Tick += (_, _) =>
        {
            t.Stop(); t.Dispose();
            _tray.ShowBalloonTip(8000, "Claude seni bekliyor", "test-project · VS Code", ToolTipIcon.Info);
        };
        t.Start();

        // Auto-exit after 12s.
        var life = new System.Windows.Forms.Timer { Interval = 12000 };
        life.Tick += (_, _) =>
        {
            life.Stop(); life.Dispose();
            _tray.Visible = false;
            _tray.Dispose();
            TrafficLightIcon.DestroyIcon(_hicon);
            ExitThread();
        };
        life.Start();
    }
}
