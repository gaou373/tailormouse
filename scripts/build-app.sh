#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.local/build"
APP="$BUILD/TailorMouse.app"
cd "$ROOT"
# Prefer the full Xcode toolchain when installed; mixed CLT installations can fail
# to link a SwiftPM manifest even when `swift --version` succeeds.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
xcrun swift build -c release --scratch-path "$BUILD/swift"
BIN_DIR="$(xcrun swift build -c release --scratch-path "$BUILD/swift" --show-bin-path)"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/TailorMouse" "$APP/Contents/MacOS/TailorMouse"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.tailormouse.app</string>
<key>CFBundleName</key><string>TailorMouse</string>
<key>CFBundleDisplayName</key><string>TailorMouse</string>
<key>CFBundleExecutable</key><string>TailorMouse</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict></plist>
PLIST
codesign --force --sign - --identifier dev.tailormouse.app "$APP"
printf 'Built %s\n' "$APP"
