#!/bin/zsh
# Builds build/NotchHub.dmg. Unsigned unless DEVELOPER_ID is set; notarized when NOTARY_PROFILE is
# also set (a profile saved with `xcrun notarytool store-credentials`).
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/bundle.sh
app=build/NotchHub.app
dmg=build/NotchHub.dmg
staging=build/dmg-staging

rm -rf "$staging" "$dmg"
mkdir -p "$staging"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"

hdiutil create -volname "Notch Hub" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null
rm -rf "$staging"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
    codesign --force --timestamp --sign "$DEVELOPER_ID" "$dmg"
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$dmg"
        echo "Notarized and stapled."
    else
        echo "Signed, not notarized (set NOTARY_PROFILE to notarize)."
    fi
else
    echo "UNSIGNED build: people who download it will see a Gatekeeper warning. Set DEVELOPER_ID to sign."
fi
echo "Built $dmg ($(du -h "$dmg" | cut -f1))"
