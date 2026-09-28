#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd -P)"
cd "$ROOT"

BACKUP="${SPECCY_BACKUP:-/Volumes/July2025inclOct2022/Visual Studio Code Backups/Carbon Neural/2025-09-13_22-10-25/CarbonNeural_portable_2025-09-13_22-10-25}"
ROM="$BACKUP/ROMS/48.rom"
CORE="$BACKUP/Sources/SpeccyCore"
MENU="SNAPSHOTS/Snapshot.z80"
GAME="SNAPSHOTS/Snapshot_GamePlay.z80"
PRIVATE="reverse_engineering/private"
MENU_SHA="34d98ec3dc55d60755a7d9ceebe45c3a7e345ce5961692d25d2d6718bcdc20ea"
GAME_SHA="803e4197989c73408cfc5113f8f30c81ac0269958aa9e105b474b6f52437203c"
ROM_SHA="d55daa439b673b0e3f5897f99ac37ecb45f974d1862b4dadb85dec34af99cb42"

require_file() {
    if [[ ! -f "$1" ]]; then
        printf 'Missing required file: %s\n' "$1" >&2
        exit 1
    fi
}

check_sha() {
    local actual
    actual="$(shasum -a 256 "$1" | awk '{print $1}')"
    if [[ "$actual" != "$2" ]]; then
        printf 'Unexpected SHA-256 for %s\nExpected: %s\nActual:   %s\n' "$1" "$2" "$actual" >&2
        exit 1
    fi
}

require_file "$MENU"
require_file "$GAME"
require_file "$ROM"
require_file "$CORE/Z80Snapshot.swift"
check_sha "$MENU" "$MENU_SHA"
check_sha "$GAME" "$GAME_SHA"
check_sha "$ROM" "$ROM_SHA"

mkdir -p "$PRIVATE"
if ! git check-ignore -q "$PRIVATE/"; then
    printf 'Refusing to generate original game images: %s is not ignored by Git.\n' "$PRIVATE" >&2
    exit 1
fi
umask 077

printf 'Rendering your private, static Spectrum menu and gameplay captures...\n'
if ! swiftc -O -parse-as-library -module-cache-path "$ROOT/$PRIVATE/module-cache" \
    "$CORE"/*.swift reverse_engineering/tools/SnapshotExport.swift \
    -o "$ROOT/$PRIVATE/SnapshotExport" > "$ROOT/$PRIVATE/export-build.log" 2>&1; then
    cat "$ROOT/$PRIVATE/export-build.log" >&2
    exit 1
fi
"$ROOT/$PRIVATE/SnapshotExport" "$MENU" --screen "$ROM"
"$ROOT/$PRIVATE/SnapshotExport" "$GAME" --screen "$ROM"

printf 'Building a private 16x16 world-type overview from your snapshots...\n'
if ! swiftc -O -parse-as-library -module-cache-path "$ROOT/$PRIVATE/module-cache" \
    "$CORE"/*.swift reverse_engineering/tools/SnapshotRoomIndex.swift \
    -o "$ROOT/$PRIVATE/SnapshotRoomIndex" > "$ROOT/$PRIVATE/room-index-build.log" 2>&1; then
    cat "$ROOT/$PRIVATE/room-index-build.log" >&2
    exit 1
fi
"$ROOT/$PRIVATE/SnapshotRoomIndex" "$MENU" "$GAME" --private-map \
    > "$ROOT/$PRIVATE/room-index-report.json"

MENU_PNG="$ROOT/$PRIVATE/snapshot-${MENU_SHA:0:12}-screen.png"
GAME_PNG="$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-screen.png"
WORLD_MAP="$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-world.html"
require_file "$MENU_PNG"
require_file "$GAME_PNG"
require_file "$WORLD_MAP"

if ! command -v xcodegen >/dev/null 2>&1; then
    printf 'Missing xcodegen. Reference images are ready in %s, but the native prototype cannot be built.\n' "$PRIVATE" >&2
    exit 1
fi
printf 'Building the native macOS prototype (independently authored placeholder gameplay)...\n'
xcodegen generate
xcodebuild -quiet -project SabreWulf.xcodeproj -scheme SabreWulfMac \
    -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath "$ROOT/$PRIVATE/DerivedData" CODE_SIGNING_ALLOWED=NO build

APP="$ROOT/$PRIVATE/DerivedData/Build/Products/Debug/SabreWulfMac.app"
require_file "$APP/Contents/MacOS/SabreWulfMac"
open "$APP"
open -a Preview "$MENU_PNG" "$GAME_PNG"
open "$WORLD_MAP"
printf '\nOpened the native placeholder app, two original static captures, and a private world-type map.\n'
printf 'Use Command-Tab to switch. The captures/map are not playable and the prototype is not yet the 1984 game.\n'
