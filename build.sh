#!/bin/bash
#
# Build Quick_Drop.app from the Swift package and assemble a runnable .app bundle.
# Requires the Swift toolchain (comes with Xcode or the Xcode Command Line Tools).
#
set -euo pipefail

APP_NAME="Quick_Drop"
EXECUTABLE="Quick_Drop"
BUNDLE_ID="com.local.quickdrop"
VERSION="1.0.0"

cd "$(dirname "$0")"

echo "==> Compiling (release)..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)"

DIST_DIR="dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
echo "==> Assembling $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH/$EXECUTABLE" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

# App icon.
if [ -f "Sources/Quick_Drop/AppIcon.icns" ]; then
    cp "Sources/Quick_Drop/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <!-- Agent app: no Dock icon, no app menu. -->
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing..."
# Ad-hoc signature (the "-" identity) so Gatekeeper lets you run it locally.
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || \
    echo "    (codesign skipped/failed - app will still run after you allow it in System Settings)"

echo ""
echo "Done. Built ./$APP_DIR"
echo "Run it now with:        open ./$APP_DIR"
echo "Install it with:        cp -R ./$APP_DIR /Applications/"
