using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using ClaudeTrafficLight.Core;
using ClaudeTrafficLight.Platform;

namespace ClaudeTrafficLight.UI;

/// <summary>
/// Custom flyout popup for the tray menu. A borderless top-level form gives pixel-perfect,
/// symmetric padding (ContextMenuStrip overrides its own Padding and adds width, §probe),
/// closes on outside click via <see cref="OnDeactivate"/>, and hosts the same themed
/// controls (header / rows / hint / actions).
/// </summary>
public sealed class MenuFlyout : Form
{
    private const int CW = 300;      // content width — all rows are exactly this wide
    private const int OuterTB = 8;   // top/bottom outer padding (sides handled inside rows at 16)
    private const int Radius = 8;

    private readonly MenuTheme _t;
    private readonly List<SessionRowControl> _rows = new();

    public event Action<SessionStatus>? RouteRequested;
    public event Action<SessionStatus>? EndRequested;
    public event Action? RefreshRequested;
    public event Action? UpdateCheckRequested;
    public event Action? QuitRequested;

    public string Signature { get; }

    public MenuFlyout(IReadOnlyList<SessionStatus> sessions, int waiting, int working, int done,
                      L10n l, MenuTheme t)
    {
        _t = t;
        Signature = string.Join("|", sessions.Select(s => s.SessionId + ":" + s.State));

        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        ShowInTaskbar = false;
        TopMost = true;
        BackColor = t.Background;
        DoubleBuffered = true;
        Font = new Font("Segoe UI", 9f);

        int y = OuterTB;

        var header = new HeaderControl(l, t, waiting, working, done, CW) { Location = new Point(0, y) };
        header.CloseClicked += Close;
        Controls.Add(header);
        y += header.Height;

        if (sessions.Count > 0)
        {
            y = AddSeparator(y);
            foreach (var s in sessions)
            {
                var row = new SessionRowControl(s, l, t) { Location = new Point(0, y) };
                row.RowClicked += sess => { RouteRequested?.Invoke(sess); Close(); };
                row.CloseClicked += sess => EndRequested?.Invoke(sess);
                Controls.Add(row);
                _rows.Add(row);
                y += row.Height;
            }
            var hint = new HintControl(l, t, CW) { Location = new Point(0, y) };
            Controls.Add(hint);
            y += hint.Height;
        }

        y = AddSeparator(y);

        var notif = new ActionRowControl(t, l.NotifyMenu, CW, hasCheck: true, isChecked: AppSettings.NotificationsEnabled)
        { Location = new Point(0, y) };
        notif.Clicked += () =>
        {
            AppSettings.NotificationsEnabled = !AppSettings.NotificationsEnabled;
            notif.Checked = AppSettings.NotificationsEnabled;
        };
        Controls.Add(notif);
        y += notif.Height;

        var refresh = new ActionRowControl(t, l.Refresh, CW, shortcut: "R") { Location = new Point(0, y) };
        refresh.Clicked += () => RefreshRequested?.Invoke();
        Controls.Add(refresh);
        y += refresh.Height;

        var updates = new ActionRowControl(t, l.CheckUpdates, CW) { Location = new Point(0, y) };
        updates.Clicked += () => UpdateCheckRequested?.Invoke();
        Controls.Add(updates);
        y += updates.Height;

        var quit = new ActionRowControl(t, l.Quit, CW, shortcut: "Q") { Location = new Point(0, y) };
        quit.Clicked += () => QuitRequested?.Invoke();
        Controls.Add(quit);
        y += quit.Height;

        y += OuterTB;
        ClientSize = new Size(CW, y);
        using (var rp = ThemedMenuRenderer.Rounded(new Rectangle(0, 0, CW, y), Radius))
            Region = new Region(rp); // dispose the path (Region copies its data)
    }

    /// <summary>Re-invalidate row controls so relative timestamps advance while open.</summary>
    public void RefreshTimes()
    {
        foreach (var r in _rows) r.Invalidate();
    }

    private int AddSeparator(int y)
    {
        y += 6;
        var sep = new Panel { BackColor = _t.Separator, Size = new Size(CW - 24, 1), Location = new Point(12, y) };
        Controls.Add(sep);
        return y + 1 + 6;
    }

    /// <summary>Position the flyout above-left of the anchor (tray/cursor), clamped on-screen.</summary>
    public void ShowAt(Point anchor)
    {
        var wa = Screen.FromPoint(anchor).WorkingArea;
        int x = Math.Min(anchor.X, wa.Right) - Width;   // right edge near the anchor
        int yy = anchor.Y - Height;                      // sit above the anchor (tray is at the bottom)
        x = Math.Max(wa.Left + 4, Math.Min(x, wa.Right - Width - 4));
        yy = Math.Max(wa.Top + 4, Math.Min(yy, wa.Bottom - Height - 4));
        Location = new Point(x, yy);
        Show();
        Activate();
        NativeMethods.SetForegroundWindow(Handle); // ensure Deactivate fires on outside click
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var pen = new Pen(_t.Border);
        using var path = ThemedMenuRenderer.Rounded(new Rectangle(0, 0, Width - 1, Height - 1), Radius);
        e.Graphics.DrawPath(pen, path);
    }

    protected override void OnDeactivate(EventArgs e)
    {
        base.OnDeactivate(e);
        Close(); // click outside → dismiss
    }

    protected override CreateParams CreateParams
    {
        get
        {
            const int CS_DROPSHADOW = 0x00020000;
            var cp = base.CreateParams;
            cp.ClassStyle |= CS_DROPSHADOW;
            return cp;
        }
    }

    // Don't steal activation from other apps on first show beyond what we need.
    protected override bool ShowWithoutActivation => false;
}
