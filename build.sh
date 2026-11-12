#!/bin/sh
# Builds Snaps.app into ./build. Run: ./build.sh && open build/Snaps.app
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/Snaps.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Snaps "$APP/Contents/MacOS/Snaps"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Snaps</string>
    <key>CFBundleIdentifier</key><string>com.amims71.snaps</string>
    <key>CFBundleExecutable</key><string>Snaps</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
# Sign with an Apple Development cert when available: a stable identity keeps the
# macOS privacy permissions across rebuilds (ad-hoc signatures change every build).
IDENTITY=$(security find-identity -p codesigning -v | awk '/Apple Development/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP"
