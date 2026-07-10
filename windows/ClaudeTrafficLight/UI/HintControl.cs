using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using ClaudeTrafficLight.Core;

namespace ClaudeTrafficLight.UI;

/// <summary>Subtle footer hint under the session list (§8, "Click a session to jump to it").</summary>
public sealed class HintControl : Control
{
    private readonly L10n _l;
    private readonly MenuTheme _t;

    public HintControl(L10n l, MenuTheme t, int width)
    {
        _l = l; _t = t;
        Size = new Size(width, 26);
        DoubleBuffered = true;
        SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint, true);
        BackColor = t.Background;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        g.Clear(_t.Background);
        using var f = new Font("Segoe UI", 8f, FontStyle.Italic);
        using var b = new SolidBrush(Color.FromArgb(160, _t.SubText));
        g.DrawString(_l.Hint, f, b, new PointF(16, 5));
    }
}
