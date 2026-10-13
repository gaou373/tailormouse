#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
BUILD="$ROOT/.local/build"
xcrun swift build -c release --scratch-path "$BUILD/swift"
BIN_DIR="$(xcrun swift build -c release --scratch-path "$BUILD/swift" --show-bin-path)"
xcrun swiftc -parse-as-library -D TAILORMOUSE_UI_PREVIEW -I "$BIN_DIR/Modules" -I "$BIN_DIR/NativeHIDBridge.build" \
    Sources/TailorMouse/*.swift "$BIN_DIR/TailorMouseCore.build/"*.swift.o "$BIN_DIR/NativeHIDBridge.build/"*.o \
    -o "$BUILD/TailorMouseUIRender"
"$BUILD/TailorMouseUIRender" "$ROOT/.local/ui"
