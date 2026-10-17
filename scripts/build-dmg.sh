#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${TAILORMOUSE_SKIP_BUILD:-0}" != 1 ]]; then
    TAILORMOUSE_ARCHS='arm64 x86_64' bash "$ROOT/scripts/build-app.sh"
fi
APP="$ROOT/.local/build/TailorMouse.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUTPUT="$ROOT/.local/releases/$VERSION"
STAGING="$(mktemp -d "$ROOT/.local/dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$OUTPUT"
codesign --verify --deep --strict "$APP"
lipo "$APP/Contents/MacOS/TailorMouse" -verify_arch arm64 x86_64
ditto "$APP" "$STAGING/TailorMouse.app"
ln -s /Applications "$STAGING/Applications"
cp "$ROOT/release/Install TailorMouse.txt" "$STAGING/Install TailorMouse.txt"
SIGNING_STATUS='Ad hoc signed preview; not Apple notarized'
if [[ -n "${TAILORMOUSE_SIGNING_IDENTITY:-}" && "$TAILORMOUSE_SIGNING_IDENTITY" != '-' ]]; then
    SIGNING_STATUS='Signed with the publisher certificate; notarization not requested'
    if [[ -n "${TAILORMOUSE_NOTARY_PROFILE:-}" ]]; then SIGNING_STATUS='Publisher signed and submitted to Apple notarization'; fi
fi
printf 'TailorMouse %s\nArchitectures: Apple Silicon (arm64), Intel (x86_64)\nRequires: macOS 13 or later\nSigning: %s\n' "$VERSION" "$SIGNING_STATUS" > "$STAGING/Release Info.txt"
DMG="$OUTPUT/TailorMouse-$VERSION-universal.dmg"
hdiutil create -volname "TailorMouse $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"
if [[ -n "${TAILORMOUSE_SIGNING_IDENTITY:-}" && "$TAILORMOUSE_SIGNING_IDENTITY" != '-' ]]; then
    codesign --force --sign "$TAILORMOUSE_SIGNING_IDENTITY" --timestamp "$DMG"
fi
# Optional publisher Keychain profile. Never accepts passwords in arguments.
if [[ -n "${TAILORMOUSE_NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$TAILORMOUSE_NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
fi
hdiutil verify "$DMG"
printf 'DMG ready: %s\n' "$DMG"
