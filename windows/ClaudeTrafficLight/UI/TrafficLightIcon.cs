using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using ClaudeTrafficLight.Core;
using ClaudeTrafficLight.Platform;

namespace ClaudeTrafficLight.UI;

/// <summary>
/// Draws the traffic-light glyph (§7). The tray slot is square, so the light is
/// VERTICAL (red top, yellow middle, green bottom) — the natural Windows adaptation.
/// Colors, pulse and glow match the macOS renderer.
/// </summary>
public static class TrafficLightIcon
{
    // §7.1 calibrated lens colors (kept identical to macOS).
    private static readonly Color Red = Color.FromArgb(242, 51, 41);
    private static readonly Color Yellow = Color.FromArgb(255, 199, 13);
    private static readonly Color Green = Color.FromArgb(46, 184, 89);

    private static readonly Color Housing = Gray(0.17); // dark body
    private static readonly Color Socket = Gray(0.09);  // ring around each lens
    private static readonly Color Hood = Gray(0.08);    // eyelid over each lens

    private static Color Gray(double w) => Color.FromArgb(255, (int)(w * 255), (int)(w * 255), (int)(w * 255));
    private static Color ColorFor(State s) => s switch { State.Red => Red, State.Yellow => Yellow, _ => Green };

    /// <summary>Pulse brightness for the active lens (§7.2). 1.0 when not animating.</summary>
    public static double Pulse(State? active, double phase)
    {
        bool animate = active is State.Red or State.Yellow;
        if (!animate) return 1.0;
        return 0.75 + 0.25 * (0.5 - 0.5 * Math.Cos(phase * 2 * Math.PI));
    }

    /// <summary>
    /// Build a tray <see cref="Icon"/>. The caller MUST DestroyIcon the previous
    /// handle after assigning the new one (see <paramref name="hicon"/>) to avoid a leak.
    /// </summary>
    public static Icon RenderTrayIcon(State? active, double pulse, int waiting, int size, out IntPtr hicon)
    {
        // The Windows tray slot is a small square, so a 3-lens light is illegible there.
        // Show a single large lens of the active color (whichever is lit); dim disc when idle.
        using var bmp = RenderSingleLens(active, pulse, waiting, size);
        hicon = bmp.GetHicon();
        return Icon.FromHandle(hicon);
    }

