#!/bin/bash
# Uninstalls ClaudeStatus: launch-at-login, the app, the hook script and the status
# directory. Safely strips our entries from the "hooks" block in settings.json
# (with a backup).
set -uo pipefail

APP_NAME="Claude Traffic Light"   # display name / .app bundle
EXEC_NAME="ClaudeLight"           # binary + process name (see build-app.sh)
LABEL="com.mervepro.claudelight"

echo "==> Removing launch-at-login…"
# Clean up both the new and old (ClaudeStatus) labels.
for L in "$LABEL" "com.mervepro.claudestatus"; do
  launchctl unload "$HOME/Library/LaunchAgents/$L.plist" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/$L.plist"
done

echo "==> Quitting the app…"
pkill -x "$EXEC_NAME" 2>/dev/null || true
pkill -x "ClaudeStatus" 2>/dev/null || true

echo "==> Removing the app and hook…"
rm -rf "/Applications/$APP_NAME.app" "$(dirname "$0")/$APP_NAME.app"
# Clean up earlier names too (ClaudeLight, ClaudeStatus).
rm -rf "/Applications/ClaudeLight.app" "$(dirname "$0")/ClaudeLight.app"
rm -rf "/Applications/ClaudeStatus.app" "$(dirname "$0")/ClaudeStatus.app"
rm -f "$HOME/.claude/hooks/claude-status-hook.sh"
rm -rf "$HOME/.claude/status"

echo "==> Stripping hooks from settings.json…"
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak.claudestatus.$(date +%s)"
  SETTINGS="$SETTINGS" /usr/bin/python3 - <<'PY'
import json, os
sp = os.environ["SETTINGS"]
try:
    s = json.load(open(sp))
except Exception:
    raise SystemExit(0)
hooks = s.get("hooks", {})
for event in list(hooks.keys()):
    kept = []
    for g in hooks[event]:
        cmds = [h.get("command", "") for h in g.get("hooks", [])]
        if any("claude-status-hook.sh" in c for c in cmds):
            continue  # our hook group → drop it
        kept.append(g)
    if kept:
        hooks[event] = kept
    else:
        del hooks[event]
if hooks:
    s["hooks"] = hooks
else:
    s.pop("hooks", None)
json.dump(s, open(sp, "w"), indent=2)
print("    OK: hooks removed (backup created)")
PY
fi

echo "✅ Uninstall complete."
