#!/bin/bash
# Builds Claude Traffic Light.app and packages it into a distributable Claude Traffic Light.dmg
# (app + an /Applications symlink for drag-and-drop install).
#
# The app self-installs its hook + settings on first launch (see Bootstrap.swift),
# so the DMG is all a user needs.
#
# NOTE ON GATEKEEPER: the app is ad-hoc signed, not Developer-ID signed/notarized.
# On a machine it was downloaded to, macOS will quarantine it and refuse to open it
# normally. The recipient must either right-click → Open once, or run:
#     xattr -dr com.apple.quarantine /Applications/Claude Traffic Light.app
# Proper distribution without that step requires an Apple Developer ID + notarization.
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="Claude Traffic Light"
VOL_NAME="Claude Traffic Light"
DMG="$PWD/$APP_NAME.dmg"

echo "==> Building the app…"
./build-app.sh >/dev/null
APP="$PWD/$APP_NAME.app"
[ -d "$APP" ] || { echo "ERROR: $APP not found" >&2; exit 1; }

echo "==> Staging DMG contents…"
STAGE="$(mktemp -d)/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Short readme explaining the one-time Gatekeeper step for an unsigned app.
cat > "$STAGE/READ ME FIRST.txt" <<'TXT'
Claude Traffic Light — menu bar traffic light for Claude Code sessions.

INSTALL
  1. Drag Claude Traffic Light.app onto the Applications folder.
  2. First open (the app is not notarized, so macOS blocks it once with
     "Apple cannot check it for malicious software"). Do ONE of:
       - System Settings > Privacy & Security > scroll down > "Open Anyway", or
       - In Terminal, run:
           xattr -dr com.apple.quarantine "/Applications/Claude Traffic Light.app"
     (On macOS 15 Sequoia and later the old right-click > Open trick usually
      no longer works — use one of the two above.)
  3. Allow notifications when prompted.

That's it — the app installs its Claude Code hook automatically on first launch.
A traffic light appears in the menu bar; colors come alive on your next session.
TXT

echo "==> Creating DMG…"
rm -f "$DMG"
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$(dirname "$STAGE")"

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
echo "==> Done: $DMG ($SIZE)"
echo "    Reminder: recipients must clear the Gatekeeper quarantine (see the DMG's READ ME)."
