#!/bin/bash
# Starts Claude Traffic Light.app at every login (a user LaunchAgent).
# Looks for the app under /Applications or in this project directory.
set -euo pipefail

APP_NAME="Claude Traffic Light"   # display name / .app bundle
EXEC_NAME="ClaudeLight"           # binary name inside the bundle (see build-app.sh)
LABEL="com.mervepro.claudelight"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

# Locate the app.
if [[ -d "/Applications/$APP_NAME.app" ]]; then
  APP="/Applications/$APP_NAME.app"
elif [[ -d "$(dirname "$0")/$APP_NAME.app" ]]; then
  APP="$(cd "$(dirname "$0")" && pwd)/$APP_NAME.app"
else
  echo "ERROR: $APP_NAME.app not found. Run ./build-app.sh first." >&2
  exit 1
fi

BIN="$APP/Contents/MacOS/$EXEC_NAME"
echo "==> App: $APP"

mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
PLISTEOF

echo "==> LaunchAgent written: $PLIST"

# If already loaded, unload then load (idempotent).
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo "==> Launch at login enabled. $APP_NAME will run on every login."
echo "    To remove:  launchctl unload \"$PLIST\" && rm \"$PLIST\""
