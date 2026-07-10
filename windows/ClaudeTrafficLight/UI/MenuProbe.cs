using System.Drawing;
using System.Text;
using System.Windows.Forms;
using ClaudeTrafficLight.Core;

namespace ClaudeTrafficLight.UI;

/// <summary>Debug (--menuprobe out.txt): build the menu off-screen and dump real geometry.</summary>
public static class MenuProbe
{
    public static int Run(string[] args)
    {
        string outPath = args.Length >= 2 ? args[1] : Path.Combine(Path.GetTempPath(), "menuprobe.txt");
        try { return RunCore(outPath); }
        catch (Exception ex) { File.WriteAllText(outPath, "EXCEPTION: " + ex); return 1; }
    }

    private static int RunCore(string outPath)
    {
        var theme = MenuTheme.Dark;
        var l = L10n.Current;
        int w = SessionRowControl.RowWidth;

        var menu = new ContextMenuStrip
        {
            ShowImageMargin = false,
            ShowCheckMargin = false,
            Padding = new Padding(0, 8, 0, 8)
        };
        menu.Renderer = new ThemedMenuRenderer(theme);

        ToolStripControlHost Host(Control c) => new(c)
        {
            AutoSize = false,
            Size = c.Size,
            Margin = Padding.Empty,
            Padding = Padding.Empty
        };

        menu.Items.Add(Host(new HeaderControl(l, theme, 1, 1, 1, w)));
        menu.Items.Add(new ToolStripSeparator());
        var s = new SessionStatus("s", State.Red, "proj", @"C:\x", DateTimeOffset.UtcNow, "vscode", "", 1);
        menu.Items.Add(Host(new SessionRowControl(s, l, theme)));
        menu.Items.Add(Host(new HintControl(l, theme, w)));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(Host(new ActionRowControl(theme, l.Refresh, w, shortcut: "R")));

        menu.Show(new Point(-3000, -3000)); // off-screen; forces layout

        var sb = new StringBuilder();
        sb.AppendLine($"RowWidth (control)   = {w}");
        sb.AppendLine($"menu.Width           = {menu.Width}");
        sb.AppendLine($"menu.Height          = {menu.Height}");
        sb.AppendLine($"menu.ClientSize      = {menu.ClientSize}");
        sb.AppendLine($"menu.Padding         = {menu.Padding}");
        sb.AppendLine($"menu.DisplayRectangle= {menu.DisplayRectangle}");
        sb.AppendLine("--- item bounds ---");
        foreach (ToolStripItem it in menu.Items)
            sb.AppendLine($"{it.GetType().Name,-24} Bounds={it.Bounds} Margin={it.Margin} Padding={it.Padding}");

        menu.Close();
        File.WriteAllText(outPath, sb.ToString());
        return 0;
    }
}
