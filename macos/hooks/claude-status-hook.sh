#!/bin/bash
# Claude Status hook — writes session status to disk on Claude Code events.
#
# Usage (called from settings.json):
#   claude-status-hook.sh <state>
#   state: yellow | red | green | end | subagent-start | subagent-stop
#
# Claude Code passes JSON to the hook over stdin (session_id, cwd, ...).
# This script reads that JSON and updates ~/.claude/status/<session_id>.json.
# On "end" it removes the file (the session closed).

STATE="$1"
STATUS_DIR="${CLAUDE_STATUS_DIR:-$HOME/.claude/status}"
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

# Controlling terminal of the claude process. A real tty ("ttys012") means the
# session is visible in a terminal window; "??" means headless — driven over
# pipes by an IDE extension or a background resume, with no guaranteed UI.
SESSION_TTY="$(ps -o tty= -p "$PPID" 2>/dev/null | tr -d '[:space:]')"

# $PPID = the process running this hook = the session's claude process. When the
# session closes this PID dies; the app uses it for the liveness check.
STATE="$STATE" STATUS_DIR="$STATUS_DIR" PAYLOAD="$PAYLOAD" SESSION_PID="$PPID" SESSION_PLATFORM="$PLATFORM" SESSION_APP_PATH="$APP_PATH" SESSION_TTY="$SESSION_TTY" /usr/bin/python3 <<'PY'
import os, json, time, fcntl

state = os.environ.get("STATE", "")
status_dir = os.environ["STATUS_DIR"]

try:
    payload = json.loads(os.environ.get("PAYLOAD", "") or "{}")
except Exception:
    payload = {}

session_id = payload.get("session_id") or "unknown"
safe = "".join(c for c in session_id if c.isalnum() or c in "-_") or "unknown"
path = os.path.join(status_dir, safe + ".json")

if state == "end":
    for p in (path, path + ".lock"):
        try:
            os.remove(p)
        except OSError:
            pass
    raise SystemExit(0)

# Concurrency: with parallel subagents, several hook processes fire at once for the
# SAME session file. The whole read-modify-write below runs under an exclusive lock,
# and the temp file is per-writer — a shared ".tmp" name let one process install
# another's HALF-WRITTEN json (torn write), which the app then couldn't parse (row
# vanished) and the next hook read as "no previous file" (cwd pin reset).
_lock = open(path + ".lock", "w")
fcntl.flock(_lock, fcntl.LOCK_EX)

def write_atomic(obj):
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w") as f:
        json.dump(obj, f)
    os.replace(tmp, path)

prev = {}
try:
    with open(path) as f:
        prev = json.load(f)
except Exception:
    prev = {}

# --- F11: subagent tracking -----------------------------------------------------
# A background subagent turn ends its OWN Stop event, painting the shared session
# green even though the user's actual request is still in flight; the next tool
# event from the agent flips it back yellow. To the user this reads as a single
# piece of work — the light should not flicker green in the middle of it. So we
# track active subagent ids on the status file and, at the real (main-turn) Stop,
# stay yellow while any are still running. Entries are timestamped and pruned
# after STALE_AFTER so a missed SubagentStop can't wedge the light yellow forever.
STALE_AFTER = 30 * 60  # keep in sync with StatusStore.staleAfter

def pruned_subagents(raw, now):
    if not isinstance(raw, dict):
        return {}
    return {k: v for k, v in raw.items()
            if isinstance(v, (int, float)) and now - v <= STALE_AFTER}

now = time.time()
subagents = pruned_subagents(prev.get("subagents"), now)

# subagent-stop never touches color or any other field — it only clears the id
# from the active set. If there is nothing on disk yet there is nothing to update.
if state == "subagent-stop":
    agent_id = payload.get("agent_id") or ""
    if agent_id:
        subagents.pop(agent_id, None)
    if not prev:
        raise SystemExit(0)
    out = dict(prev)
    out["subagents"] = subagents
    write_atomic(out)
    raise SystemExit(0)

# subagent-start always repaints yellow (background work just resumed) regardless
# of whatever state was there before, then falls through the normal pipeline below
# so project/cwd/platform/trust are (re)derived exactly like any other write.
if state == "subagent-start":
    agent_id = payload.get("agent_id") or f"_anon_{time.time_ns()}"
    subagents[agent_id] = now
    state = "yellow"

