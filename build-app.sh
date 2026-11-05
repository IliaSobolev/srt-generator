#!/bin/zsh
# Builds a release SRT Generator.app into ./dist
set -euo pipefail
cd "$(dirname "$0")"

# Version: VERSION file (SemVer) unless APP_VERSION overrides it; build number grows with every commit.
APP_VERSION="${APP_VERSION:-$(tr -d '[:space:]' < VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/SRTGenerator"
APP="dist/SRT Generator.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SRTGenerator"
# Bundle resources from SwiftPM dependencies (tokenizer templates etc.), if any.
for b in "$(dirname "$BIN")"/*.bundle(N); do cp -R "$b" "$APP/Contents/Resources/"; done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SRT Generator</string>
    <key>CFBundleDisplayName</key><string>SRT Generator</string>
    <key>CFBundleIdentifier</key><string>local.srtgenerator</string>
    <key>CFBundleExecutable</key><string>SRTGenerator</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${APP_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.video</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array><string>public.audiovisual-content</string><string>public.audio</string><string>public.movie</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built: $APP ($APP_VERSION, build $BUILD_NUMBER)"
