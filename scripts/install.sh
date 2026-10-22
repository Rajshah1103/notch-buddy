#!/bin/zsh
# Builds Notch Hub and installs it into /Applications (or ~/Applications if that is not writable), so it
# appears in Launchpad, Spotlight and the "+" picker in System Settings > Privacy & Security, then opens it.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/bundle.sh
app="build/Notch Hub.app"

target=/Applications
[[ -w "$target" ]] || { target="$HOME/Applications"; mkdir -p "$target"; }

pkill -x NotchHub 2>/dev/null || true
sleep 0.5
rm -rf "$target/Notch Hub.app"
cp -R "$app" "$target/"
echo "Installed $target/Notch Hub.app"
open "$target/Notch Hub.app"
