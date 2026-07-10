using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Windows.Forms;
using ClaudeTrafficLight.Core;
using ClaudeTrafficLight.UI;

namespace ClaudeTrafficWidget;

/// <summary>Debug (--capture out.png [dark|light]): compose the widget chrome + rows into a
/// PNG using in-memory sessions, without touching the real status dir.</summary>
internal static class WidgetPreview
{
    public static int Capture(string[] args)
    {
        string outPath = args[1];
        var theme = args.Length >= 3 && args[2].Equals("light", StringComparison.OrdinalIgnoreCase)
            ? MenuTheme.Light : MenuTheme.Dark;
        var l = L10n.Current;
        int w = SessionRowControl.RowWidth;
        var now = DateTimeOffset.UtcNow;

        var all = new[]
        {
            new SessionStatus("s1", State.Red, "WiseFrontend", @"C:\dev\WiseFrontend", now.AddMinutes(-2), "vscode", "", 1),
            new SessionStatus("s2", State.Yellow, "payments-api", @"C:\dev\payments-api", now, "cursor", "", 2),
            new SessionStatus("s3", State.Green, "ClaudeTrafficLight", @"C:\dev\ctl", now.AddSeconds(-40), "terminal", "", 3),
        };
        const int railW = 76, pad = 12, titleH = 26, titleGap = 8, dividerGap = 10, sideInset = 14, radius = 10;

        // Collapsed preview: the traffic light fills the widget (args[3] == "c").
        if (args.Length >= 4 && args[3].Equals("c", StringComparison.OrdinalIgnoreCase))
        {
            const int cw = 52, ch = 140;
            var cbmp = new Bitmap(cw, ch, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(cbmp))
            {
                g.Clear(theme.Background);
                g.SmoothingMode = SmoothingMode.AntiAlias;
                using var light = new TrafficLightPanel(theme) { Size = new Size(cw, ch), Fill = true };
                light.SetState(State.Red);
                light.SetPhase(0.5);
                Draw(g, light, 0, 0);
            }
            cbmp.Save(outPath, ImageFormat.Png);
            cbmp.Dispose();
            Console.WriteLine($"wrote {outPath} (collapsed {cw}x{ch})");
            return 0;
        }

        int count = args.Length >= 4 && int.TryParse(args[3], out var c) ? Math.Clamp(c, 0, 3) : 3;
        var sessions = all.Take(count).ToArray();
        int dividerY = pad + titleH + titleGap;
        int contentTop = dividerY + 1 + dividerGap;
        int listH = count == 0 ? 44 : count * 52;
        int y = Math.Max(contentTop + listH + pad, contentTop + 96 + pad);
        int contentH = y - contentTop - pad;
        int rowsTop = contentTop + (contentH - listH) / 2;
        int totalW = railW + w;

        var bmp = new Bitmap(totalW, y, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp))
        {
            g.Clear(theme.Background);
            g.SmoothingMode = SmoothingMode.AntiAlias;

            // Title bar spans the whole top row (below the top padding).
            using (var title = new WidgetTitleBar(theme, true) { Size = new Size(totalW, titleH) })
                Draw(g, title, 0, pad);

            // Divider under the title.
            using (var sep = new Pen(theme.Separator))
                g.DrawLine(sep, sideInset, dividerY, totalW - sideInset, dividerY);

            // Left rail below the divider: realistic traffic light (aggregate = red here).
            using (var light = new TrafficLightPanel(theme) { Size = new Size(railW, y - contentTop - pad) })
            {
                light.SetState(State.Red);
                light.SetPhase(0.5);
                Draw(g, light, 0, contentTop);
            }

            if (count == 0)
            {
                using var f = new Font("Segoe UI", 9f, FontStyle.Italic);
                TextRenderer.DrawText(g, l.NoSessions, f,
                    new Rectangle(railW, rowsTop, w, listH), theme.SubText,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
            }
            int cy = rowsTop;
            foreach (var s in sessions)
            {
                using var row = new SessionRowControl(s, l, theme);
                Draw(g, row, railW, cy);
                cy += row.Height;
            }

            using var pen = new Pen(theme.Border);
            using var path = Rounded(new Rectangle(0, 0, totalW - 1, y - 1), radius);
            g.DrawPath(pen, path);
        }
        bmp.Save(outPath, ImageFormat.Png);
        bmp.Dispose();
        Console.WriteLine($"wrote {outPath} ({w}x{y})");
        return 0;
    }

    private static void Draw(Graphics g, Control c, int x, int y)
    {
        using var bmp = new Bitmap(c.Width, c.Height);
        c.DrawToBitmap(bmp, new Rectangle(0, 0, c.Width, c.Height));
        g.DrawImage(bmp, x, y);
    }

    private static GraphicsPath Rounded(Rectangle r, int radius)
    {
        int d = radius * 2;
        var p = new GraphicsPath();
        p.AddArc(r.Left, r.Top, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Top, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.Left, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }
}
