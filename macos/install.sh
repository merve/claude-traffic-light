#!/bin/bash
# Claude Traffic Light one-command install:
#   1) builds the app (if needed)
#   2) copies the hook script into ~/.claude/hooks/
#   3) merges the hooks into ~/.claude/settings.json (with a backup)
#   4) creates the ~/.claude/status directory
#   5) sets up launch-at-login
#   6) starts the app
#
# Requirements: macOS 12+, Xcode Command Line Tools (swift). Check: `swift --version`
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$PWD"
APP_NAME="Claude Traffic Light"   # display name / .app bundle
EXEC_NAME="ClaudeLight"           # binary + process name (see build-app.sh)

echo "==> 1/6 Building the app…"
if ! command -v swift >/dev/null 2>&1; then
  echo "ERROR: 'swift' not found. Install Xcode Command Line Tools: xcode-select --install" >&2
  exit 1
fi
./build-app.sh >/dev/null
echo "    OK: $ROOT/$APP_NAME.app"

echo "==> 2/6 Installing the hook script…"
mkdir -p "$HOME/.claude/hooks"
cp "hooks/claude-status-hook.sh" "$HOME/.claude/hooks/claude-status-hook.sh"
chmod +x "$HOME/.claude/hooks/claude-status-hook.sh"
echo "    OK: ~/.claude/hooks/claude-status-hook.sh"

echo "==> 3/6 Merging hooks into settings.json…"
SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.claudestatus.$(date +%s)"
SNIPPET="$ROOT/hooks/settings-snippet.json" SETTINGS="$SETTINGS" /usr/bin/python3 - <<'PY'
import json, os
sp = os.environ["SETTINGS"]
try:
    s = json.load(open(sp))
except Exception:
    s = {}
snip = json.load(open(os.environ["SNIPPET"]))
s.setdefault("hooks", {})
def cmds(lst):
    out = set()
    for g in lst:
        for h in g.get("hooks", []):
            out.add(h.get("command", ""))
    return out
for event, arr in snip["hooks"].items():
    existing = s["hooks"].get(event, [])
    have = cmds(existing)
    for g in arr:
        if cmds([g]) & have:
            continue
        existing.append(g)
    s["hooks"][event] = existing
json.dump(s, open(sp, "w"), indent=2)
print("    OK: hooks added (backup: settings.json.bak.claudestatus.*)")
PY

echo "==> 4/6 Status directory…"
mkdir -p "$HOME/.claude/status"
echo "    OK: ~/.claude/status"

echo "==> 5/6 Launch at login…"
./install-autostart.sh >/dev/null
echo "    OK: LaunchAgent installed"

echo "==> 6/6 Starting the app…"
pkill -x "$EXEC_NAME" 2>/dev/null || true
sleep 1
open "$ROOT/$APP_NAME.app"

echo ""
echo "✅ Install complete. A traffic light should appear in the menu bar."
echo "   Colors come alive when you open a new Claude Code session."
echo "   Allow the notification permission prompt on first launch (for red alerts)."
echo "   To verify everything is wired correctly, run:  ./doctor.sh"
echo "   To move the app into /Applications, move it and then run ./install-autostart.sh."
