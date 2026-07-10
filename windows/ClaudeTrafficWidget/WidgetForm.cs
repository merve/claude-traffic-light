using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using ClaudeTrafficLight.Core;
using ClaudeTrafficLight.Platform;
using ClaudeTrafficLight.UI;

namespace ClaudeTrafficWidget;

/// <summary>
/// A persistent desktop widget showing live Claude Code sessions. Reuses the tray app's
/// StatusStore + SessionRowControl and the same <c>~/.claude/status</c> contract, but is a
/// standalone, draggable, always-on-top panel. It never writes hooks/settings — read-only
/// viewer + click-to-jump, so it runs alongside the tray app without affecting it.
/// </summary>
internal sealed class WidgetForm : Form
{
    // Spacing system (8px rhythm).
    private const int W = SessionRowControl.RowWidth; // 300 (list column)
    private const int RailW = 76;                     // left traffic-light rail
    private const int Pad = 12;                       // outer padding (top / bottom)
    private const int TitleH = 26;
    private const int TitleGap = 8;                   // title → divider
    private const int DividerGap = 10;                // divider → content
    private const int DividerY = Pad + TitleH + TitleGap;
    private const int ContentTop = DividerY + 1 + DividerGap;
    private const int SideInset = 14;                 // divider horizontal inset
    private const int Radius = 10;

    private readonly MenuTheme _t = MenuTheme.Current;
    private L10n _l = L10n.Current;
    private readonly StatusStore _store = new();
    private readonly System.Windows.Forms.Timer _poll;
    private readonly System.Windows.Forms.Timer _anim;
    private readonly WidgetTitleBar _title;
    private readonly TrafficLightPanel _light;
    private readonly Label _empty;
    private readonly List<SessionRowControl> _rows = new();

    private const int CollapsedW = 52;   // collapsed: just the traffic light, no side gap
    private const int CollapsedH = 140;
    private const float Aspect = (float)CollapsedW / CollapsedH; // locked while resizing
    private const int MinCollapsedH = 96;
    private const int MaxCollapsedH = 300;

    private List<SessionStatus> _sessions = new();
    private State? _aggregate;
    private double _phase;
    private string _sig = "\0";
    private bool _positionRestored;
    private bool _expanded = WidgetSettings.ListExpanded;
    private ToolStripMenuItem? _showListItem;
    private bool _suppressResize;

    public WidgetForm()
    {
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        ShowInTaskbar = false;
        TopMost = WidgetSettings.Pinned;
        BackColor = _t.Background;
        DoubleBuffered = true;
        SetStyle(ControlStyles.ResizeRedraw, true); // full repaint on resize → no ghosting
        Font = new Font("Segoe UI", 9f);
        MinimumSize = new Size(30, MinCollapsedH); // allow collapsing/resizing down to just the light
        try { Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!); } catch { /* non-fatal */ }

        // Title spans the top row; a divider separates it from the traffic light + list.
        _light = new TrafficLightPanel(_t) { Location = new Point(0, ContentTop), Size = new Size(RailW, 60) };
        _light.ToggleRequested += () => SetExpanded(!_expanded); // clicking the light toggles the list
        Controls.Add(_light);

        _title = new WidgetTitleBar(_t, WidgetSettings.Pinned) { Location = new Point(0, Pad), Size = new Size(RailW + W, TitleH) };
        _title.CloseClicked += Close;
        _title.PinToggled += p => { TopMost = p; WidgetSettings.Pinned = p; };
        _title.ToggleClicked += () => SetExpanded(!_expanded);
        Controls.Add(_title);

        _empty = new Label
        {
            AutoSize = false,
            TextAlign = ContentAlignment.MiddleCenter,
            ForeColor = _t.SubText,
            BackColor = _t.Background,
            Font = new Font("Segoe UI", 9f, FontStyle.Italic),
            Visible = false
        };
        Controls.Add(_empty);

        BuildContextMenu();

        _poll = new System.Windows.Forms.Timer { Interval = 1000 };
        _poll.Tick += (_, _) => Poll();

