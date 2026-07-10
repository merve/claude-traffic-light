#!/bin/bash
# Claude Traffic Light doctor — diagnoses the common failure points, especially after
# installing on a different machine (toolchain, code signing / notifications,
# Gatekeeper quarantine, hook + settings wiring, launch-at-login, running state).
#
# Exit code: 0 if no hard failures, 1 if any FAIL was found.
# WARN items are non-fatal but worth addressing.

cd "$(dirname "$0")"
ROOT="$PWD"
APP_NAME="Claude Traffic Light"   # display name / .app bundle
EXEC_NAME="ClaudeLight"           # binary + process name (see build-app.sh)
BUNDLE_ID="com.mervepro.claudelight"
HOOK="$HOME/.claude/hooks/claude-status-hook.sh"
SETTINGS="$HOME/.claude/settings.json"
STATUS_DIR="$HOME/.claude/status"
PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

FAIL=0
WARN=0

pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; WARN=$((WARN+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
fix()  { printf '      → %s\n' "$1"; }

echo "Claude Traffic Light doctor"
echo "=================="

# --- 1. macOS version ---
echo "System"
OSVER="$(sw_vers -productVersion 2>/dev/null || echo '?')"
OSMAJ="${OSVER%%.*}"
if [ "${OSMAJ:-0}" -ge 12 ] 2>/dev/null; then
  pass "macOS $OSVER (>= 12 required)"
else
  fail "macOS $OSVER is too old (need 12+)"
fi

# --- 2. Toolchain ---
if command -v swift >/dev/null 2>&1; then
  pass "swift found ($(swift --version 2>/dev/null | head -n1))"
else
  fail "swift not found (needed to build)"
  fix "xcode-select --install"
fi

if [ -x /usr/bin/python3 ]; then
  pass "/usr/bin/python3 present (used by the hook)"
else
  fail "/usr/bin/python3 missing — the hook cannot write status"
  fix "Install Xcode Command Line Tools: xcode-select --install"
fi

# --- 3. App bundle ---
echo "App"
APP=""
if [ -d "/Applications/$APP_NAME.app" ]; then
  APP="/Applications/$APP_NAME.app"
elif [ -d "$ROOT/$APP_NAME.app" ]; then
  APP="$ROOT/$APP_NAME.app"
fi

if [ -n "$APP" ]; then
  pass "app bundle: $APP"

  # Code signing identity must match the bundle id, or notifications break.
  IDENT="$(codesign -dv "$APP" 2>&1 | sed -nE 's/^Identifier=(.*)$/\1/p')"
  if [ "$IDENT" = "$BUNDLE_ID" ]; then
    pass "code signing identifier matches bundle id ($BUNDLE_ID)"
  else
    fail "signing identifier is '$IDENT', expected '$BUNDLE_ID' — notifications will silently fail"
    fix "Rebuild so it is signed correctly: ./build-app.sh"
  fi

  # Gatekeeper quarantine (set when the app was downloaded/copied from elsewhere).
  if xattr -p com.apple.quarantine "$APP" >/dev/null 2>&1; then
    warn "app is quarantined (Gatekeeper may block it on this machine)"
    fix "xattr -dr com.apple.quarantine \"$APP\""
  else
    pass "not quarantined by Gatekeeper"
  fi
else
  fail "$APP_NAME.app not found in /Applications or $ROOT"
  fix "Build it: ./build-app.sh"
fi

# --- 4. Hook ---
echo "Hook"
if [ -f "$HOOK" ]; then
  if [ -x "$HOOK" ]; then
    pass "hook installed and executable"
  else
    fail "hook exists but is not executable"
    fix "chmod +x \"$HOOK\""
  fi
else
  fail "hook not installed at $HOOK"
  fix "cp hooks/claude-status-hook.sh \"$HOOK\" && chmod +x \"$HOOK\""
fi

# --- 5. settings.json wiring ---
echo "settings.json"
if [ -f "$SETTINGS" ] && [ -x /usr/bin/python3 ]; then
  # Python reports "TAG|message"; the shell renders it with the right style.
  LINE="$(SETTINGS="$SETTINGS" /usr/bin/python3 - <<'PY'
import json, os
sp = os.environ["SETTINGS"]
expected = ["UserPromptSubmit", "PreToolUse", "PermissionRequest",
            "PostToolUse", "Notification", "Stop", "SessionEnd"]
try:
    s = json.load(open(sp))
except Exception:
    print("FAIL|settings.json is not valid JSON"); raise SystemExit(0)
hooks = s.get("hooks", {})
def has(event):
    for g in hooks.get(event, []):
        for h in g.get("hooks", []):
            if "claude-status-hook.sh" in h.get("command", ""):
                return True
    return False
missing = [e for e in expected if not has(e)]
print(("PASS|all hook events wired (%d)" % len(expected)) if not missing
      else ("WARN|missing hook events: %s" % ", ".join(missing)))
PY
)"
  TAG="${LINE%%|*}"; MSG="${LINE#*|}"
  case "$TAG" in
    PASS) pass "$MSG" ;;
    WARN) warn "$MSG"; fix "Re-run ./install.sh to merge the missing events" ;;
    *)    fail "$MSG" ;;
  esac
else
  fail "settings.json not found or python3 missing"
  fix "Run ./install.sh"
fi

# --- 6. Status directory ---
echo "Runtime"
if [ -d "$STATUS_DIR" ]; then
  pass "status directory exists ($STATUS_DIR)"
else
  warn "status directory missing (created on first hook run)"
  fix "mkdir -p \"$STATUS_DIR\""
fi

# --- 7. Launch at login ---
if [ -f "$PLIST" ]; then
  pass "launch-at-login LaunchAgent installed"
else
  warn "launch-at-login not set up"
  fix "./install-autostart.sh"
fi

# --- 8. Running? ---
if pgrep -x "$EXEC_NAME" >/dev/null 2>&1; then
  pass "$APP_NAME is running (pid $(pgrep -x "$EXEC_NAME" | tr '\n' ' '))"
else
  warn "$APP_NAME is not running"
  [ -n "$APP" ] && fix "open \"$APP\""
fi

# --- 9. Notification permission (cannot be read reliably from the CLI) ---
echo "Notifications"
echo "  i  Grant permission on first launch, or check:"
echo "      System Settings → Notifications → $APP_NAME (Allow Notifications = on)"
echo "  i  If notifications never appear, the usual cause is the signing-identifier"
echo "      mismatch above — fix that first, then relaunch."

echo
if [ "$FAIL" -gt 0 ]; then
  printf '\033[31mResult: %d failure(s), %d warning(s).\033[0m\n' "$FAIL" "$WARN"
  exit 1
elif [ "$WARN" -gt 0 ]; then
  printf '\033[33mResult: healthy, %d warning(s).\033[0m\n' "$WARN"
  exit 0
else
  printf '\033[32mResult: all checks passed.\033[0m\n'
  exit 0
fi
