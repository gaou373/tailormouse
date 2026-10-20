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
# Distribution builds request both architectures; local installs stay native.
read -r -a ARCHS <<< "${TAILORMOUSE_ARCHS:-$(uname -m)}"
BINARIES=()
for ARCH in "${ARCHS[@]}"; do
    case "$ARCH" in arm64|x86_64) ;; *) printf 'Unsupported architecture: %s\n' "$ARCH" >&2; exit 1 ;; esac
    xcrun swift build --build-system native -c release --arch "$ARCH" --scratch-path "$BUILD/swift"
    BIN_DIR="$(xcrun swift build --build-system native -c release --arch "$ARCH" --scratch-path "$BUILD/swift" --show-bin-path)"
    cp "$BIN_DIR/TailorMouse" "$BUILD/TailorMouse-$ARCH"
    BINARIES+=("$BUILD/TailorMouse-$ARCH")
done
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
if [[ ${#BINARIES[@]} -gt 1 ]]; then
    lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/TailorMouse"
else
    cp "${BINARIES[0]}" "$APP/Contents/MacOS/TailorMouse"
fi
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$FRAMEWORK"
ditto "$BIN_DIR/Sparkle.framework" "$FRAMEWORK"
cp "$BUILD/swift/artifacts/sparkle/Sparkle/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
xcrun swift "$ROOT/scripts/create-icon.swift" "$BUILD/TailorMouse.iconset"
iconutil -c icns "$BUILD/TailorMouse.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.tailormouse.app</string>
<key>CFBundleName</key><string>TailorMouse</string>
<key>CFBundleDisplayName</key><string>TailorMouse</string>
<key>CFBundleExecutable</key><string>TailorMouse</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.7</string>
<key>CFBundleVersion</key><string>35</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict></plist>
PLIST
/usr/bin/python3 "$ROOT/scripts/embed-update-config.py" "$ROOT/release/update-config.json" "$APP/Contents/Info.plist"
# Sign nested helpers from the inside out, then the framework and application.
# Developer ID builds use hardened runtime and secure timestamps for notarization.
SIGNING_IDENTITY="${TAILORMOUSE_SIGNING_IDENTITY:--}"
SIGN_OPTIONS=(--force --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then SIGN_OPTIONS+=(--options runtime --timestamp); fi
for NESTED in \
    "$FRAMEWORK/Versions/B/Autoupdate" \
    "$FRAMEWORK/Versions/B/Updater.app/Contents/MacOS/fileop" \
    "$FRAMEWORK/Versions/B/Updater.app" \
    "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc" \
    "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"; do
    if [[ -e "$NESTED" ]]; then codesign "${SIGN_OPTIONS[@]}" "$NESTED"; fi
done
codesign "${SIGN_OPTIONS[@]}" "$FRAMEWORK"
codesign "${SIGN_OPTIONS[@]}" --identifier dev.tailormouse.app "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built %s\n' "$APP"
