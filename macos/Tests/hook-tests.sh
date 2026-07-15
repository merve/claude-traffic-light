#!/bin/bash
# Behavioral test harness for macos/hooks/claude-status-hook.sh. The scenario table
# below is the cross-platform contract (F-tags legend: windows/WINDOWS-PORT-SPEC.md) and
# is meant to be reproduced 1:1 by the Windows HookRunner unit tests.
# Exercises the real hook script end-to-end: fake `ps` shim on PATH (no real
# process ancestry needed) + CLAUDE_STATUS_DIR override (no touching the real
# ~/.claude/status). Run directly: `bash macos/Tests/hook-tests.sh` (also invoked by
# `swift test` via run-tests.sh if wired in).
#
# PID-inheritance scenarios (trust carried across events of the "same session") MUST run
# their events inside one `session()` block: sequential commands in a single subshell share
# one $PPID, exactly like repeated hook calls from one live `claude` process would.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../hooks/claude-status-hook.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin" "$WORK/status"
cat > "$WORK/bin/ps" <<'EOF'
#!/bin/bash
if [[ "$*" == *"-o tty="* ]]; then
  echo "${TEST_TTY:-ttys012}"
elif [[ "$*" == *"-o command="* ]]; then
  echo "${TEST_CMD:-/bin/zsh}"
elif [[ "$*" == *"-o ppid=,command="* ]]; then
  echo "1 ${TEST_CMD:-/bin/zsh}"
fi
EOF
chmod +x "$WORK/bin/ps"

export PATH="$WORK/bin:$PATH"
export CLAUDE_STATUS_DIR="$WORK/status"

PASS=0
FAIL=0

# fire STATE JSON_PAYLOAD  — one hook invocation, discards output.
fire() {
  echo -n "$2" | bash "$HOOK" "$1" >/dev/null 2>&1
}

# session BLOCK — runs BLOCK (containing one or more `fire` calls) inside a single
# subshell so every `fire` in it observes the same $PPID (pid-inheritance tests).
session() { ( eval "$1" ); }

# assert LABEL SESSION_ID JQ_EXPR EXPECT
assert() {
  local label="$1" sid="$2" expr="$3" expect="$4"
  local f="$WORK/status/$sid.json"
  local got
  if [ ! -f "$f" ]; then got="<no file>"; else got="$(python3 -c "
import json
d = json.load(open('$f'))
print($expr)
" 2>/dev/null)"; fi
  if [ "$got" == "$expect" ]; then
    PASS=$((PASS+1)); printf "ok   %s\n" "$label"
  else
    FAIL=$((FAIL+1)); printf "FAIL %s: got=%s expect=%s\n" "$label" "$got" "$expect"
  fi
}

