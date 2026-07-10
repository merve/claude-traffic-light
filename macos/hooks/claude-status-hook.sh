#!/bin/bash
# Claude Status hook — writes session status to disk on Claude Code events.
#
# Usage (called from settings.json):
#   claude-status-hook.sh <state>
#   state: yellow | red | green | end
#
# Claude Code passes JSON to the hook over stdin (session_id, cwd, ...).
# This script reads that JSON and updates ~/.claude/status/<session_id>.json.
# On "end" it removes the file (the session closed).

STATE="$1"
STATUS_DIR="$HOME/.claude/status"
mkdir -p "$STATUS_DIR"

# Read stdin JSON into a variable (we don't pipe stdin straight into python so the
# python heredoc doesn't consume it; we pass it via an env var instead).
PAYLOAD="$(cat)"

# Platform detection: figure out which environment the claude process ($PPID)
# running this hook lives in, from the process ancestry. Build the chain ONCE and
# derive both the platform and the hosting .app path from it (used to focus the
# right app on click).
build_chain() {
  local cmd; cmd=$(ps -o command= -p "$PPID" 2>/dev/null)
  local pid="$PPID" depth=0 chain="$cmd"
  while [ -n "$pid" ] && [ "$pid" -gt 1 ] && [ $depth -lt 8 ]; do
    local line; line=$(ps -o ppid=,command= -p "$pid" 2>/dev/null) || break
    chain="$chain|$line"
    pid=$(echo "$line" | awk '{print $1}' | tr -d ' ')
    depth=$((depth+1))
  done
  printf '%s' "$chain"
}
CHAIN="$(build_chain)"

detect_platform() {
  case "$CHAIN" in
    *".vscode/extensions/anthropic.claude-code"*|*"Visual Studio Code"*|*"Code Helper"*) echo "vscode";  return;;
    *".cursor/extensions/anthropic.claude-code"*|*Cursor*)                                echo "cursor";  return;;
    *"Application Support/Claude/claude-code"*|*/Applications/Claude.app/*)               echo "desktop"; return;;
    *iTerm*|*Terminal.app*|*WarpTerminal*|*Warp.app*|*ghostty*|*Alacritty*|*kitty*|*WezTerm*|*Hyper*|*tmux*) echo "terminal"; return;;
    *) echo "unknown"; return;;
  esac
}
PLATFORM="$(detect_platform)"

# Extract the path of the first .app bundle in the chain, to focus the correct app
# on click (especially for terminal sessions: iTerm/Terminal/Warp...). Preserves
# names with spaces ("Visual Studio Code.app"); takes the first (outermost) .app.
detect_app_path() {
  printf '%s\n' "$CHAIN" | tr '|' '\n' \
    | sed -nE 's#^[[:space:]]*([0-9]+[[:space:]]+)?(/.*\.app)(/.*)?$#\2#p' \
    | head -n1
}
APP_PATH="$(detect_app_path)"

# $PPID = the process running this hook = the session's claude process. When the
# session closes this PID dies; the app uses it for the liveness check.
STATE="$STATE" STATUS_DIR="$STATUS_DIR" PAYLOAD="$PAYLOAD" SESSION_PID="$PPID" SESSION_PLATFORM="$PLATFORM" SESSION_APP_PATH="$APP_PATH" /usr/bin/python3 -c '
import os, json, time

state = os.environ.get("STATE", "")
status_dir = os.environ["STATUS_DIR"]

try:
    payload = json.loads(os.environ.get("PAYLOAD", "") or "{}")
except Exception:
    payload = {}

session_id = payload.get("session_id") or "unknown"
safe = "".join(c for c in session_id if c.isalnum() or c in "-_") or "unknown"
path = os.path.join(status_dir, safe + ".json")

# The moment a tool that asks the user / waits for approval is about to run
# (PreToolUse), flip the state to red (Claude is waiting for your input).
tool = (payload.get("tool_name") or "").lower()
if state == "yellow" and any(k in tool for k in ("askuserquestion", "exitplanmode")):
    state = "red"

if state == "end":
    try:
        os.remove(path)
    except OSError:
        pass
    raise SystemExit(0)

cwd = payload.get("cwd") or ""
project = os.path.basename(cwd.rstrip("/")) if cwd else "?"

try:
    session_pid = int(os.environ.get("SESSION_PID", "0"))
except ValueError:
    session_pid = 0

platform = os.environ.get("SESSION_PLATFORM", "unknown") or "unknown"
app_path = os.environ.get("SESSION_APP_PATH", "") or ""

data = {"state": state, "project": project, "cwd": cwd,
        "ts": int(time.time()), "session_pid": session_pid,
        "platform": platform, "app_path": app_path}

tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f)
os.replace(tmp, path)
'
