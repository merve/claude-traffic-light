using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Windows.Forms;
using ClaudeTrafficLight.Core;

namespace ClaudeTrafficLight.UI;

/// <summary>Debug (--preview-menu): compose the themed menu into a PNG for visual review.</summary>
public static class PreviewMenu
{
    /// <summary>Capture the REAL flyout form (not a proxy) to a PNG.</summary>
    public static int Capture(string[] args)
    {
        string outPath = args[1];
        var theme = args.Length >= 3 && args[2].Equals("light", StringComparison.OrdinalIgnoreCase)
            ? MenuTheme.Light : MenuTheme.Dark;
        var l = L10n.Current;
        var now = DateTimeOffset.UtcNow;
        var sessions = new[]
        {
            new SessionStatus("s1", State.Red, "WiseFrontend", @"C:\dev\WiseFrontend", now.AddMinutes(-2), "vscode", "", 1),
            new SessionStatus("s2", State.Yellow, "payments-api", @"C:\dev\payments-api", now, "cursor", "", 2),
            new SessionStatus("s3", State.Green, "ClaudeTrafficLight", @"C:\dev\ctl", now.AddSeconds(-52), "terminal", "", 3),
        };
        using var f = new MenuFlyout(sessions, 1, 1, 1, l, theme);
        f.Location = new System.Drawing.Point(-4000, -4000);
        f.Show();
        using (var bmp = new Bitmap(f.Width, f.Height))
        {
            f.DrawToBitmap(bmp, new Rectangle(0, 0, f.Width, f.Height));
            bmp.Save(outPath, ImageFormat.Png);
        }
        f.Close();
        Console.WriteLine($"wrote {outPath} ({f.Width}x{f.Height})");
        return 0;
    }

    public static int Run(string[] args)
    {
        string outPath = args[1];
        var theme = args.Length >= 3 && args[2].Equals("light", StringComparison.OrdinalIgnoreCase)
            ? MenuTheme.Light : MenuTheme.Dark;
        var l = L10n.Current;
        int w = SessionRowControl.RowWidth;

        var now = DateTimeOffset.UtcNow;
        var sessions = new[]
        {
            new SessionStatus("s1", State.Red, "WiseFrontend", @"C:\dev\WiseFrontend", now.AddMinutes(-2), "vscode", "", 1),
            new SessionStatus("s2", State.Yellow, "payments-api", @"C:\dev\payments-api", now, "cursor", "", 2),
            new SessionStatus("s3", State.Green, "ClaudeTrafficLight", @"C:\dev\ctl", now.AddSeconds(-52), "terminal", "", 3),
        };
        int waiting = 1, working = 1, done = 1;

        var composite = new Bitmap(w, 1200, PixelFormat.Format32bppArgb);
        int y;
        using (var g = Graphics.FromImage(composite))
        {
            g.Clear(theme.Background);
            y = 8;

            y = DrawControl(g, new HeaderControl(l, theme, waiting, working, done, w), y);
            y = Separator(g, theme, w, y);
            foreach (var s in sessions)
                y = DrawControl(g, new SessionRowControl(s, l, theme), y);
            y = DrawControl(g, new HintControl(l, theme, w), y);
            y = Separator(g, theme, w, y);
            y = DrawControl(g, new ActionRowControl(theme, l.NotifyMenu, w, hasCheck: true, isChecked: true), y);
            y = DrawControl(g, new ActionRowControl(theme, l.Refresh, w, shortcut: "R"), y);
            y = DrawControl(g, new ActionRowControl(theme, l.Quit, w, shortcut: "Q"), y);
            y += 8;
        }

        var final = new Bitmap(w, y, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(final))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.DrawImage(composite, 0, 0);
            using var pen = new Pen(theme.Border);
            using var path = ThemedMenuRenderer.Rounded(new Rectangle(0, 0, w - 1, y - 1), 8);
            g.DrawPath(pen, path);
        }
        composite.Dispose();
        final.Save(outPath, ImageFormat.Png);
        final.Dispose();
        Console.WriteLine($"wrote {outPath} ({w}x{y})");
        return 0;
    }

    private static int DrawControl(Graphics g, Control c, int y)
    {
        using var bmp = new Bitmap(c.Width, c.Height);
        c.DrawToBitmap(bmp, new Rectangle(0, 0, c.Width, c.Height));
        g.DrawImage(bmp, 0, y);
        return y + c.Height;
    }

    private static int Separator(Graphics g, MenuTheme t, int w, int y)
    {
        y += 5;
        using var pen = new Pen(t.Separator);
        g.DrawLine(pen, 10, y, w - 10, y);
        return y + 6;
    }
}