    private static Bitmap RenderSingleLens(State? active, double pulse, int waiting, int N)
    {
        var bmp = new Bitmap(N, N, PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(bmp);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        g.Clear(Color.Transparent);

        float cx = N / 2f, cy = N / 2f;

        if (active is null)
        {
            // Idle (no sessions) — dim neutral disc so the tray still shows something.
            float dd = N * 0.66f;
            using var fill = new SolidBrush(Gray(0.30));
            g.FillEllipse(fill, cx - dd / 2, cy - dd / 2, dd, dd);
            using var ring = new Pen(Gray(0.48), Math.Max(1f, N * 0.045f));
            g.DrawEllipse(ring, cx - dd / 2, cy - dd / 2, dd, dd);
            return bmp;
        }

        var color = ColorFor(active.Value);
        bool animate = active is State.Red or State.Yellow;

        // Glow halo (pulses for red/yellow).
        float glowR = N * 0.5f;
        int glowA = animate ? (int)(40 + 55 * pulse) : 45;
        using (var halo = new GraphicsPath())
        {
            halo.AddEllipse(cx - glowR, cy - glowR, 2 * glowR, 2 * glowR);
            using var pgb = new PathGradientBrush(halo)
            {
                CenterPoint = new PointF(cx, cy),
                CenterColor = Color.FromArgb(glowA, color),
                SurroundColors = new[] { Color.FromArgb(0, color) }
            };
            g.FillEllipse(pgb, cx - glowR, cy - glowR, 2 * glowR, 2 * glowR);
        }

        // Core lens.
        float d = N * 0.66f;
        var rect = new RectangleF(cx - d / 2, cy - d / 2, d, d);
        var core = animate ? Blend(color, Color.White, 0.06 * pulse) : color;
        using (var fill = new SolidBrush(core))
            g.FillEllipse(fill, rect);
        // Dark edge for contrast on light taskbars.
        using (var edge = new Pen(Color.FromArgb(90, Blend(color, Color.Black, 0.5)), Math.Max(1f, N * 0.045f)))
            g.DrawEllipse(edge, rect);

        // Gloss highlight on top.
        using (var gloss = new GraphicsPath())
        {
            var gr = new RectangleF(cx - d * 0.34f, cy - d * 0.42f, d * 0.68f, d * 0.42f);
            gloss.AddEllipse(gr);
            using var gb = new SolidBrush(Color.FromArgb((int)(120 * (animate ? pulse : 1.0)), Color.White));
            g.FillPath(gb, gloss);
        }

        if (waiting > 1) DrawBadge(g, N, waiting);
        return bmp;
    }

    /// <summary>Free a HICON previously returned by <see cref="RenderTrayIcon"/> (no-op on zero).</summary>
    public static void DestroyIcon(IntPtr hicon)
    {
        if (hicon != IntPtr.Zero) NativeMethods.DestroyIcon(hicon);
    }

    private static Bitmap RenderVertical(State? active, double pulse, int waiting, int N)
    {
        var bmp = new Bitmap(N, N, PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(bmp);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        g.Clear(Color.Transparent);

        // §7.4 vertical layout math.
        float lensD = N * 0.26f;
        float gap = N * 0.035f;
        float sideMargin = N * 0.055f;
        float topMargin = N * 0.05f;
        float housingW = lensD + 2 * sideMargin;
        float housingH = 3 * lensD + 2 * gap + 2 * topMargin;
        float ox = (N - housingW) / 2f;
        float oy = (N - housingH) / 2f;
        float cx = ox + housingW / 2f;
        float firstCy = oy + topMargin + lensD / 2f;
        float step = lensD + gap;

        // Housing (stadium: corner radius = half width → fully rounded ends).
        using (var housingPath = RoundedRect(new RectangleF(ox, oy, housingW, housingH), housingW / 2f))
        using (var brush = new SolidBrush(Housing))
            g.FillPath(brush, housingPath);

        State[] order = { State.Red, State.Yellow, State.Green };
        for (int i = 0; i < 3; i++)
        {
            float cy = firstCy + i * step;
            bool isActive = active.HasValue && active.Value == order[i];
            DrawLens(g, cx, cy, lensD / 2f, order[i], isActive, pulse);
        }

        if (waiting > 1) DrawBadge(g, N, waiting);
        return bmp;
    }

    private static void DrawLens(Graphics g, float cx, float cy, float r, State state, bool active, double pulse)
    {
        var baseColor = ColorFor(state);
        var lensRect = new RectangleF(cx - r, cy - r, 2 * r, 2 * r);

        // Socket ring (slightly larger, dark).
        float sr = r + Math.Max(1f, r * 0.10f);
        using (var socketBrush = new SolidBrush(Socket))
            g.FillEllipse(socketBrush, cx - sr, cy - sr, 2 * sr, 2 * sr);

        if (active)
        {
            // Halo: radial gradient (center = color, edge = transparent), painted a few
            // times to intensify (§7.2). Approximates the macOS shadow-blur glow.
            float haloR = r * 2.1f;
            for (int pass = 0; pass < 3; pass++)
            {
                using var halo = new GraphicsPath();
                halo.AddEllipse(cx - haloR, cy - haloR, 2 * haloR, 2 * haloR);
                using var pgb = new PathGradientBrush(halo)
                {
                    CenterPoint = new PointF(cx, cy),
                    CenterColor = Color.FromArgb((int)(70 * pulse), baseColor),
                    SurroundColors = new[] { Color.FromArgb(0, baseColor) }
                };
                g.FillEllipse(pgb, cx - haloR, cy - haloR, 2 * haloR, 2 * haloR);
            }

            // Lens: saturated color blended with 6% white, at pulse alpha.
            var lit = Blend(baseColor, Color.White, 0.06);
            using (var brush = new SolidBrush(Color.FromArgb((int)(255 * pulse), lit)))
                g.FillEllipse(brush, lensRect);

            // Glass glint: thin bright cap on the top of the lens.
            int glintA = (int)(0.42 * pulse * 255);
            using var glint = new GraphicsPath();
            var glintRect = new RectangleF(cx - r * 0.72f, cy - r * 0.85f, r * 1.44f, r * 0.9f);
            glint.AddEllipse(glintRect);
            using var glintBrush = new SolidBrush(Color.FromArgb(glintA, Color.White));
            var clip = g.Clip;
            g.SetClip(new RectangleF(lensRect.X, lensRect.Y, lensRect.Width, lensRect.Height * 0.5f), CombineMode.Replace);
            g.FillPath(glintBrush, glint);
            g.Clip = clip;
        }
        else
        {
            // Dim (unlit) lens: base color at 30% alpha.
            using var brush = new SolidBrush(Color.FromArgb((int)(0.30 * 255), baseColor));
            g.FillEllipse(brush, lensRect);
        }

        // Hood / eyelid: opaque dark cap over the top third of the lens.
        using var hoodPath = new GraphicsPath();
        hoodPath.AddEllipse(cx - r * 1.05f, cy - r * 1.35f, r * 2.1f, r * 1.3f);
        using var hoodBrush = new SolidBrush(Hood);
        var savedClip = g.Clip;
        g.SetClip(new RectangleF(cx - r, cy - r, 2 * r, r * 0.42f), CombineMode.Replace);
        g.FillPath(hoodBrush, hoodPath);
        g.Clip = savedClip;
    }

    private static void DrawBadge(Graphics g, int N, int count)
    {
        float d = N * 0.5f;
        float x = N - d, y = 0;
        using (var bg = new SolidBrush(Red))
            g.FillEllipse(bg, x, y, d, d);
        using var pen = new Pen(Color.FromArgb(230, Color.White), Math.Max(1f, N * 0.03f));
        g.DrawEllipse(pen, x, y, d, d);

        string text = count > 9 ? "9+" : count.ToString();
        using var font = new Font("Segoe UI", d * 0.5f, FontStyle.Bold, GraphicsUnit.Pixel);
        using var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
        using var tb = new SolidBrush(Color.White);
        g.DrawString(text, font, tb, new RectangleF(x, y, d, d), sf);
    }

    private static Color Blend(Color a, Color b, double t)
        => Color.FromArgb(
            (int)(a.R + (b.R - a.R) * t),
            (int)(a.G + (b.G - a.G) * t),
            (int)(a.B + (b.B - a.B) * t));

    private static GraphicsPath RoundedRect(RectangleF r, float radius)
    {
        radius = Math.Min(radius, Math.Min(r.Width, r.Height) / 2f);
        float d = radius * 2f;
        var path = new GraphicsPath();
        if (radius <= 0) { path.AddRectangle(r); return path; }
        path.AddArc(r.Left, r.Top, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Top, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.Left, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}
