#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/.local/build/TailorMouse.app"
DESTINATION="/Applications/TailorMouse.app"
STAGED="/Applications/.TailorMouse-install-$$.app"
trap 'rm -rf "$STAGED"' EXIT
bash "$ROOT/scripts/build-app.sh"
codesign --verify --strict "$SOURCE"
# Installation never launches input handling or changes another mouse manager.
if pgrep -x TailorMouse >/dev/null; then
    printf 'Quit TailorMouse before replacing the installed app.\n' >&2
    exit 1
fi
ditto "$SOURCE" "$STAGED"
codesign --verify --strict "$STAGED"
if [[ -e "$DESTINATION" ]]; then
    BACKUP="$ROOT/.local/backups/TailorMouse-$(date +%Y%m%d-%H%M%S).app"
    mkdir -p "$(dirname "$BACKUP")"
    ditto "$DESTINATION" "$BACKUP"
    rm -rf "$DESTINATION"
fi
mv "$STAGED" "$DESTINATION"
codesign --verify --strict "$DESTINATION"
printf 'Installed %s. Open the app; handling starts automatically when enabled.\n' "$DESTINATION"