reset_status() { rm -f "$WORK/status"/*.json 2>/dev/null; }

transcript() {
  python3 -c "
import json, sys
text = sys.argv[1]
print(json.dumps({'type':'assistant','message':{'content':[{'type':'text','text':text}]}}))
" "$1" > "$WORK/t.jsonl"
  echo "$WORK/t.jsonl"
}

stop_payload() {
  local sid="$1" text="$2"
  local tp; tp="$(transcript "$text")"
  echo "{\"session_id\":\"$sid\",\"hook_event_name\":\"Stop\",\"transcript_path\":\"$tp\",\"cwd\":\"/tmp/p\"}"
}

notif_payload() {
  local sid="$1" ntype="$2"
  local f=""
  [ -n "$ntype" ] && f=",\"notification_type\":\"$ntype\""
  echo "{\"session_id\":\"$sid\",\"hook_event_name\":\"Notification\",\"cwd\":\"/tmp/p\"$f}"
}

echo "== F1: courtesy match anchored to last sentence =="
export TEST_TTY=ttys012 TEST_CMD=/bin/zsh
reset_status
fire green "$(stop_payload f1a 'İşlemleri tamamladım. Başka bir şey var mı?')"
assert "F1 tr courtesy close -> green" f1a "d['state']" "green"
reset_status
fire green "$(stop_payload f1b 'All done. Is there anything else I can help you with?')"
assert "F1 en courtesy close -> green" f1b "d['state']" "green"
reset_status
fire green "$(stop_payload f1c 'Is there anything in the logs that explains this, or should I drop the table?')"
assert "F1 compound question -> red" f1c "d['state']" "red"
reset_status
fire green "$(stop_payload f1d 'Soll ich sonst noch die Prod-Config ändern?')"
assert "F1 de compound (substring trap) -> red" f1d "d['state']" "red"
reset_status
fire green "$(stop_payload f1e 'İki yol var. Hangisiyle devam edeyim?')"
assert "F1 tr real question -> red" f1e "d['state']" "red"

echo "== F6: closing-quote / CJK bracket closers =="
reset_status
fire green "$(stop_payload f6a $'Devam edeyim mi?”')"
assert "F6 curly-quote closer still detects question -> red" f6a "d['state']" "red"
reset_status
fire green "$(stop_payload f6b $'完了しました。他に何かありますか？」')"
assert "F6 CJK closer + courtesy -> green" f6b "d['state']" "green"

echo "== F7: U+2028 inside a JSONL record must not split it =="
reset_status
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"line one\xe2\x80\xa8still same record"}]}}\n{"type":"assistant","message":{"content":[{"type":"text","text":"Should I proceed with the migration or wait?"}]}}\n' > "$WORK/t7.jsonl"
fire green "{\"session_id\":\"f7\",\"hook_event_name\":\"Stop\",\"transcript_path\":\"$WORK/t7.jsonl\",\"cwd\":\"/tmp/p\"}"
assert "F7 U+2028 doesn't fragment the record -> red" f7 "d['state']" "red"

echo "== F2: Notification allowlist inverted (default: don't write) =="
reset_status
fire red "$(notif_payload f2a auth_success)"
assert "F2 auth_success -> no file" f2a "'x'" "<no file>"
reset_status
fire red "$(notif_payload f2b future_type)"
assert "F2 unknown future type -> no file" f2b "'x'" "<no file>"
reset_status
fire red "$(notif_payload f2b2 agent_completed)"
assert "F2 agent_completed -> no file" f2b2 "'x'" "<no file>"
reset_status
fire red "$(notif_payload f2c '')"
assert "F2 missing type -> no file" f2c "'x'" "<no file>"
reset_status
fire red "$(notif_payload f2d permission_prompt)"
assert "F2 permission_prompt -> red" f2d "d['state']" "red"
reset_status
fire red "$(notif_payload f2e elicitation_dialog)"
assert "F2 elicitation_dialog -> red" f2e "d['state']" "red"
reset_status
fire red "$(notif_payload f2f agent_needs_input)"
assert "F2 agent_needs_input -> red" f2f "d['state']" "red"
reset_status
fire red "$(notif_payload f2g elicitation_complete)"
assert "F2 elicitation_complete -> yellow" f2g "d['state']" "yellow"
reset_status
echo '{"state":"green","trusted":true}' > "$WORK/status/f2h.json"
fire red "$(notif_payload f2h idle_prompt)"
assert "F2 idle_prompt after green -> unchanged (green)" f2h "d['state']" "green"
reset_status
echo '{"state":"yellow","trusted":true}' > "$WORK/status/f2i.json"
fire red "$(notif_payload f2i idle_prompt)"
assert "F2 idle_prompt mid-turn -> red" f2i "d['state']" "red"

echo "== F3/F5/F9: trust gate =="
reset_status
export TEST_TTY="??" TEST_CMD=/bin/zsh
fire red "$(notif_payload f3a permission_prompt)"
assert "ghost red (headless, no prior activity) -> green/untrusted" f3a "(d['state'],d['trusted'])" "('green', False)"

reset_status
export TEST_TTY="ttys012"
fire red "$(notif_payload f3b permission_prompt)"
assert "tty present -> red/trusted" f3b "(d['state'],d['trusted'])" "('red', True)"

reset_status
export TEST_TTY="??" TEST_CMD="/Applications/Claude.app/Contents/MacOS/claude-code"
fire red "$(notif_payload f3c permission_prompt)"
assert "platform=desktop -> red/trusted (no tty needed)" f3c "(d['state'],d['trusted'])" "('red', True)"

reset_status
export TEST_TTY="??" TEST_CMD=/bin/zsh
session '
  fire yellow "{\"session_id\":\"f5a\",\"hook_event_name\":\"UserPromptSubmit\",\"cwd\":\"/tmp/p\"}"
  fire red    "{\"session_id\":\"f5a\",\"hook_event_name\":\"Notification\",\"notification_type\":\"permission_prompt\",\"cwd\":\"/tmp/p\"}"
'
assert "UserPromptSubmit trust carries into a later red (same session)" f5a "(d['state'],d['trusted'])" "('red', True)"

reset_status
# Both events must come from the SAME pid (one session block) — the whole point is
# that a yellow write must NOT launder trust for a later red from the same process.
# The intermediate state is snapshotted to a side file between the two fires.
session '
  fire red "{\"session_id\":\"f5b\",\"hook_event_name\":\"Notification\",\"notification_type\":\"elicitation_complete\",\"cwd\":\"/tmp/p\"}"
  cp "$WORK/status/f5b.json" "$WORK/status/f5b-mid.json"
  fire red "{\"session_id\":\"f5b\",\"hook_event_name\":\"Notification\",\"notification_type\":\"permission_prompt\",\"cwd\":\"/tmp/p\"}"
'
assert "elicitation_complete on a fresh headless pid -> yellow/untrusted" f5b-mid "(d['state'],d['trusted'])" "('yellow', False)"
assert "same pid, but prev write was untrusted -> red demoted to green/untrusted" f5b "(d['state'],d['trusted'])" "('green', False)"
rm -f "$WORK/status/f5b-mid.json"

echo "== F11: subagent tracking =="
reset_status
export TEST_TTY=ttys012
session '
  fire yellow          "{\"session_id\":\"f11\",\"hook_event_name\":\"UserPromptSubmit\",\"cwd\":\"/tmp/p\"}"
  fire subagent-start  "{\"session_id\":\"f11\",\"hook_event_name\":\"SubagentStart\",\"agent_id\":\"A\",\"cwd\":\"/tmp/p\"}"
'
assert "subagent-start A -> yellow, set={A}" f11 "(d['state'], sorted(d['subagents'].keys()))" "('yellow', ['A'])"

session '
  fire green "$(cat <<PAYLOAD
{"session_id":"f11","hook_event_name":"Stop","transcript_path":"$(transcript "All done, nothing more to say.")","cwd":"/tmp/p"}
PAYLOAD
)"
'
assert "Stop while A still active -> stays yellow (not green)" f11 "d['state']" "yellow"

session '
  fire subagent-start "{\"session_id\":\"f11\",\"hook_event_name\":\"SubagentStart\",\"agent_id\":\"B\",\"cwd\":\"/tmp/p\"}"
  fire subagent-stop  "{\"session_id\":\"f11\",\"hook_event_name\":\"SubagentStop\",\"agent_id\":\"A\",\"cwd\":\"/tmp/p\"}"
'
assert "subagent-stop A -> color unchanged, set={B}" f11 "(d['state'], sorted(d['subagents'].keys()))" "('yellow', ['B'])"

session '
  fire subagent-stop "{\"session_id\":\"f11\",\"hook_event_name\":\"SubagentStop\",\"agent_id\":\"B\",\"cwd\":\"/tmp/p\"}"
  fire green "$(cat <<PAYLOAD
{"session_id":"f11","hook_event_name":"Stop","transcript_path":"$(transcript "All done, nothing more to say.")","cwd":"/tmp/p"}
PAYLOAD
)"
'
assert "final Stop with empty set -> green" f11 "(d['state'], d['subagents'])" "('green', {})"

reset_status
session '
  fire yellow          "{\"session_id\":\"f11q\",\"hook_event_name\":\"UserPromptSubmit\",\"cwd\":\"/tmp/p\"}"
  fire subagent-start  "{\"session_id\":\"f11q\",\"hook_event_name\":\"SubagentStart\",\"agent_id\":\"C\",\"cwd\":\"/tmp/p\"}"
  fire green "$(cat <<PAYLOAD
{"session_id":"f11q","hook_event_name":"Stop","transcript_path":"$(transcript "Should I go ahead and delete the branch?")","cwd":"/tmp/p"}
PAYLOAD
)"
'
assert "real question at Stop outranks active subagent set -> red" f11q "d['state']" "red"

echo "== question tools: red only while ASKING, not after the answer =="
reset_status
fire yellow '{"session_id":"fq","hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","cwd":"/tmp/p"}'
assert "PreToolUse(AskUserQuestion) -> red" fq "d['state']" "red"
fire yellow '{"session_id":"fq","hook_event_name":"PostToolUse","tool_name":"AskUserQuestion","cwd":"/tmp/p"}'
assert "PostToolUse(AskUserQuestion) = answered -> back to yellow" fq "d['state']" "yellow"

echo "== cwd pinning: mid-session cd must not rename/retarget the session =="
reset_status
session '
  fire yellow "{\"session_id\":\"fcwd\",\"hook_event_name\":\"UserPromptSubmit\",\"cwd\":\"/w/claude-traffic-light\"}"
  fire yellow "{\"session_id\":\"fcwd\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",\"cwd\":\"/w/claude-traffic-light/macos\"}"
'
assert "cwd stays pinned to the launch dir after a mid-session cd" fcwd "(d['project'], d['cwd'])" "('claude-traffic-light', '/w/claude-traffic-light')"

echo "== concurrency: parallel hook writers must not tear the file or reset the pin =="
reset_status
fire yellow "{\"session_id\":\"frace\",\"hook_event_name\":\"UserPromptSubmit\",\"cwd\":\"/w/root\"}"
for i in 1 2 3 4 5 6 7 8; do
  ( fire yellow "{\"session_id\":\"frace\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"cwd\":\"/w/root/sub\"}" ) &
  ( fire subagent-start "{\"session_id\":\"frace\",\"hook_event_name\":\"SubagentStart\",\"agent_id\":\"r$i\",\"cwd\":\"/w/root/sub\"}" ) &
done
wait
assert "file stays parseable and cwd stays pinned under parallel writers" frace "(d['project'], d['cwd'])" "('root', '/w/root')"

echo "== end: file removed (and its .lock) =="
reset_status
echo '{"state":"yellow"}' > "$WORK/status/fend.json"
touch "$WORK/status/fend.json.lock"
fire end '{"session_id":"fend"}'
assert "end removes the status file" fend "'x'" "<no file>"
if [ ! -f "$WORK/status/fend.json.lock" ]; then
  PASS=$((PASS+1)); echo "ok   end removes the .lock companion too"
else
  FAIL=$((FAIL+1)); echo "FAIL end left the .lock behind"
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
