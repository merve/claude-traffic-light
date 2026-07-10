using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using ClaudeTrafficLight.UI;

namespace ClaudeTrafficWidget;

/// <summary>Widget title bar: 3-dot logo + title, a pin (always-on-top) toggle, a close ✕,
/// and it doubles as the drag handle for the borderless window.</summary>
internal sealed class WidgetTitleBar : Control
{
    private readonly MenuTheme _t;
    private bool _pinned;
    private bool _pinHover, _closeHover, _toggleHover;

    public event Action? CloseClicked;
    public event Action<bool>? PinToggled;
    public event Action? ToggleClicked;   // collapse/expand the list

    private static readonly Color Red = Color.FromArgb(242, 51, 41);

    public WidgetTitleBar(MenuTheme t, bool pinned)
    {
        _t = t; _pinned = pinned;
        DoubleBuffered = true;
        SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint, true);
    }

    private Rectangle CloseRect => new(Width - 27, (Height - 22) / 2, 22, 22);
    private Rectangle PinRect => new(Width - 52, (Height - 22) / 2, 22, 22);
    private Rectangle ToggleRect => new(Width - 77, (Height - 22) / 2, 22, 22);

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        g.Clear(_t.Background);

        // Title, left-aligned across the whole top row.
        const int textX = 14;
        using var f = new Font("Segoe UI Semibold", 9.5f, FontStyle.Bold);
        TextRenderer.DrawText(g, "Claude Traffic Light", f,
            new Rectangle(textX, 0, ToggleRect.Left - textX - 6, Height), _t.Text,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);

        // Collapse toggle: a left-chevron "‹" (click to hide the list; the light stays).
        var tr = ToggleRect;
        if (_toggleHover) FillCircle(g, tr, Color.FromArgb(30, _t.Text));
        using (var pen = new Pen(_toggleHover ? _t.Text : _t.SubText, 1.8f) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round })
        {
            int cxc = tr.Left + tr.Width / 2, cyc = tr.Top + tr.Height / 2;
            g.DrawLines(pen, new[] { new Point(cxc + 2, cyc - 5), new Point(cxc - 3, cyc), new Point(cxc + 2, cyc + 5) });
        }

        // Pin toggle: simple push-pin, neutral color only (never a status color).
        // Bright (text) when pinned, dim (subtext) when not.
        var pr = PinRect;
        if (_pinHover) FillCircle(g, pr, Color.FromArgb(30, _t.Text));
        var pinColor = _pinned ? _t.Text : _t.SubText;
        using (var pen = new Pen(pinColor, 1.7f) { StartCap = LineCap.Round, EndCap = LineCap.Round })
        using (var br = new SolidBrush(pinColor))
        {
            int pcx = pr.Left + pr.Width / 2, pcy = pr.Top + 7;
            g.FillEllipse(br, pcx - 4, pcy - 4, 8, 8);
            g.DrawLine(pen, pcx, pcy + 4, pcx, pcy + 12);
        }

        // Close ✕.
        var cr = CloseRect;
        if (_closeHover) FillCircle(g, cr, Color.FromArgb(38, Red));
        using (var pen = new Pen(_closeHover ? Red : _t.SubText, 1.6f) { StartCap = LineCap.Round, EndCap = LineCap.Round })
        {
            int p = 7;
            g.DrawLine(pen, cr.Left + p, cr.Top + p, cr.Right - p, cr.Bottom - p);
            g.DrawLine(pen, cr.Right - p, cr.Top + p, cr.Left + p, cr.Bottom - p);
        }
    }

    private static void FillCircle(Graphics g, Rectangle r, Color c)
    {
        using var b = new SolidBrush(c);
        g.FillEllipse(b, r);
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        bool p = PinRect.Contains(e.Location), c = CloseRect.Contains(e.Location), t = ToggleRect.Contains(e.Location);
        if (p != _pinHover || c != _closeHover || t != _toggleHover)
        {
            _pinHover = p; _closeHover = c; _toggleHover = t;
            Cursor = (p || c || t) ? Cursors.Hand : Cursors.SizeAll;
            Invalidate();
        }
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        base.OnMouseLeave(e);
        _pinHover = _closeHover = _toggleHover = false;
        Invalidate();
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (e.Button != MouseButtons.Left) return;
        if (CloseRect.Contains(e.Location)) { CloseClicked?.Invoke(); return; }
        if (PinRect.Contains(e.Location)) { _pinned = !_pinned; PinToggled?.Invoke(_pinned); Invalidate(); return; }
        if (ToggleRect.Contains(e.Location)) { ToggleClicked?.Invoke(); return; }
        // Anywhere else on the bar → drag the window.
        var form = FindForm();
        if (form is not null) WidgetNative.DragMove(form.Handle);
    }
}
