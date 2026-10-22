#!/bin/zsh
# Builds a release NotchHub.app into build/ (ad-hoc signed, for local use only).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
app="build/Notch Hub.app"
mkdir -p build && touch build/.metadata_never_index   # keep this copy out of Spotlight and the "+" pickers
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/NotchHub "$app/Contents/MacOS/NotchHub"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>NotchHub</string>
    <key>CFBundleIdentifier</key><string>dev.notchhub.app</string>
    <key>CFBundleName</key><string>Notch Hub</string>
    <key>CFBundleDisplayName</key><string>Notch Hub</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
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

# Signing: with DEVELOPER_ID set (for example "Developer ID Application: Name (TEAMID)") the app is signed
# with the hardened runtime, which notarization requires. Otherwise it is ad-hoc signed, which is enough
# to run locally but makes macOS ask for permissions again after every rebuild.
if [[ -n "${DEVELOPER_ID:-}" ]]; then
    codesign --force --options runtime --timestamp --entitlements scripts/NotchHub.entitlements --sign "$DEVELOPER_ID" "$app"
    echo "Signed with: $DEVELOPER_ID"
else
    codesign --force --sign - "$app"
fi
echo "Built $app"
