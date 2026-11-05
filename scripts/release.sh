#!/bin/zsh
# Builds the release zip for Homebrew and GitHub: build/NotchBuddy-<version>-arm64.zip, and prints its sha256.
# Usage: VERSION=1.0.0 ./scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."
export VERSION="${VERSION:-1.0.0}"
ADHOC=1 ./scripts/bundle.sh
zip="build/NotchBuddy-$VERSION-arm64.zip"
rm -f "$zip"
ditto -c -k --keepParent "build/Notch Hub.app" "$zip"
echo "$zip"
shasum -a 256 "$zip"
