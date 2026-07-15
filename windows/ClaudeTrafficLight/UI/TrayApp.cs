using System.Drawing;
using System.Windows.Forms;
using ClaudeTrafficLight.Core;
using ClaudeTrafficLight.Platform;

namespace ClaudeTrafficLight.UI;

/// <summary>
/// The tray application (§6, §8): a NotifyIcon showing the aggregate traffic light,
/// a custom flyout listing sessions, a 1 s poll timer and a ~15 fps pulse animation,
/// plus red-transition balloon notifications.
/// </summary>
public sealed class TrayApp : ApplicationContext
{
    private readonly NotifyIcon _tray;
    private readonly System.Windows.Forms.Timer _pollTimer;
    private readonly System.Windows.Forms.Timer _animTimer;

    private readonly StatusStore _store = new();
    private readonly RedTransitionTracker _redTracker = new();
    private L10n _l = L10n.Current;

    private List<SessionStatus> _sessions = new();
    private State? _active;      // null = light off (no sessions)
    private int _waiting;
    private double _phase;
    private IntPtr _lastHicon = IntPtr.Zero;
    private string? _lastNotifiedSessionId;

    private MenuFlyout? _flyout;
    private Point _anchor;
    private int _flyoutClosedTick;

    public TrayApp()
    {
        _tray = new NotifyIcon { Visible = true, Text = "Claude Traffic Light" };
        _tray.BalloonTipClicked += (_, _) => OnBalloonClicked();
        _tray.MouseClick += (_, e) => OnTrayClick(e);

        _pollTimer = new System.Windows.Forms.Timer { Interval = 1000 };
        _pollTimer.Tick += (_, _) => Poll();

        _animTimer = new System.Windows.Forms.Timer { Interval = 1000 / 15 }; // ~15 fps
        _animTimer.Tick += (_, _) => AnimateTick();

        Poll();                 // initial paint
        _pollTimer.Start();
        _animTimer.Start();
    }

    // MARK: - flyout

    private void OnTrayClick(MouseEventArgs e)
    {
        if (e.Button is not (MouseButtons.Left or MouseButtons.Right)) return;
        // If a click just closed the flyout (Deactivate fires before this), treat as toggle.
        if (_flyout is null && Environment.TickCount - _flyoutClosedTick < 300) return;
        if (_flyout is not null) { CloseFlyout(); return; }
        _anchor = Cursor.Position;
        ShowFlyout();
    }

    private void ShowFlyout()
    {
        CloseFlyout();
        _l = L10n.Current;
        var theme = MenuTheme.Current;
        int working = _sessions.Count(s => s.State == State.Yellow);
        int done = _sessions.Count(s => s.State == State.Green);

        var f = new MenuFlyout(_sessions, _waiting, working, done, _l, theme);
        f.RouteRequested += Route;
        f.EndRequested += EndSession;
        f.RefreshRequested += () => { Poll(); ShowFlyout(); };   // rebuild in place
        f.UpdateCheckRequested += CheckForUpdates;
        f.QuitRequested += Shutdown;
        f.FormClosed += (_, _) => { if (_flyout == f) { _flyout = null; _flyoutClosedTick = Environment.TickCount; } };
        _flyout = f;
        f.ShowAt(_anchor);
    }

    private void CloseFlyout()
    {
        if (_flyout is null) return;
        var f = _flyout;
        _flyout = null;
        _flyoutClosedTick = Environment.TickCount;
        try { f.Close(); f.Dispose(); } catch { /* ignore */ }
    }

    // MARK: - polling

    private void Poll()
    {
        _l = L10n.Current;
        _sessions = _store.Load();
        _waiting = _sessions.Count(s => s.State == State.Red);
        _active = _sessions.Count == 0 ? null : _store.Aggregate(_sessions);

        ApplyIcon();
        UpdateTooltip();
        NotifyNewlyRed();

        // Keep an open flyout in sync: rebuild on structural change, else just advance times.
        if (_flyout is not null)
        {
            string sig = string.Join("|", _sessions.Select(s => s.SessionId + ":" + s.State));
            if (sig != _flyout.Signature) ShowFlyout();
            else _flyout.RefreshTimes();
        }
    }

    private void AnimateTick()
    {
        if (_active is State.Red or State.Yellow)
        {
            _phase += (1.0 / 15.0) / 1.2;
            if (_phase > 1.0) _phase -= 1.0;
            ApplyIcon();
            _flyout?.RefreshTimes();
        }
    }

