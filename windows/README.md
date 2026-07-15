# Claude Traffic Light — Windows

A system-tray traffic light for Claude Code sessions on Windows. It watches your
local `%USERPROFILE%\.claude\status\` folder and shows, at a glance, whether any
open Claude Code session needs you:

- 🟢 **green** — done, your turn
- 🟡 **yellow** — working
- 🔴 **red** — waiting on you (asking a question / permission)

Multiple sessions collapse to the highest-priority color (red > yellow > green).
Click the icon for a per-session menu; click a session to jump to it (VS Code /
Cursor / terminal / Claude desktop). A balloon fires when a session turns red.

**No network, no tokens — reads local files only, fully offline.** It shares the
exact same `~/.claude/status` contract as the macOS app, so both can run side by side.

This is the Windows port of the macOS menu-bar app. Behavior contract:
[`../WINDOWS-PORT-SPEC.md`](../WINDOWS-PORT-SPEC.md).

---

## Tray position (bottom-right vs bottom-left)

Windows only lets a `NotifyIcon` live in the **notification area (bottom-right, by
the clock)** — there is no supported API to place a tray icon in the left/center
taskbar button area. This app uses the notification area, matching the macOS
menu-bar placement. If you want an indicator you can park anywhere on screen
(including bottom-left), see the always-on-top desktop widget below.

---

## Requirements

- Windows 10/11
- [.NET SDK 9](https://dotnet.microsoft.com/download) to build (end users need nothing
  if you publish self-contained — see below)

## Build & run

```powershell
cd windows\ClaudeTrafficLight
dotnet build -c Release
.\bin\Release\net9.0-windows\ClaudeTrafficLight.exe
```

Running the app the first time auto-installs itself (idempotent): it merges the
hook groups into `~/.claude/settings.json` (backup saved as `settings.json.bak`),
creates the status dir, and registers autostart.

### Publish a single self-contained exe (users install nothing)

```powershell
cd windows\ClaudeTrafficLight
dotnet publish -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true
# → bin\Release\net9.0-windows\win-x64\publish\ClaudeTrafficLight.exe
```

Copy that single `ClaudeTrafficLight.exe` anywhere stable (e.g.
`%LOCALAPPDATA%\ClaudeTrafficLight\`) and run it once to install.

> SmartScreen may warn on first run because the exe is unsigned — choose
> *More info → Run anyway*.

## Command-line modes

| Command | What it does |
|---|---|
| `ClaudeTrafficLight.exe` | Run the tray app (also self-installs hooks + autostart on every launch — cheap and idempotent). |
| `ClaudeTrafficLight.exe --hook <state>` | Hook mode — called by Claude Code on events; reads the JSON payload from stdin and updates the status file, then exits. `<state>` = `yellow` \| `red` \| `green` \| `end`. |
| `ClaudeTrafficLight.exe --uninstall` | Remove our hook groups from `settings.json` and the autostart entry. |
| `ClaudeTrafficLight.exe --render <red\|yellow\|green\|off> <out.png> [size] [waiting]` | Debug: dump the tray icon to a PNG. |
| `ClaudeTrafficLight.exe --testnotify` | Debug: show one balloon notification for a few seconds, isolated from polling/animation. |
| `ClaudeTrafficLight.exe --preview-menu <out.png> [dark\|light]` | Debug: compose the themed flyout menu into a PNG. |
| `ClaudeTrafficLight.exe --menuprobe <out.txt>` | Debug: build the menu off-screen and dump its real geometry as text. |
| `ClaudeTrafficLight.exe --capture-flyout <out.png> [dark\|light]` | Debug: capture the real flyout form (not a proxy) to a PNG. |

## How it hooks into Claude Code

The **same exe is also the hook** (`--hook`), so there's no separate script and no
console-window flash on every tool call. Install merges these groups into
`~/.claude/settings.json`:

| Event | State |
|---|---|
| `UserPromptSubmit`, `PreToolUse`, `PostToolUse` | `yellow` |
| `PostToolUseFailure`, `PermissionDenied` | `yellow` |
| `PermissionRequest`, `Notification`* | `red` |
| `SubagentStart` | `subagent-start` (repaints `yellow`, tracks the agent id) |
| `SubagentStop` | `subagent-stop` (clears the agent id, color untouched) |
| `Stop`, `StopFailure` | `green`** |
| `SessionEnd` | `end` (deletes the file) |

Plus a **red override**: if a `yellow` event carries a `tool_name` of
`AskUserQuestion` / `ExitPlanMode`, it's promoted to `red` (Claude is waiting).

\* `Notification` is filtered by an inverted allowlist: only
`permission_prompt`/`elicitation_dialog`/`agent_needs_input`/mid-turn-idle go
red; every other type — including unknown or missing — repaints nothing, so a
future notification type can never fake a mid-turn red. Full detail + the
red-trust gate (F3/F5/F9) and subagent tracking (F11): see
[`WINDOWS-PORT-SPEC.md`](WINDOWS-PORT-SPEC.md).

\** Unless a background subagent is still active (stays `yellow`) or the
reply's last sentence ends in a real question (goes `red`).

The merge is idempotent (running install again won't duplicate entries) and
identifies our groups by the exe reference in the command, so it survives moving
the exe.

## Tests

```powershell
dotnet test ClaudeTrafficLight.Tests
dotnet test ClaudeTrafficWidget.Tests
```

`ClaudeTrafficLight.Tests/` covers the portable `Core/` logic: status loading,
liveness/staleness, aggregation and priority ordering (`StatusStoreTests.cs`),
click-routing decisions (`SessionRouterTests.cs`), the red-transition notification
tracker (`RedTransitionTrackerTests.cs`), and that every language table is fully
populated (`LocalizationTests.cs`). `ClaudeTrafficWidget.Tests/` covers the
widget's aspect-locked collapsed-resize geometry (`WidgetResizeTests.cs`) — the
pure `WidgetResize` logic behind its `WM_SIZING` handler.

## Where things live

- Status files: `%USERPROFILE%\.claude\status\<session_id>.json` (atomic writes)
- Hook config: `%USERPROFILE%\.claude\settings.json`
- Notifications on/off: `HKCU\Software\ClaudeTrafficLight`
- Autostart: `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\ClaudeTrafficLight`

## Uninstall

```powershell
ClaudeTrafficLight.exe --uninstall
```

Then delete the exe. (Removes the hook groups and the autostart entry; leaves your
other `settings.json` content untouched.)

## Project layout

```
ClaudeTrafficLight/
├─ Program.cs                 entry: --hook / --uninstall / tray / debug modes
├─ Bootstrap.cs               settings.json merge + autostart (§10)
├─ Core/                      portable logic (no WinForms) — mirrors ClaudeStatusCore
│  ├─ StatusStore.cs          State, SessionStatus, load, aggregate, liveness (§4)
│  ├─ SessionRouter.cs        click-routing decision (§5)
│  ├─ RedTransitionTracker.cs notification transition + PlatformLabel (§6)
│  ├─ Localization.cs         all language tables (§9)
│  ├─ AppSettings.cs          notifications toggle (registry)
│  └─ Paths.cs                %USERPROFILE%\.claude locations
├─ Hook/HookRunner.cs         --hook: stdin JSON → status file (§3)
├─ Platform/                  Win32 glue
│  ├─ ProcessTree.cs          ancestry walk → platform + session pid (§3.3/§12.2)
│  ├─ ProcessInfo.cs          liveness / end / focus-window (§4.2/§12.3)
│  ├─ AppLauncher.cs          execute the routing decision (§5/§12.3)
│  └─ NativeMethods.cs        P/Invoke (toolhelp, user32)
└─ UI/                        WinForms tray + custom flyout menu
   ├─ TrayApp.cs              NotifyIcon, flyout, timers, notifications (§6/§8)
   ├─ TrafficLightIcon.cs     vertical traffic-light drawing (§7)
   ├─ MenuFlyout.cs           borderless popup form hosting the themed menu controls
   ├─ MenuTheme.cs            light/dark palette for the flyout, from the Windows theme
   ├─ HeaderControl.cs        title + summary counter + close ✕ (§8.1)
   ├─ SessionRowControl.cs    styled session row + close button (§8.3)
   ├─ ActionRowControl.cs     themed Notifications / Refresh / Quit rows
   ├─ HintControl.cs          footer hint ("Click a session to jump to it")
   ├─ RelativeTime.cs         "58s ago"
   ├─ DebugRender.cs          --render helper
   ├─ PreviewMenu.cs          --preview-menu / --capture-flyout helpers
   ├─ MenuProbe.cs            --menuprobe helper
   └─ NotifyTest.cs           --testnotify helper
