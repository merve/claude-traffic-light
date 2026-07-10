using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using Microsoft.Win32;

namespace ClaudeTrafficLight.UI;

/// <summary>Palette for the tray menu, chosen from the current Windows light/dark theme.</summary>
public sealed class MenuTheme
{
    public Color Background { get; init; }
    public Color Text { get; init; }
    public Color SubText { get; init; }
    public Color Hover { get; init; }        // row hover overlay
    public Color Separator { get; init; }
    public Color Border { get; init; }
    public Color Accent { get; init; }        // waiting/red highlight

    // Traffic-light colors (shared with the icon).
    public static readonly Color Red = Color.FromArgb(242, 51, 41);
    public static readonly Color Yellow = Color.FromArgb(255, 199, 13);
    public static readonly Color Green = Color.FromArgb(46, 184, 89);

    public static Color DotColor(Core.State s) => s switch
    {
        Core.State.Red => Red,
        Core.State.Yellow => Yellow,
        _ => Green
    };

    public static readonly MenuTheme Dark = new()
    {
        Background = Color.FromArgb(32, 32, 32),
        Text = Color.FromArgb(236, 236, 236),
        SubText = Color.FromArgb(150, 156, 162),
        Hover = Color.FromArgb(28, 255, 255, 255),
        Separator = Color.FromArgb(48, 48, 48),
        Border = Color.FromArgb(64, 64, 64),
        Accent = Red
    };

    public static readonly MenuTheme Light = new()
    {
        Background = Color.FromArgb(251, 251, 251),
        Text = Color.FromArgb(26, 26, 26),
        SubText = Color.FromArgb(107, 112, 117),
        Hover = Color.FromArgb(20, 0, 0, 0),
        Separator = Color.FromArgb(226, 226, 226),
        Border = Color.FromArgb(214, 214, 214),
        Accent = Color.FromArgb(200, 38, 30)
    };

    /// <summary>Reads the Windows "apps use light theme" preference (defaults to dark on failure).</summary>
    public static MenuTheme Current
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(
                    @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
                var v = key?.GetValue("AppsUseLightTheme");
                bool light = v is int i && i != 0;
                return light ? Light : Dark;
            }
            catch { return Dark; }
        }
    }
}

/// <summary>Flat, themed renderer for the tray <see cref="ContextMenuStrip"/> — rounded hover, custom border/separators.</summary>
public sealed class ThemedMenuRenderer : ToolStripProfessionalRenderer
{
    private readonly MenuTheme _t;

    public ThemedMenuRenderer(MenuTheme t) : base(new ThemedColorTable(t))
    {
        _t = t;
        RoundedEdges = false;
    }

    protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e)
    {
        using var b = new SolidBrush(_t.Background);
        e.Graphics.FillRectangle(b, e.AffectedBounds);
    }

    protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e)
    {
        // Border is painted by the rounded region owner; keep the inner edge subtle.
        var r = new Rectangle(0, 0, e.ToolStrip.Width - 1, e.ToolStrip.Height - 1);
        using var pen = new Pen(_t.Border);
        using var path = Rounded(r, 8);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.DrawPath(pen, path);
    }

    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
    {
        if (!e.Item.Selected || !e.Item.Enabled) return;
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        var r = new Rectangle(4, 1, e.Item.Width - 8, e.Item.Height - 2);
        using var b = new SolidBrush(_t.Hover);
        using var path = Rounded(r, 6);
        g.FillPath(b, path);
    }

    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
    {
        e.TextColor = e.Item.Enabled ? _t.Text : _t.SubText;
        base.OnRenderItemText(e);
    }

    protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e)
    {
        var g = e.Graphics;
        int y = e.Item.Height / 2;
        using var pen = new Pen(_t.Separator);
        g.DrawLine(pen, 10, y, e.Item.Width - 10, y);
    }

    internal static GraphicsPath Rounded(Rectangle r, int radius)
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

/// <summary>Color table so system-drawn bits (margins, arrows) match the theme.</summary>
internal sealed class ThemedColorTable : ProfessionalColorTable
{
    private readonly MenuTheme _t;
    public ThemedColorTable(MenuTheme t) { _t = t; UseSystemColors = false; }

    public override Color ToolStripDropDownBackground => _t.Background;
    public override Color ImageMarginGradientBegin => _t.Background;
    public override Color ImageMarginGradientMiddle => _t.Background;
    public override Color ImageMarginGradientEnd => _t.Background;
    public override Color MenuBorder => _t.Border;
    public override Color MenuItemBorder => Color.Transparent;
    public override Color MenuItemSelected => _t.Hover;
    public override Color MenuItemSelectedGradientBegin => _t.Hover;
    public override Color MenuItemSelectedGradientEnd => _t.Hover;
    public override Color SeparatorDark => _t.Separator;
    public override Color SeparatorLight => _t.Separator;
}