event = payload.get("hook_event_name") or ""

# The moment a tool that asks the user / waits for approval is about to run
# (PreToolUse), flip the state to red (Claude is waiting for your input).
# ONLY on PreToolUse: PostToolUse carries the same tool_name but fires when the
# user has just ANSWERED — repainting red there kept the light red until the next
# unrelated event, long after the question was gone.
tool = (payload.get("tool_name") or "").lower()
if state == "yellow" and event == "PreToolUse" and any(k in tool for k in ("askuserquestion", "exitplanmode")):
    state = "red"

# --- Plain-text questions -----------------------------------------------------
# AskUserQuestion (multiple-choice) goes red via PreToolUse above, but Claude
# often asks in prose and just stops — the only signal is the actual final
# message. On Stop, if the last assistant text ends with a question, the user
# is being asked something → red, not green. Any parse problem → keep green.
if state == "green" and event == "Stop":
    def last_assistant_text(tp):
        try:
            size = os.path.getsize(tp)
            with open(tp, "rb") as f:
                f.seek(max(0, size - 262144))  # tail is enough; transcripts are append-only
                tail = f.read().decode("utf-8", "replace")
        except Exception:
            return ""
        text = ""
        # split on "\n" only (JSONL's real line separator) — Python's splitlines()
        # also breaks on U+2028/U+2029, which are legal, unescaped inside a JSON
        # string and would otherwise cut a record in half and lose the last message.
        for line in tail.split("\n"):
            line = line.rstrip("\r")
            try:
                obj = json.loads(line)
            except Exception:
                continue
            if obj.get("type") != "assistant":
                continue
            msg = obj.get("message") or {}
            parts = [b.get("text", "") for b in (msg.get("content") or [])
                     if isinstance(b, dict) and b.get("type") == "text"]
            if any(p.strip() for p in parts):
                text = "\n".join(parts)  # keep overwriting → last one wins
        return text

    tail_text = last_assistant_text(payload.get("transcript_path") or "").rstrip()
    # markdown/quote closers: backtick, straight/curly double+single quotes,
    # guillemet, CJK bracket closers, fullwidth paren close (F6 — a closing
    # quote right after the "?" must not hide the question mark from endswith()).
    CLOSERS = set("*_)]}`") | {'"', "'", "’", "»",
                                "”", "‘", "」", "』", "）"}
    while tail_text and tail_text[-1] in CLOSERS:
        tail_text = tail_text[:-1].rstrip()

    if tail_text.endswith("?") or tail_text.endswith("？"):
        # A trailing "?" alone isn't enough: "...or should I drop the table?" also
        # ends with "?" but is a real blocking question, not a courtesy close. So
        # we anchor the courtesy check to the LAST SENTENCE only (F1) — split on
        # real sentence enders, not an arbitrary trailing character window — and
        # require the courtesy phrase to sit at the START of that sentence, with
        # the whole sentence staying close to the phrase's own length. That accepts
        # "Anything else?" / "Başka bir şey var mı?" but rejects compound questions
        # that merely contain a courtesy-shaped substring in the middle
        # ("Soll ich sonst noch die Prod-Config ändern?").
        SENTENCE_ENDERS = ".!?？。\n"

        def last_sentence(text):
            end = len(text)
            start = 0
            # scan backward from the char BEFORE the final one (the final char is
            # the question mark itself, not a sentence boundary)
            for i in range(end - 2, -1, -1):
                if text[i] in SENTENCE_ENDERS:
                    start = i + 1
                    break
            return text[start:end].strip()

        sentence = last_sentence(tail_text).casefold().replace("̇", "")
        courtesy = (
            # en
            "anything else", "is there anything", "any other question",
            "what else can i",
            # tr
            "başka bir şey var m", "başka istediğin",
            "başka bir isteğ", "başka sorunuz",
            "yardımcı olabileceğim başka",
            # es
            "algo más", "alguna otra cosa",
            # de
            "noch etwas", "sonst noch",
            # fr
            "autre chose",
            # it
            "qualcos'altro", "altre domande",
            # pt
            "mais alguma coisa", "algo mais",
            # ru (both yo/e spellings)
            "что-нибудь ещё", "что-нибудь еще",
            "что-то ещё", "что-то еще",
            # ja
            "他に何か", "ほかに何か",
            # zh
            "还有什么", "还需要什么", "其他需要",
            # ko
            "더 필요한", "다른 필요한", "더 도와드릴",
        )
        matched = any(sentence.startswith(k) and len(sentence) <= len(k) + 40
                      for k in courtesy)
        if not matched:
            state = "red"

