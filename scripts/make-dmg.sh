#!/bin/zsh
# Packages dist/SRT Generator.app into dist/SRTGenerator-<version>.dmg (with an Applications shortcut)
# plus dist/SRTGenerator-<version>.dmg.sha256. Run build-app.sh first (make dmg does both).
# Usage: scripts/make-dmg.sh [version]   (default: CFBundleShortVersionString of the built app)
set -euo pipefail
cd "$(dirname "$0")/.."
APP="dist/SRT Generator.app"
[[ -d "$APP" ]] || { echo "Missing $APP; run ./build-app.sh first" >&2; exit 1; }
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
DMG="dist/SRTGenerator-$VERSION.dmg"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG" "$DMG.sha256"
hdiutil create -quiet -volname "SRT Generator $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
(cd dist && shasum -a 256 "${DMG:t}" > "${DMG:t}.sha256")
echo "Built: $DMG"
cat "$DMG.sha256"
