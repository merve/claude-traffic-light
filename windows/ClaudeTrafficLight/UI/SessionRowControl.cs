using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using ClaudeTrafficLight.Core;

namespace ClaudeTrafficLight.UI;

/// <summary>
/// A styled session row hosted in the tray menu (§8.3): status dot, project name +
/// detail, a platform tag, and a per-session close (✕) button. Clicking the row
/// jumps to the session; clicking ✕ ends it. Themed to match the rest of the menu.
/// </summary>
public sealed class SessionRowControl : Control
{
    public SessionStatus Session { get; private set; }
    private readonly L10n _l;
    private readonly MenuTheme _t;
    private bool _hover;
    private bool _closeHover;

    public event Action<SessionStatus>? RowClicked;
    public event Action<SessionStatus>? CloseClicked;

    public const int RowWidth = 300;
    private const int RowHeight = 52;
    private const int CloseSize = 20;

    public SessionRowControl(SessionStatus session, L10n l, MenuTheme t)
    {
        Session = session;
        _l = l;
        _t = t;
        Size = new Size(RowWidth, RowHeight);
        BackColor = t.Background;
        ForeColor = t.Text;
        DoubleBuffered = true;
        SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint, true);
        Cursor = Cursors.Hand;
    }

    public void UpdateSession(SessionStatus s)
    {
        Session = s;
        Invalidate();
    }

    // Glyph inset is 6, so X.Right = Width-10 puts the visible ✕ edge 16 px from the border.
    private Rectangle CloseRect => new(Width - CloseSize - 10, (Height - CloseSize) / 2, CloseSize, CloseSize);

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        g.Clear(_t.Background);

        // Rounded hover highlight.
        if (_hover)
        {
            var hr = new Rectangle(4, 3, Width - 8, Height - 6);
            using var hb = new SolidBrush(_t.Hover);
            using var hp = ThemedMenuRenderer.Rounded(hr, 6);
            g.FillPath(hb, hp);
        }

        var color = MenuTheme.DotColor(Session.State);

        // Status dot with a soft glow ring.
        int dotD = 11;
        int dotX = 16, dotY = (Height - dotD) / 2;
        float haloR = dotD * 1.5f;
        float hcx = dotX + dotD / 2f, hcy = dotY + dotD / 2f;
        using (var halo = new GraphicsPath())
        {
            halo.AddEllipse(hcx - haloR, hcy - haloR, 2 * haloR, 2 * haloR);
            using var pgb = new PathGradientBrush(halo)
            {
                CenterColor = Color.FromArgb(90, color),
                SurroundColors = new[] { Color.FromArgb(0, color) },
                CenterPoint = new PointF(hcx, hcy)
            };
            g.FillEllipse(pgb, hcx - haloR, hcy - haloR, 2 * haloR, 2 * haloR);
        }
        using (var db = new SolidBrush(color))
            g.FillEllipse(db, dotX, dotY, dotD, dotD);

        const int textX = 40; // shared title column (aligns with action rows)

        // Platform tag, right-aligned on the title line (left of the close button).
        string platform = PlatformLabel.Label(Session.Platform);
        using var tagFont = new Font("Segoe UI", 7.5f, FontStyle.Regular);
        int tagTextW = TextRenderer.MeasureText(g, platform, tagFont, Size.Empty, TextFormatFlags.NoPadding).Width;
        int tagW = tagTextW + 16;
        int tagH = 17;
        int tagX = CloseRect.Left - tagW - 10;
        int tagY = (Height - tagH) / 2; // vertically centered → aligns with the dot and the ✕
        var tagRect = new Rectangle(tagX, tagY, tagW, tagH);
        using (var tagBg = new SolidBrush(_t.Hover))
        using (var tp = ThemedMenuRenderer.Rounded(tagRect, 8))
            g.FillPath(tagBg, tp);
        TextRenderer.DrawText(g, platform, tagFont, tagRect, _t.SubText,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);

        // Title (project) + detail — both on the textX column.
        int titleW = tagX - textX - 8;
        using var titleFont = new Font("Segoe UI Semibold", 9.5f, FontStyle.Bold);
        using var subFont = new Font("Segoe UI", 8f, FontStyle.Regular);
        var titleFlags = TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding;
        TextRenderer.DrawText(g, Session.Project, titleFont, new Rectangle(textX, 8, titleW, 20), _t.Text, titleFlags);
        TextRenderer.DrawText(g, DetailText(), subFont, new Rectangle(textX, 28, CloseRect.Left - textX - 8, 18), _t.SubText, titleFlags);

        // Close button.
        var cr = CloseRect;
        if (_closeHover)
        {
            using var cb = new SolidBrush(Color.FromArgb(38, _t.Accent));
            g.FillEllipse(cb, cr);
        }
        using var xPen = new Pen(_closeHover ? _t.Accent : _t.SubText, 1.6f) { StartCap = LineCap.Round, EndCap = LineCap.Round };
        int pad = 6;
        g.DrawLine(xPen, cr.Left + pad, cr.Top + pad, cr.Right - pad, cr.Bottom - pad);
        g.DrawLine(xPen, cr.Right - pad, cr.Top + pad, cr.Left + pad, cr.Bottom - pad);
    }

    private string DetailText()
    {
        // yellow → just the status label; red/green → "<label> · <relative time>".
        if (Session.State == State.Yellow)
            return _l.Label(Session.State);
        return $"{_l.Label(Session.State)} · {RelativeTime.Ago(Session.Ts, _l)}";
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        bool wasClose = _closeHover;
        _closeHover = CloseRect.Contains(e.Location);
        Cursor = _closeHover ? Cursors.Hand : Cursors.Hand;
        if (!_hover || wasClose != _closeHover) { _hover = true; Invalidate(); }
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        base.OnMouseLeave(e);
        _hover = false; _closeHover = false;
        Invalidate();
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (e.Button != MouseButtons.Left) return;
        if (CloseRect.Contains(e.Location)) CloseClicked?.Invoke(Session);
        else RowClicked?.Invoke(Session);
    }
}
