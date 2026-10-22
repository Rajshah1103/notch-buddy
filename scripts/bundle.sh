#!/bin/zsh
# Builds a release NotchHub.app into build/ (ad-hoc signed, for local use only).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
app=build/NotchHub.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/NotchHub "$app/Contents/MacOS/NotchHub"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>NotchHub</string>
    <key>CFBundleIdentifier</key><string>dev.notchhub.app</string>
    <key>CFBundleName</key><string>Notch Hub</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Notch Hub reads your browser tabs so you can jump straight to one.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$app"
echo "Built $app"
