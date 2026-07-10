#!/bin/bash
# Builds Claude Traffic Widget.app: a floating, pinnable, draggable desktop widget showing
# live Claude Code sessions. Companion to build-app.sh (the menu-bar app) — the two are
# independent processes that can run together or separately.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Claude Traffic Widget"   # user-facing display name (Finder, About)
EXEC_NAME="ClaudeTrafficWidget"    # binary + process name
PRODUCT="ClaudeWidget"             # SwiftPM product (binary) name
BUILD_CONFIG="release"
BUNDLE_ID="com.mervepro.claudewidget"

echo "==> Compiling Swift ($BUILD_CONFIG)…"
swift build -c "$BUILD_CONFIG"

BIN_PATH="$(swift build -c "$BUILD_CONFIG" --show-bin-path)/$PRODUCT"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "ERROR: binary not found: $BIN_PATH" >&2
  exit 1
fi
# The menu-bar app's binary draws the shared app icon (--appicon debug mode); reuse it
# instead of duplicating the icon-drawing code in the widget target.
ICON_BIN="$(swift build -c "$BUILD_CONFIG" --show-bin-path)/ClaudeStatus"
if [[ ! -f "$ICON_BIN" ]]; then
  echo "ERROR: ClaudeStatus binary not found (needed to render the app icon): $ICON_BIN" >&2
  exit 1
fi

APP_DIR="$PWD/$APP_NAME.app"
echo "==> Creating .app bundle: $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$EXEC_NAME"

# --- App icon (.icns) ---
echo "==> Generating app icon…"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
gen() { "$ICON_BIN" --appicon "$ICONSET/$1" "$2"; }
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
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature, identifier matching CFBundleIdentifier (same reasoning as build-app.sh).
echo "==> Ad-hoc signing (identity = $BUNDLE_ID)…"
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_DIR"
codesign -dv "$APP_DIR" 2>&1 | grep -E "Identifier|Signature" | sed 's/^/    /'

touch "$APP_DIR"

echo "==> Done: $APP_DIR"
echo "    To run:  open \"$APP_DIR\""
echo "    (Move it into /Applications if you like — runs independently of"
echo "     \"Claude Traffic Light.app\"; both can be open at the same time.)"