# --- Notification filtering ---------------------------------------------------
# Notification carries many types; only "a question/approval is waiting for YOU"
# may go red. The allowlist is inverted on purpose (F2): a future/unknown type,
# or a Claude Code version where the field never arrives, must NOT be able to
# paint a false mid-turn red — the cheap direction here is "don't write" (real
# permission waits already go red via the separate PermissionRequest event).
if event == "Notification":
    ntype = (payload.get("notification_type") or "").lower()
    if ntype in ("permission_prompt", "elicitation_dialog", "agent_needs_input"):
        pass  # genuinely waiting on the user → red stands
    elif ntype == "idle_prompt":
        # mid-turn idle (prev yellow/red) escalates to red; after a completed
        # response (prev green) an idle chat is simply "your turn", not a
        # question — never repaint green → red on idle.
        if prev.get("state") == "green":
            raise SystemExit(0)
    elif ntype in ("elicitation_complete", "elicitation_response"):
        state = "yellow"  # dialog answered → work continues
    else:
        raise SystemExit(0)  # unknown or missing type: never repaint

# --- F11 (cont.): a real Stop while subagents are still active stays yellow ----
# Only when no question was detected above — a question is always the priority
# signal even if background agents are still running.
if state == "green" and event == "Stop" and subagents:
    state = "yellow"

# The session's identity is pinned to where it STARTED. Claude Code's payload `cwd`
# follows the session's live working directory — the agent's shell often `cd`s into a
# subfolder mid-task, and without pinning the menu row gets renamed (e.g. "macos") and
# a click opens that subfolder in a NEW editor window instead of focusing the window
# the session actually lives in. First non-empty cwd wins; later values are ignored.
cwd = prev.get("cwd") or payload.get("cwd") or ""
project = os.path.basename(cwd.rstrip("/")) if cwd else "?"

try:
    session_pid = int(os.environ.get("SESSION_PID", "0"))
except ValueError:
    session_pid = 0

platform = os.environ.get("SESSION_PLATFORM", "unknown") or "unknown"
app_path = os.environ.get("SESSION_APP_PATH", "") or ""

# --- Trust gate (F3 / F5 / F9) -------------------------------------------------
# Red must mean "a question is visible in a chat the user is actually in". When
# an IDE reloads it silently resumes old sessions headlessly; the resumed process
# immediately re-fires the pending-question Notification, which would paint a red
# the user can never find or answer (ghost red).
#
# `trusted` is granted ONLY by an event that actually proves the user is present:
#   - hook_event_name == "UserPromptSubmit" (the user just typed — direct proof), or
#   - the claude process has a controlling tty (a visible terminal window), or
#   - platform == "desktop" (the Desktop app is always an open, visible window —
#     unlike vscode/cursor, no ghost-resume-on-reload failure mode is proven here), or
#   - the previous write under the SAME pid was already trusted (inherited).
# Anything else — including every plain yellow/green tool event that isn't one of
# the above — carries the previous trust forward unchanged (default false, so a
# brand-new pid starts untrusted until one of the proofs above fires).
# An untrusted red is written as green: nothing the user can see or act on is pending.
has_tty = os.environ.get("SESSION_TTY", "") not in ("", "??")
prev_pid_matches = session_pid > 0 and prev.get("session_pid") == session_pid
inherited_trust = prev_pid_matches and prev.get("trusted", False)

trusted = (event == "UserPromptSubmit") or has_tty or (platform == "desktop") or inherited_trust

if state == "red" and not trusted:
    state = "green"

data = {"state": state, "project": project, "cwd": cwd,
        "ts": int(time.time()), "session_pid": session_pid,
        "platform": platform, "app_path": app_path, "trusted": trusted,
        "subagents": subagents}

write_atomic(data)
PY
