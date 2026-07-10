using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using ClaudeTrafficLight.Core;

namespace ClaudeTrafficLight.UI;

/// <summary>Menu header (§8.1): title + a summary counter with the waiting count accented,
/// plus a top-right ✕ that closes the menu.</summary>
public sealed class HeaderControl : Control
{
    private readonly L10n _l;
    private readonly MenuTheme _t;
    private readonly int _waiting, _working, _done;
    private readonly bool _empty;
    private bool _closeHover;

    public event Action? CloseClicked;

    private const int Gutter = 16;
    private const int CloseSize = 26;   // larger than the per-row close (§ user request)

    public HeaderControl(L10n l, MenuTheme t, int waiting, int working, int done, int width)
    {
        _l = l; _t = t; _waiting = waiting; _working = working; _done = done;
        _empty = waiting + working + done == 0;
        Size = new Size(width, _empty ? 40 : 52);
        DoubleBuffered = true;
        SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint, true);
        BackColor = t.Background;
    }

    // Glyph inset is 8, so X.Right = Width-8 / Top = 0 puts the visible ✕ 16 px from
    // the right border and ~16 px (incl. the menu's 8 px top pad) from the top.
    private Rectangle CloseRect => new(Width - CloseSize - 8, 0, CloseSize, CloseSize);

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        g.Clear(_t.Background);

        if (_empty)
        {
            using var f = new Font("Segoe UI", 9.5f, FontStyle.Regular);
            TextRenderer.DrawText(g, _l.NoSessions, f,
                new Rectangle(Gutter, 0, Width - Gutter - CloseSize - 20, Height), _t.SubText,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            DrawClose(g);
            return;
        }

        using var titleFont = new Font("Segoe UI Semibold", 10f, FontStyle.Bold);
        TextRenderer.DrawText(g, _l.ActiveSessions, titleFont,
            new Point(Gutter - 1, 7), _t.Text, TextFormatFlags.NoPadding);

        // Summary segments; waiting is accented (§8.1). "done" shows only if nothing else.
        var segs = new List<(string text, Color color, bool bold)>();
        if (_waiting > 0) segs.Add(($"{_waiting} {_l.WaitingWord}", _t.Accent, true));
        if (_working > 0) segs.Add(($"{_working} {_l.WorkingWord}", _t.SubText, false));
        if (segs.Count == 0) segs.Add(($"{_done} {_l.DoneWord}", _t.SubText, false));

        int x = Gutter;
        int y = 29;
        using var regular = new Font("Segoe UI", 8.5f, FontStyle.Regular);
        using var bold = new Font("Segoe UI Semibold", 8.5f, FontStyle.Bold);
        for (int i = 0; i < segs.Count; i++)
        {
            var (text, color, isBold) = segs[i];
            var f = isBold ? bold : regular;
            TextRenderer.DrawText(g, text, f, new Point(x, y), color, TextFormatFlags.NoPadding);
            x += TextRenderer.MeasureText(g, text, f, Size.Empty, TextFormatFlags.NoPadding).Width;
            if (i < segs.Count - 1)
            {
                TextRenderer.DrawText(g, "·", regular, new Point(x + 2, y), _t.SubText, TextFormatFlags.NoPadding);
                x += TextRenderer.MeasureText(g, "·", regular, Size.Empty, TextFormatFlags.NoPadding).Width + 4;
            }
        }

        DrawClose(g);
    }

    private void DrawClose(Graphics g)
    {
        var cr = CloseRect;
        if (_closeHover)
        {
            using var cb = new SolidBrush(Color.FromArgb(38, _t.Accent));
            g.FillEllipse(cb, cr);
        }
        using var pen = new Pen(_closeHover ? _t.Accent : _t.SubText, 1.8f) { StartCap = LineCap.Round, EndCap = LineCap.Round };
        int pad = 8; // 26 - 2*8 = 10 px glyph, clearly bigger than the 8 px row ✕
        g.DrawLine(pen, cr.Left + pad, cr.Top + pad, cr.Right - pad, cr.Bottom - pad);
        g.DrawLine(pen, cr.Right - pad, cr.Top + pad, cr.Left + pad, cr.Bottom - pad);
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        bool h = CloseRect.Contains(e.Location);
        if (h != _closeHover) { _closeHover = h; Cursor = h ? Cursors.Hand : Cursors.Default; Invalidate(); }
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        base.OnMouseLeave(e);
        if (_closeHover) { _closeHover = false; Invalidate(); }
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (e.Button == MouseButtons.Left && CloseRect.Contains(e.Location)) CloseClicked?.Invoke();
    }
}
