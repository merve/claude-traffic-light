using System.ComponentModel;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace ClaudeTrafficLight.UI;

/// <summary>
/// A themed action item for the bottom of the menu (Notifications / Refresh / Quit).
/// Custom-drawn so it shares the exact 16 px gutter, height and hover of the rest of
/// the menu instead of the default ToolStripMenuItem metrics.
/// </summary>
public sealed class ActionRowControl : Control
{
    private readonly MenuTheme _t;
    private readonly string _text;
    private readonly string? _shortcut;
    private readonly bool _hasCheck;
    private bool _checked;
    private bool _hover;

    public event Action? Clicked;

    private const int RowHeight = 34;
    private const int Gutter = 16;   // left edge, shared with header
    private const int IconSize = 16;
    private const int TextX = 40;    // aligns with the session-row title column
    private const int RightPad = 16;

    private static readonly Color CheckOn = Color.FromArgb(45, 125, 210);

    public ActionRowControl(MenuTheme t, string text, int width, string? shortcut = null,
                            bool hasCheck = false, bool isChecked = false)
    {
        _t = t; _text = text; _shortcut = shortcut; _hasCheck = hasCheck; _checked = isChecked;
        Size = new Size(width, RowHeight);
        BackColor = t.Background;
        DoubleBuffered = true;
        SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint, true);
        Cursor = Cursors.Hand;
    }

    [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public bool Checked
    {
        get => _checked;
        set { _checked = value; Invalidate(); }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        g.Clear(_t.Background);

        if (_hover)
        {
            var hr = new Rectangle(4, 2, Width - 8, Height - 4);
            using var hb = new SolidBrush(_t.Hover);
            using var hp = ThemedMenuRenderer.Rounded(hr, 6);
            g.FillPath(hb, hp);
        }

        if (_hasCheck)
        {
            var box = new Rectangle(Gutter, (Height - IconSize) / 2, IconSize, IconSize);
            using var boxPath = ThemedMenuRenderer.Rounded(box, 4);
            if (_checked)
            {
                using var fill = new SolidBrush(CheckOn);
                g.FillPath(fill, boxPath);
                using var pen = new Pen(Color.White, 1.8f) { StartCap = LineCap.Round, EndCap = LineCap.Round };
                g.DrawLines(pen, new[]
                {
                    new PointF(box.Left + 4f, box.Top + 8.5f),
                    new PointF(box.Left + 6.8f, box.Top + 11.5f),
                    new PointF(box.Right - 3.5f, box.Top + 4.5f),
                });
            }
            else
            {
                using var pen = new Pen(_t.SubText, 1.4f);
                g.DrawPath(pen, boxPath);
            }
        }

        var textRect = new Rectangle(TextX, 0, Width - TextX - RightPad, Height);
        using var f = new Font("Segoe UI", 9.5f, FontStyle.Regular);
        TextRenderer.DrawText(g, _text, f, textRect, _t.Text,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);

        if (_shortcut is not null)
        {
            TextRenderer.DrawText(g, _shortcut, f, textRect, _t.SubText,
                TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        }
    }

    protected override void OnMouseEnter(EventArgs e) { _hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { _hover = false; Invalidate(); base.OnMouseLeave(e); }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (e.Button == MouseButtons.Left) Clicked?.Invoke();
    }
}