    private void ApplyIcon()
    {
        int size = 32; // tray accepts multiple sizes; 32 downscales cleanly for 16/20/24.
        double pulse = TrafficLightIcon.Pulse(_active, _phase);
        IntPtr previous = _lastHicon;
        var icon = TrafficLightIcon.RenderTrayIcon(_active, pulse, _waiting, size, out var hicon);
        _tray.Icon = icon;
        _lastHicon = hicon;
        // Destroy the previous HICON only after the new one is assigned (avoids the leak).
        TrafficLightIcon.DestroyIcon(previous);
    }

    private void UpdateTooltip()
    {
        int working = _sessions.Count(s => s.State == State.Yellow);
        int done = _sessions.Count(s => s.State == State.Green);
        string text;
        if (_sessions.Count == 0)
            text = _l.NoSessions;
        else
        {
            var parts = new List<string>();
            if (_waiting > 0) parts.Add($"{_waiting} {_l.WaitingWord}");
            if (working > 0) parts.Add($"{working} {_l.WorkingWord}");
            if (parts.Count == 0) parts.Add($"{done} {_l.DoneWord}");
            text = "Claude Traffic Light — " + string.Join("  ·  ", parts);
        }
        // NotifyIcon.Text is capped at 127 chars.
        _tray.Text = text.Length > 127 ? text[..127] : text;
    }

    private void NotifyNewlyRed()
    {
        var currentRed = _sessions.Where(s => s.State == State.Red).Select(s => s.SessionId).ToHashSet();
        var fresh = _redTracker.NewlyRed(currentRed);
        if (!AppSettings.NotificationsEnabled || fresh.Count == 0) return;

        // Notify for the most relevant freshly-red session (balloon shows one at a time).
        var session = _sessions.FirstOrDefault(s => fresh.Contains(s.SessionId));
        if (session is null) return;

        _lastNotifiedSessionId = session.SessionId;
        string body = $"{session.Project} · {PlatformLabel.Label(session.Platform)}";
        _tray.ShowBalloonTip(5000, _l.NotifyTitle, body, ToolTipIcon.Info);
    }

    private void OnBalloonClicked()
    {
        if (_lastNotifiedSessionId is null) return;
        var s = _sessions.FirstOrDefault(x => x.SessionId == _lastNotifiedSessionId);
        if (s is not null) Route(s);
    }

    // MARK: - routing

    private void Route(SessionStatus s)
    {
        var action = SessionRouter.Action(s.Platform, s.Pid, s.Cwd, s.SessionId);
        AppLauncher.Execute(action);
    }

    private void EndSession(SessionStatus s)
    {
        ProcessInfo.End(s.Pid);
        // Give the process a moment to drop its status file, then refresh (rebuilds the flyout).
        var t = new System.Windows.Forms.Timer { Interval = 400 };
        t.Tick += (_, _) => { t.Stop(); t.Dispose(); Poll(); };
        t.Start();
    }

    /// <summary>
    /// Manual, user-initiated only: this is the app's ONLY network call, fired
    /// exclusively from the "Check for Updates…" menu row — the app never phones
    /// home on its own. Newer release → open its page in the browser; otherwise
    /// a short balloon tip.
    /// </summary>
    private async void CheckForUpdates()
    {
        CloseFlyout();
        string current = typeof(TrayApp).Assembly.GetName().Version?.ToString(3) ?? "";
        string? body = null;
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
            // GitHub's API rejects requests without a User-Agent.
            http.DefaultRequestHeaders.UserAgent.ParseAdd("claude-traffic-light");
            body = await http.GetStringAsync(UpdateCheck.LatestReleaseApi);
        }
        catch { /* offline / rate-limited → fall through to the failure tip */ }

        var latest = body is null ? null : UpdateCheck.ParseLatestRelease(body);
        if (latest is null)
        {
            _tray.ShowBalloonTip(4000, "Claude Traffic Light", _l.UpdateCheckFailed, ToolTipIcon.Warning);
            return;
        }
        if (UpdateCheck.IsNewer(latest.Value.Tag, current))
        {
            try
            {
                System.Diagnostics.Process.Start(
                    new System.Diagnostics.ProcessStartInfo(latest.Value.Url) { UseShellExecute = true });
            }
            catch { /* no browser handler — nothing sane to do */ }
        }
        else
        {
            string shown = string.IsNullOrEmpty(current) ? "dev" : current;
            _tray.ShowBalloonTip(4000, "Claude Traffic Light", $"{_l.UpToDate} ({shown})", ToolTipIcon.Info);
        }
    }

    private void Shutdown()
    {
        _pollTimer.Stop();
        _animTimer.Stop();
        CloseFlyout();
        _tray.Visible = false;
        TrafficLightIcon.DestroyIcon(_lastHicon);
        _tray.Dispose();
        ExitThread();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _pollTimer.Dispose();
            _animTimer.Dispose();
            _flyout?.Dispose();
        }
        base.Dispose(disposing);
    }
}
