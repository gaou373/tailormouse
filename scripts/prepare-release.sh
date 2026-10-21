#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/build-dmg.sh"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/.local/build/TailorMouse.app/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT/.local/build/TailorMouse.app/Contents/Info.plist")"
OUTPUT="$ROOT/.local/releases/$VERSION"
TOOLS="$ROOT/.local/build/swift/artifacts/sparkle/Sparkle/bin"
ACCOUNT="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["keychainAccount"])' "$ROOT/release/update-config.json")"
# Fail rather than silently rotate keys and strand existing installations.
PUBLIC_KEY="$("$TOOLS/generate_keys" --account "$ACCOUNT" -p)"
EXPECTED_KEY="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["publicKey"])' "$ROOT/release/update-config.json")"
if [[ "$PUBLIC_KEY" != "$EXPECTED_KEY" ]]; then printf 'The publisher signing key does not match the bundled public key.\n' >&2; exit 1; fi
DMG="$OUTPUT/TailorMouse-$VERSION-universal.dmg"
SIGNATURE="$("$TOOLS/sign_update" --account "$ACCOUNT" -p "$DMG")"
"$TOOLS/sign_update" --account "$ACCOUNT" --verify "$DMG" "$SIGNATURE"
/usr/bin/python3 "$ROOT/scripts/create-appcast.py" "$ROOT/release/update-config.json" "$DMG" "$VERSION" "$BUILD_NUMBER" "$SIGNATURE" "$OUTPUT/appcast.xml"
"$TOOLS/sign_update" --account "$ACCOUNT" "$OUTPUT/appcast.xml"
"$TOOLS/sign_update" --account "$ACCOUNT" --verify "$OUTPUT/appcast.xml"
(cd "$OUTPUT" && shasum -a 256 "TailorMouse-$VERSION-universal.dmg" appcast.xml > SHA256SUMS.txt)
printf 'Prepared signed release files in %s\nNothing has been uploaded.\n' "$OUTPUT"
