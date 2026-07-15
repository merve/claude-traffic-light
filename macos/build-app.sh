#!/bin/bash
# Builds Claude Traffic Light.app: compiles Swift, generates the app icon (.icns) and
# packages it as a menu-bar application.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Claude Traffic Light"       # user-facing display name (menu bar, Finder, About)
EXEC_NAME="ClaudeLight"      # binary + process name — kept short & space-free because macOS
                             # truncates process names to ~16 chars, which pgrep/pkill -x match on
PRODUCT="ClaudeStatus"       # SwiftPM product (binary) name
BUILD_CONFIG="release"
BUNDLE_ID="com.mervepro.claudelight"

echo "==> Compiling Swift ($BUILD_CONFIG)…"
swift build -c "$BUILD_CONFIG"

BIN_PATH="$(swift build -c "$BUILD_CONFIG" --show-bin-path)/$PRODUCT"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "ERROR: binary not found: $BIN_PATH" >&2
  exit 1
fi

APP_DIR="$PWD/$APP_NAME.app"
echo "==> Creating .app bundle: $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy the binary under the (short) executable name.
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$EXEC_NAME"

# Bundle the hook + settings snippet so the app can self-install on first launch
# (drag-and-drop DMG install; see Bootstrap.swift).
cp "hooks/claude-status-hook.sh" "$APP_DIR/Contents/Resources/claude-status-hook.sh"
cp "hooks/settings-snippet.json" "$APP_DIR/Contents/Resources/settings-snippet.json"

# --- App icon (.icns) ---
echo "==> Generating app icon…"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
# iconset file name -> pixel size
gen() { "$BIN_PATH" --appicon "$ICONSET/$1" "$2"; }
gen icon_16x16.png 16
gen icon_16x16@2x.png 32
gen icon_32x32.png 32
gen icon_32x32@2x.png 64
gen icon_128x128.png 128
gen icon_128x128@2x.png 256
gen icon_256x256.png 256
gen icon_256x256@2x.png 512
gen icon_512x512.png 512
gen icon_512x512@2x.png 1024
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$EXEC_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.2.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature — match the signing identifier to the bundle id. This is
# REQUIRED: the adhoc signature the linker adds automatically uses the binary name
# ("ClaudeStatus") as its identifier, which does not match CFBundleIdentifier; that
# mismatch silently breaks UNUserNotificationCenter registration (i.e. notifications).
echo "==> Ad-hoc signing (identity = $BUNDLE_ID, for notifications)…"
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_DIR"
codesign -dv "$APP_DIR" 2>&1 | grep -E "Identifier|Signature" | sed 's/^/    /'

# Refresh the icon cache (so Finder/Dock don't show a stale icon).
touch "$APP_DIR"

echo "==> Done: $APP_DIR"
echo "    To run:  open \"$APP_DIR\""
echo "    (Move it into /Applications if you like.)"