```

## Floating desktop widget (optional)

`ClaudeTrafficWidget.exe` is a standalone, always-on-top desktop widget — a small,
borderless panel you can drag anywhere on screen. Same vertical traffic light as
the tray icon, plus a live session list. It's a **read-only viewer**: it reuses the
tray app's `Core/` and `SessionRowControl`/`MenuTheme` (linked in via the `.csproj`,
not a project reference) but never installs hooks or touches `settings.json` — it
needs `ClaudeTrafficLight.exe` run at least once first so the hook is wired up and
`~/.claude/status` gets populated. Runs fine alongside the tray app, or on its own.

```powershell
cd windows\ClaudeTrafficWidget
dotnet build -c Release
.\bin\Release\net9.0-windows\ClaudeTrafficWidget.exe
```

Publish a self-contained exe the same way as the tray app:

```powershell
cd windows\ClaudeTrafficWidget
dotnet publish -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true
# → bin\Release\net9.0-windows\win-x64\publish\ClaudeTrafficWidget.exe
```

Debug mode: `ClaudeTrafficWidget.exe --capture <out.png> [dark|light]` composes the
widget chrome + rows into a PNG using in-memory sessions, without touching the real
status directory.

```
ClaudeTrafficWidget/
├─ Program.cs           entry: --capture debug mode / single-instance / run
├─ WidgetForm.cs         the borderless window: layout, poll, routing, drag/resize
├─ TrafficLightPanel.cs  the vertical traffic light (left rail / collapsed housing)
├─ WidgetTitleBar.cs     title bar: drag handle, pin toggle, close ✕
├─ WidgetResize.cs       pure geometry for aspect-locked collapsed resize (WM_SIZING)
├─ WidgetNative.cs       P/Invoke for click-drag move + resize hit-testing
├─ WidgetSettings.cs     persisted prefs — HKCU\Software\ClaudeTrafficWidget
└─ WidgetPreview.cs      --capture helper
```
