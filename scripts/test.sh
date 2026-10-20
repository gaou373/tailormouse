#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
xcrun swift test --build-system native "$@"
# Check actual native queue/Stop ordering with a fake backend, never live HID.
BIN_DIR="$(xcrun swift build --build-system native --show-bin-path)"
mkdir -p .local/build
xcrun swiftc -parse-as-library -I "$BIN_DIR/Modules" -I "$BIN_DIR/NativeHIDBridge.build" \
    Sources/TailorMouse/NativePointer.swift scripts/test-tracking-worker.swift \
    "$BIN_DIR/TailorMouseCore.build/"*.swift.o "$BIN_DIR/NativeHIDBridge.build/"*.o \
    -o .local/build/TrackingWorkerChecks
.local/build/TrackingWorkerChecks