        _anim = new System.Windows.Forms.Timer { Interval = 1000 / 15 }; // ~15 fps pulse
        _anim.Tick += (_, _) => AnimateTick();

        Poll();
        _poll.Start();
        _anim.Start();
    }

    private void AnimateTick()
    {
        if (_aggregate is State.Red or State.Yellow)
        {
            _phase += (1.0 / 15.0) / 1.2;
            if (_phase > 1.0) _phase -= 1.0;
            _light.SetPhase(_phase);
        }
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        WidgetNative.EnableRoundedCorners(Handle); // smooth, anti-aliased corners via DWM
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        RestorePosition();
    }

    private void RestorePosition()
    {
        if (_positionRestored) return;
        _positionRestored = true;
        var wa = Screen.PrimaryScreen!.WorkingArea;
        if (WidgetSettings.Position is { } p)
        {
            // Clamp onto a visible screen in case monitors changed.
            var scr = Screen.FromPoint(p).WorkingArea;
            int x = Math.Max(scr.Left, Math.Min(p.X, scr.Right - Width));
            int y = Math.Max(scr.Top, Math.Min(p.Y, scr.Bottom - Height));
            Location = new Point(x, y);
        }
        else
        {
            Location = new Point(wa.Right - Width - 24, wa.Bottom - Height - 24);
        }
    }

    protected override void OnMove(EventArgs e)
    {
        base.OnMove(e);
        if (_positionRestored) WidgetSettings.Position = Location;
    }

    // MARK: - polling / layout

    private void Poll()
    {
        _l = L10n.Current;
        _sessions = _store.Load();
        _aggregate = _sessions.Count == 0 ? null : _store.Aggregate(_sessions);
        _light.SetState(_aggregate);
        string sig = string.Join("|", _sessions.Select(s => s.SessionId + ":" + s.State));
        if (sig != _sig) { _sig = sig; Rebuild(); }
        else foreach (var r in _rows) r.Invalidate(); // advance relative times
    }

    private void Rebuild()
    {
        SuspendLayout();
        foreach (var r in _rows) { Controls.Remove(r); r.Dispose(); }
        _rows.Clear();

        int totalW, totalH;
        if (_expanded)
        {
            _light.Fill = false;
            _light.Resizable = false;
            _light.Dock = DockStyle.None;
            _title.Visible = true;
            _title.Bounds = new Rectangle(0, Pad, RailW + W, TitleH);

            int count = _sessions.Count;
            int listH = count == 0 ? 44 : count * 52;
            totalH = Math.Max(ContentTop + listH + Pad, ContentTop + 96 + Pad); // keep the light looking good
            int contentH = totalH - ContentTop - Pad;
            int rowsTop = ContentTop + (contentH - listH) / 2; // vertically centered → aligns with the light

            if (count == 0)
            {
                _empty.Text = _l.NoSessions;
                _empty.SetBounds(RailW, rowsTop, W, listH);
                _empty.Visible = true;
            }
            else
            {
                _empty.Visible = false;
                int y = rowsTop;
                foreach (var s in _sessions)
                {
                    var row = new SessionRowControl(s, _l, _t) { Location = new Point(RailW, y) };
                    row.RowClicked += Route;            // jump; widget stays open
                    row.CloseClicked += EndSession;     // end the session
                    Controls.Add(row);
                    _rows.Add(row);
                    y += row.Height;
                }
            }

            _light.Bounds = new Rectangle(0, ContentTop, RailW, contentH); // rail = full content area
            totalW = RailW + W;
        }
        else
        {
            // Collapsed: the traffic light fills the widget — no side/edge gap, resizable.
            _title.Visible = false;
            _empty.Visible = false;
            _light.Fill = true;
            _light.Resizable = true;
            _light.Dock = DockStyle.Fill; // auto-fills as the window is resized
            totalH = WidgetSettings.CollapsedHeight;
            totalW = (int)Math.Round(totalH * Aspect);
        }

        _suppressResize = true;
        ClientSize = new Size(totalW, totalH); // DWM rounds the corners; no hard region clip
        _suppressResize = false;
        ResumeLayout();
        Invalidate();
        if (_positionRestored) ClampToScreen();
    }

    private void SetExpanded(bool v)
    {
        if (_showListItem is not null) _showListItem.Checked = v;
        if (v == _expanded) return;
        _expanded = v;
        WidgetSettings.ListExpanded = v;
        Rebuild();
    }

    private void ClampToScreen()
    {
        var wa = Screen.FromRectangle(Bounds).WorkingArea;
        int x = Math.Max(wa.Left, Math.Min(Location.X, wa.Right - Width));
        int y = Math.Max(wa.Top, Math.Min(Location.Y, wa.Bottom - Height));
        if (x != Location.X || y != Location.Y) Location = new Point(x, y);
    }

    private void Route(SessionStatus s) => AppLauncher.Execute(
        SessionRouter.Action(s.Platform, s.Pid, s.Cwd, s.SessionId));

    private void EndSession(SessionStatus s)
    {
        ProcessInfo.End(s.Pid);
        var t = new System.Windows.Forms.Timer { Interval = 400 };
        t.Tick += (_, _) => { t.Stop(); t.Dispose(); Poll(); };
        t.Start();
    }

    // MARK: - chrome

    private void BuildContextMenu()
    {
        var menu = new ContextMenuStrip();
        var showList = new ToolStripMenuItem("Show list") { Checked = _expanded, CheckOnClick = true };
        showList.Click += (_, _) => SetExpanded(showList.Checked);
        _showListItem = showList;
        var pin = new ToolStripMenuItem("Always on top") { Checked = WidgetSettings.Pinned, CheckOnClick = true };
        pin.Click += (_, _) => { TopMost = pin.Checked; WidgetSettings.Pinned = pin.Checked; };
        var auto = new ToolStripMenuItem("Start with Windows") { Checked = WidgetSettings.Autostart, CheckOnClick = true };
        auto.Click += (_, _) => WidgetSettings.Autostart = auto.Checked;
        var close = new ToolStripMenuItem("Close widget");
        close.Click += (_, _) => Close();
        menu.Items.AddRange(new ToolStripItem[] { showList, pin, auto, new ToolStripSeparator(), close });
        ContextMenuStrip = menu;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;

        // When collapsed the traffic-light housing draws its own edge → no widget chrome.
        if (!_expanded) return;

        // Divider under the title.
        using (var sep = new Pen(_t.Separator))
            g.DrawLine(sep, SideInset, DividerY, Width - SideInset, DividerY);

        using var pen = new Pen(_t.Border);
        using var path = RoundedPath(new Rectangle(0, 0, Width - 1, Height - 1), Radius);
        g.DrawPath(pen, path);
    }

    // Aspect-locked resize while collapsed (keeps the traffic-light proportions).
    protected override void WndProc(ref Message m)
    {
        if (!_expanded && m.Msg == WidgetNative.WM_SIZING)
        {
            var rc = System.Runtime.InteropServices.Marshal.PtrToStructure<WidgetNative.RECT>(m.LParam);
            int edge = m.WParam.ToInt32();

            // Aspect-lock + clamp + edge-anchor is pure geometry (see WidgetResize, unit-tested).
            (rc.Left, rc.Top, rc.Right, rc.Bottom) =
                WidgetResize.Apply(edge, rc.Left, rc.Top, rc.Right, rc.Bottom, Aspect, MinCollapsedH, MaxCollapsedH);

            System.Runtime.InteropServices.Marshal.StructureToPtr(rc, m.LParam, false);
            m.Result = (IntPtr)1;
            return;
        }
        base.WndProc(ref m);
    }

    protected override void OnClientSizeChanged(EventArgs e)
    {
        base.OnClientSizeChanged(e);
        if (_suppressResize || _expanded || !_positionRestored) return;
        // Live resize (collapsed): the docked light auto-fills; DWM re-rounds the corners.
        WidgetSettings.CollapsedHeight = ClientSize.Height;
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

    private static GraphicsPath RoundedPath(Rectangle r, int radius)
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

    protected override void Dispose(bool disposing)
    {
        if (disposing) { _poll?.Dispose(); _anim?.Dispose(); }
        base.Dispose(disposing);
    }
}
