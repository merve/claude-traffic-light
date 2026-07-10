# Claude Traffic Light 🚦

**Languages:** **English** · [Türkçe](README.tr.md)

A tiny macOS menu-bar app that shows [Claude Code](https://claude.com/claude-code)'s
status as a traffic light, always visible in the top-right menu bar (like RunCat).

- 🟡 **Yellow** — Claude is working / writing code (animated pulse)
- 🔴 **Red** — Claude asked a question / needs permission / is waiting for you (animated)
- 🟢 **Green** — Claude finished
- ⚫ **Off** — no active sessions (no light lit)

With multiple Claude sessions open, the menu-bar icon shows the **most
attention-worthy** state (priority: red > yellow > green). If more than one session
is waiting on you, a count badge appears next to the icon. Click the icon to see
each session on its own row.

> Works with **any language** — the UI localizes to your system language and falls
> back to English. (See [Languages](#languages).)

## How it works

Two pieces:

1. **Claude Code hooks** — on certain events, Claude Code runs
   `~/.claude/hooks/claude-status-hook.sh` (configured in `~/.claude/settings.json`).
   The script writes a per-session status file at `~/.claude/status/<session_id>.json`.
2. **Menu-bar app** (`Claude Traffic Light.app`) — reads those files ~once a second and
   updates the traffic light.

No network, no dependencies beyond the Swift standard library + AppKit. The hook
parses its JSON input with the system `python3`.

## Floating desktop widget (optional)

Besides the menu-bar icon, there's a **floating widget** (`Claude Traffic Widget.app`)
— a small, borderless panel you can drag anywhere on the screen. Same vertical
traffic light (red top / yellow mid / green bottom) as the [Windows
port](../windows/), plus a live session list next to it.

- **Drag anywhere** — grab the title bar (or the light itself) and drop it wherever
  you want on the desktop.
- **Pin (always-on-top)** or let it sit like a normal window — toggle from the 📌 in
  the title bar or the right-click menu.
- **Collapse** to just the traffic light (click the light, or the ‹ chevron) — it
  becomes a small, resizable badge; drag any edge/corner to resize (aspect-locked).
  **Expand** again the same way to bring the session list back.
- Click a session row to jump to it (same VS Code / Cursor / terminal / Claude
  desktop routing as the menu bar app); the ✕ ends the session.
- Right-click for **Show list**, **Always on top**, **Open at Login**, **Close widget**.
- Read-only: it never touches hooks or `settings.json`, so it runs fine alongside
  (or instead of) the menu-bar app — position, pin state and expanded/collapsed
  state persist independently between launches.

Build it with:

```bash
./build-widget-app.sh   # → Claude Traffic Widget.app
```

## Install (one command)

```bash
git clone https://github.com/merve/claude-traffic-light.git
cd claude-traffic-light/macos
./install.sh
```

This does everything: builds the app, installs the hook, merges the hooks into
`~/.claude/settings.json` (backing it up first, without touching your existing
settings), creates the status folder, sets up launch-at-login, and starts the app.

**Requirements:** macOS 12+ and the Xcode Command Line Tools (`swift`). If missing:

```bash
xcode-select --install
```

## Installing on another Mac

1. **Copy this folder** to the target Mac (AirDrop, `git clone`, USB, zip — anything).
   You don't need to copy `.build/` or `Claude Traffic Light.app`; the script rebuilds them.
2. In a terminal, `cd` into the folder and run:
   ```bash
   ./install.sh
   ```
3. The traffic light appears in the menu bar. Open a new Claude Code session and the
   colors come alive.

> **Gatekeeper note:** the app is unsigned. If you move a prebuilt `.app` around
> (instead of building it in place), macOS may say "developer cannot be verified."
> Building in place via `install.sh` avoids this. If it happens: right-click the app
> → **Open**, or run `xattr -dr com.apple.quarantine "Claude Traffic Light.app"`.

<details>
<summary>Manual install (without the script)</summary>

```bash
./build-app.sh                                   # 1) build
mkdir -p ~/.claude/hooks                          # 2) install the hook
cp hooks/claude-status-hook.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/claude-status-hook.sh
# 3) merge the "hooks" block from hooks/settings-snippet.json into
#    ~/.claude/settings.json BY HAND (keep your existing settings),
#    or use the merge step inside install.sh
mkdir -p ~/.claude/status                          # 4) status folder
./install-autostart.sh                             # 5) launch at login (optional)
open "./Claude Traffic Light.app"                             # 6) run
```
</details>

## Languages

The app localizes to your **system language** automatically and falls back to
**English** for unsupported ones. Built-in: English, Turkish, Spanish, German,
French, Italian, Portuguese, Russian, Japanese, Chinese (Simplified), Korean.

To add a language, add one row keyed by its language code to the `tables` dictionary
in [`Sources/ClaudeStatus/Localization.swift`](Sources/ClaudeStatus/Localization.swift),
then `./build-app.sh`. Test with:

```bash
./.build/release/ClaudeStatus --strings -AppleLanguages "(de)"
```

## Clicking a session row

Clicking a session row opens that chat **on the platform where it's actually running**:

- **VS Code** session → focuses its VS Code window at the project
- **Cursor** session → focuses Cursor at the project
- **Claude desktop** session → opens it via the `claude://resume?session=<id>` deep link
- **terminal / unknown** → falls back to the Claude desktop deep link

The platform is detected by the hook from the session's process ancestry and stored
in the status file. Hold **⌥ Option** while clicking to force-open the project folder
in your editor instead.

For **Terminal.app** sessions specifically, activating the app by path alone would
just raise whatever window macOS last used — wrong when several Claude sessions run
in separate tabs/windows of Terminal.app. Instead the app resolves the session's
controlling tty (`ps -o tty=` on the session's PID, parsed by `TTYDevice.swift`) and
asks Terminal.app (via AppleScript) which tab has that tty, so it raises the exact
tab running that session. Other terminal apps (iTerm2, etc.) fall back to plain
app activation.

## Status mapping

| Claude Code hook            | Meaning                                          | Color |
|-----------------------------|--------------------------------------------------|-------|
| `UserPromptSubmit`          | Prompt sent, work started                        | 🟡    |
| `PreToolUse`                | A tool is running                                | 🟡    |
| `PreToolUse` (question tools) | AskUserQuestion / ExitPlanMode → waiting on you | 🔴    |
| `PermissionRequest`         | A tool approval dialog is shown → waiting on you | 🔴    |
| `PostToolUse`               | Tool finished (e.g. after you approve) → working | 🟡    |
| `Notification`              | Fallback signal — waiting on you, or long idle   | 🔴    |
| `Stop`                      | Response finished                                | 🟢    |
| `SessionEnd`                | Session ended                                    | (removed) |

When there are no sessions, **no light is lit** (off). When a chat closes, the app
notices the session's process (PID) is no longer alive, drops the entry, and deletes
its stale status file — so the list stays clean even if `SessionEnd` doesn't fire
(e.g. the window was closed abruptly).

## Notifications

Whenever a session turns **red** (waiting on you), the app posts a native macOS
notification — regardless of platform, so you get alerted for VS Code / Cursor /
terminal sessions too, not just the Claude desktop app. It fires only on the
**transition** into red (once per session, not every second), and clicking the
notification opens that session. Toggle it from the menu (**Notifications**). macOS
asks for notification permission on first launch — allow it, or nothing shows.

## Development

Code is split so the logic is testable without AppKit:

- **`Sources/ClaudeStatusCore/`** — pure Foundation logic (a library target):
  status reading / aggregation / PID liveness (`StatusStore.swift`), click-routing
  decisions (`SessionRouter.swift`), red→notify transition tracking
  (`RedTransitionTracker.swift`), the `ps`-output → tty-path parser used to focus the
  right Terminal.app tab (`TTYDevice.swift`), platform labels, and languages
  (`Localization.swift`). Also the widget's window/layout geometry — expand/collapse
  sizing (`WidgetLayout.swift`) and aspect-locked drag-resize (`WidgetResize.swift`)
  — kept here (not in `ClaudeWidget`) specifically so it's unit-testable.
- **`Sources/ClaudeStatus/`** — the AppKit app: icon drawing/animation
  (`TrafficLightIcon.swift`), menu / timers / notifications (`AppDelegate.swift`).
- **`Sources/ClaudeWidget/`** — the floating widget: vertical traffic light +
  drag/edge-resize (`VerticalTrafficLightView.swift`), title bar
  (`WidgetTitleBarView.swift`), session row (`WidgetSessionRowView.swift`),
  window/poll/routing/context-menu (`WidgetController.swift`, `WidgetWindow.swift`),
  and its own persisted prefs (`WidgetSettings.swift`).

Commands:

- Rebuild: `swift build -c release`, or `./build-app.sh` (menu bar) /
  `./build-widget-app.sh` (widget) to package + ad-hoc sign.
- Debug modes: `ClaudeStatus --render <color|off> out.png [scale]` (dump the
  menu-bar icon), `ClaudeStatus --appicon out.png [size]` (dump the app icon —
  also used by `build-widget-app.sh` to generate the widget's `.icns`),
  `ClaudeStatus --preview-menu out.png` (dump the styled dropdown), `ClaudeStatus
  --strings [-AppleLanguages "(code)"]` (print the active language's strings).

### Tests

```bash
swift test
```

Unit tests live in `Tests/ClaudeStatusCoreTests/` and cover the core logic:
JSON parsing & field fallbacks, invalid/unknown-state files being skipped,
PID-liveness dropping dead sessions (and deleting their files), old-format
staleness, red-first sorting, aggregation priority, the notification
transition tracker (seed / new / stays-red / re-enter), platform labels, that
every language table is fully populated, the `ps -o tty=` → `/dev/ttys000`
parser used for Terminal.app tab matching, and the floating widget's
aspect-locked collapsed-resize geometry (edge/corner anchoring + min/max
clamping).

The widget's expand/collapse geometry (`WidgetLayout.swift` /
`WidgetLayoutTests.swift`) is also pure Foundation code — `WidgetController` computes
its actual window/subview sizes through it, so these tests aren't just a mirror.
They pin down the must-not-regress behaviors: every session gets a row with no cap,
height grows by exactly one row per session above a sane floor, rows stay
vertically centered and never clip, the collapsed icon stays aspect-locked across
its clamp range, and toggling expanded/collapsed preserves the window's top-left
corner (the regression class behind a bug where the widget briefly jumped to the
top-left when the list was opened/closed).

> Note: the menu-bar timers run in `.common` run-loop mode so the light keeps
> updating and pulsing **while the menu is open** (default-mode timers freeze
> during menu tracking). The menu is a persistent object refreshed via its
> delegate — never reassigned while open.

## Distribute as a DMG

```bash
./build-dmg.sh   # produces Claude Traffic Light.dmg
```

The DMG is drag-and-drop: it contains `Claude Traffic Light.app` + an `Applications`
symlink. The app **self-installs on first launch** — it bundles the hook and
settings snippet and, on launch, installs the hook into `~/.claude/hooks`, merges
the hooks into `~/.claude/settings.json` (idempotent, with a backup), creates the
status directory, and — only when run from `/Applications` — registers
launch-at-login. No `install.sh` needed for DMG users.

> **Gatekeeper caveat:** the app is *ad-hoc signed*, not Developer-ID signed or
> notarized. On a machine it was **downloaded** to, macOS quarantines it and, on
> first open, shows *"Claude Traffic Light can't be opened because Apple cannot
> check it for malicious software."* Two ways past it — on macOS 15 (Sequoia) and
> later the old right-click → Open shortcut usually no longer works, so prefer these:
>
> 1. **System Settings → Privacy & Security** → scroll down → click **"Open
>    Anyway"**, then confirm. (Once; afterwards it opens normally.)
> 2. Or in Terminal:
>    `xattr -dr com.apple.quarantine "/Applications/Claude Traffic Light.app"`
>
> Removing this step entirely requires an Apple Developer ID + notarization.
> (Building locally with `./build-app.sh` / `./install.sh` is never quarantined.)

The floating widget has its own DMG builder, `./build-widget-dmg.sh` (produces
`Claude Traffic Widget.dmg`) — same drag-and-drop layout and Gatekeeper caveat as
above. Unlike the menu-bar app it never installs anything (see [Floating desktop
widget](#floating-desktop-widget-optional)), so recipients still need the menu-bar
app's DMG (or `install.sh`) run at least once first.

## Troubleshooting

Run the diagnostic — it checks every common failure point (especially useful
after installing on a different machine):

```bash
./doctor.sh
```

It verifies: macOS version, Swift/CLT, `/usr/bin/python3`, the app bundle, the
**code-signing identifier matching the bundle id** (a mismatch silently breaks
notifications), Gatekeeper quarantine, the hook install, the `settings.json` hook
wiring, the status directory, launch-at-login, and whether the app is running —
printing an actionable fix for anything wrong.

Common cases:

- **No notifications at all.** The signing identifier must equal
  `com.mervepro.claudelight`; `./build-app.sh` signs it correctly. Then allow
  notifications in System Settings → Notifications → Claude Traffic Light.
- **"App can't be opened" / "Apple cannot check it" (Gatekeeper).** Only happens
  on a machine it was downloaded/copied to. Open **System Settings → Privacy &
  Security → "Open Anyway"**, or run
  `xattr -dr com.apple.quarantine "/Applications/Claude Traffic Light.app"`. On
  recent macOS the right-click → Open trick usually no longer works.
- **Light never turns on.** Ensure the hook is wired: `./install.sh` (idempotent),
  and check `./doctor.sh`.

## Uninstall

One command (removes launch-at-login, the app, the hook, and the hooks from
`~/.claude/settings.json`):

```bash
./uninstall.sh
```

## License

[MIT](LICENSE) © Merve Ağca
