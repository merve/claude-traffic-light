#!/bin/bash
# Builds Claude Traffic Widget.app and packages it into a distributable
# Claude Traffic Widget.dmg (app + an /Applications symlink for drag-and-drop install).
# Mirrors build-dmg.sh (the menu-bar app's DMG builder).
#
# NOTE: the widget is read-only — it never installs the Claude Code hook. It needs
# "Claude Traffic Light.app" (or install.sh) set up at least once so ~/.claude/status
# gets populated; see Claude Traffic Light.dmg / install.sh.
#
# NOTE ON GATEKEEPER: the app is ad-hoc signed, not Developer-ID signed/notarized.
# On a machine it was downloaded to, macOS will quarantine it and refuse to open it
# normally. The recipient must either right-click → Open once, or run:
#     xattr -dr com.apple.quarantine "/Applications/Claude Traffic Widget.app"
# Proper distribution without that step requires an Apple Developer ID + notarization.
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="Claude Traffic Widget"
VOL_NAME="Claude Traffic Widget"
DMG="$PWD/$APP_NAME.dmg"

echo "==> Building the app…"
./build-widget-app.sh >/dev/null
APP="$PWD/$APP_NAME.app"
[ -d "$APP" ] || { echo "ERROR: $APP not found" >&2; exit 1; }

echo "==> Staging DMG contents…"
STAGE="$(mktemp -d)/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Short readme explaining the one-time Gatekeeper step for an unsigned app.
cat > "$STAGE/READ ME FIRST.txt" <<'TXT'
Claude Traffic Widget — floating desktop widget for Claude Code sessions.

INSTALL
  1. Drag Claude Traffic Widget.app onto the Applications folder.
  2. First open (the app is not notarized, so macOS blocks it once with
     "Apple cannot check it for malicious software"). Do ONE of:
       - System Settings > Privacy & Security > scroll down > "Open Anyway", or
       - In Terminal, run:
           xattr -dr com.apple.quarantine "/Applications/Claude Traffic Widget.app"
     (On macOS 15 Sequoia and later the old right-click > Open trick usually
      no longer works — use one of the two above.)

REQUIRES "Claude Traffic Light" (the menu-bar app)
  The widget is a read-only viewer — it never installs the Claude Code hook or
  touches settings.json. Install "Claude Traffic Light.app" (or run install.sh)
  at least once first, so ~/.claude/status gets populated. After that the widget
  can run alongside it, or on its own.

That's it — drag it anywhere, click the light to expand/collapse, pin it with
the 📌, right-click for more options.
TXT

echo "==> Creating DMG…"
rm -f "$DMG"
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$(dirname "$STAGE")"

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
echo "==> Done: $DMG ($SIZE)"
echo "    Reminder: recipients must clear the Gatekeeper quarantine (see the DMG's READ ME)."
