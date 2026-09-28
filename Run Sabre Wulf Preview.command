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

printf 'Recovering a private 196-ID sprite atlas from matching snapshots...\n'
if ! swiftc -O -parse-as-library -module-cache-path "$ROOT/$PRIVATE/module-cache" \
    "$CORE"/*.swift reverse_engineering/tools/SnapshotSpriteIndex.swift \
    -o "$ROOT/$PRIVATE/SnapshotSpriteIndex" > "$ROOT/$PRIVATE/sprite-index-build.log" 2>&1; then
    cat "$ROOT/$PRIVATE/sprite-index-build.log" >&2
    exit 1
fi
"$ROOT/$PRIVATE/SnapshotSpriteIndex" "$MENU" "$GAME" --private-atlas \
    > "$ROOT/$PRIVATE/sprite-index-report.json"

printf 'Preparing a private 100-frame Q-key reference replay...\n'
if ! swiftc -O -parse-as-library -module-cache-path "$ROOT/$PRIVATE/module-cache" \
    "$CORE"/*.swift reverse_engineering/tools/SnapshotReplay.swift \
    -o "$ROOT/$PRIVATE/SnapshotReplay" > "$ROOT/$PRIVATE/replay-build.log" 2>&1; then
    cat "$ROOT/$PRIVATE/replay-build.log" >&2
    exit 1
fi
REPLAY="$ROOT/$PRIVATE/replay-q-100.json"
TEMP_REPLAY="$(mktemp "$ROOT/$PRIVATE/.replay-XXXXXXXX.json")"
TEMP_TRANSITION="$(mktemp "$ROOT/$PRIVATE/.transition-XXXXXXXX.json")"
TEMP_HELD="$(mktemp "$ROOT/$PRIVATE/.held-XXXXXXXX.json")"
TEMP_ROUND="$(mktemp "$ROOT/$PRIVATE/.round-XXXXXXXX.json")"
TEMP_WEST="$(mktemp "$ROOT/$PRIVATE/.west-XXXXXXXX.json")"
TEMP_ENTITY="$(mktemp "$ROOT/$PRIVATE/.entity-XXXXXXXX.json")"
TEMP_EAST="$(mktemp "$ROOT/$PRIVATE/.east-XXXXXXXX.json")"
TEMP_WEST_REFERENCE="$(mktemp "$ROOT/$PRIVATE/.west-reference-XXXXXXXX.json")"
TEMP_ENTITY_REFERENCE="$(mktemp "$ROOT/$PRIVATE/.entity-reference-XXXXXXXX.json")"
TEMP_FIRE="$(mktemp "$ROOT/$PRIVATE/.fire-XXXXXXXX.json")"
TEMP_COMBAT="$(mktemp "$ROOT/$PRIVATE/.combat-XXXXXXXX.json")"
TEMP_COMBAT_ENTITY="$(mktemp "$ROOT/$PRIVATE/.combat-entity-XXXXXXXX.json")"
trap 'rm -f "$TEMP_REPLAY" "$TEMP_TRANSITION" "$TEMP_HELD" "$TEMP_ROUND" "$TEMP_WEST" "$TEMP_ENTITY" "$TEMP_EAST" "$TEMP_WEST_REFERENCE" "$TEMP_ENTITY_REFERENCE" "$TEMP_FIRE" "$TEMP_COMBAT" "$TEMP_COMBAT_ENTITY"' EXIT
"$ROOT/$PRIVATE/SnapshotReplay" "$ROM" "$GAME" q 100 > "$TEMP_REPLAY"
if [[ -e "$REPLAY" ]]; then
    if ! cmp -s "$REPLAY" "$TEMP_REPLAY"; then
        printf 'Existing private replay differs; refusing to overwrite %s\n' "$REPLAY" >&2
        exit 1
    fi
else
    mv "$TEMP_REPLAY" "$REPLAY"
fi

printf 'Preparing a private two-key replay that crosses the upper room boundary...\n'
TRANSITION="$ROOT/$PRIVATE/replay-upper-exit-180.json"
"$ROOT/$PRIVATE/SnapshotReplay" "$ROM" "$GAME" \
    --schedule reverse_engineering/analysis/upper-exit-schedule.json 180 > "$TEMP_TRANSITION"
if [[ -e "$TRANSITION" ]]; then
    if ! cmp -s "$TRANSITION" "$TEMP_TRANSITION"; then
        printf 'Existing private transition replay differs; refusing to overwrite %s\n' "$TRANSITION" >&2
        exit 1
    fi
else
    mv "$TEMP_TRANSITION" "$TRANSITION"
fi

printf 'Preparing a private 200-frame round-trip reference...\n'
ROUND_TRIP="$ROOT/$PRIVATE/replay-round-trip-200.json"
"$ROOT/$PRIVATE/SnapshotReplay" "$ROM" "$GAME" \
    --schedule reverse_engineering/analysis/round-trip-schedule.json 200 > "$TEMP_ROUND"
if [[ -e "$ROUND_TRIP" ]]; then
    if ! cmp -s "$ROUND_TRIP" "$TEMP_ROUND"; then
        printf 'Existing private round-trip replay differs; refusing to overwrite %s\n' "$ROUND_TRIP" >&2
        exit 1
    fi
else
    mv "$TEMP_ROUND" "$ROUND_TRIP"
fi

printf 'Preparing a private provisional west-exit reference...\n'
WEST_EXIT="$ROOT/$PRIVATE/replay-west-exit-256.json"
"$ROOT/$PRIVATE/SnapshotReplay" "$ROM" "$GAME" \
    --schedule reverse_engineering/analysis/west-exit-schedule.json 256 > "$TEMP_WEST"
if [[ -e "$WEST_EXIT" ]]; then
    if ! cmp -s "$WEST_EXIT" "$TEMP_WEST"; then
        printf 'Existing private west-exit replay differs; refusing to overwrite %s\n' "$WEST_EXIT" >&2
        exit 1
    fi
else
    mv "$TEMP_WEST" "$WEST_EXIT"
fi

printf 'Preparing the frame-aligned west replay for independent reference comparison...\n'
WEST_REFERENCE="$ROOT/$PRIVATE/replay-west-reference-256.json"
"$ROOT/$PRIVATE/SnapshotReplay" "$ROM" "$GAME" \
    --schedule reverse_engineering/analysis/west-exit-schedule.json 256 \
    --reference-timing > "$TEMP_WEST_REFERENCE"
if [[ -e "$WEST_REFERENCE" ]]; then
    if ! cmp -s "$WEST_REFERENCE" "$TEMP_WEST_REFERENCE"; then
        printf 'Existing private frame-aligned replay differs; refusing to overwrite %s\n' "$WEST_REFERENCE" >&2
        exit 1
    fi
else
    mv "$TEMP_WEST_REFERENCE" "$WEST_REFERENCE"
fi
if ! swiftc -O -parse-as-library -module-cache-path "$ROOT/$PRIVATE/module-cache" \
    "$CORE"/*.swift reverse_engineering/tools/VerifyReferenceReplay.swift \
    -o "$ROOT/$PRIVATE/VerifyReferenceReplay" > "$ROOT/$PRIVATE/replay-verify-build.log" 2>&1; then
    cat "$ROOT/$PRIVATE/replay-verify-build.log" >&2
    exit 1
fi
"$ROOT/$PRIVATE/VerifyReferenceReplay" "$ROM" "$GAME" "$WEST_REFERENCE"

printf 'Preparing a verified private 100-frame T-key actor-state observation...\n'
FIRE_REPLAY="$ROOT/$PRIVATE/replay-fire-reference-100.json"
"$ROOT/$PRIVATE/SnapshotReplay" "$ROM" "$GAME" \
    --schedule reverse_engineering/analysis/fire-observation-schedule.json 100 \
    --reference-timing --actor-kind > "$TEMP_FIRE"
if [[ -e "$FIRE_REPLAY" ]]; then
    if ! cmp -s "$FIRE_REPLAY" "$TEMP_FIRE"; then
        printf 'Existing private fire observation differs; refusing to overwrite %s\n' "$FIRE_REPLAY" >&2
        exit 1
    fi
else
    mv "$TEMP_FIRE" "$FIRE_REPLAY"
fi
"$ROOT/$PRIVATE/VerifyReferenceReplay" "$ROM" "$GAME" "$FIRE_REPLAY"

printf 'Preparing a private provisional east-return reference...\n'
EAST_RETURN="$ROOT/$PRIVATE/replay-east-return-279.json"
"$ROOT/$PRIVATE/SnapshotReplay" "$ROM" "$GAME" \
    --schedule reverse_engineering/analysis/east-return-schedule.json 279 > "$TEMP_EAST"
if [[ -e "$EAST_RETURN" ]]; then
    if ! cmp -s "$EAST_RETURN" "$TEMP_EAST"; then
        printf 'Existing private east-return replay differs; refusing to overwrite %s\n' "$EAST_RETURN" >&2
        exit 1
    fi
else
    mv "$TEMP_EAST" "$EAST_RETURN"
fi

printf 'Comparing a private moving-entity path across both reference runners...\n'
if ! swiftc -O -parse-as-library -module-cache-path "$ROOT/$PRIVATE/module-cache" \
    "$CORE"/*.swift reverse_engineering/tools/SnapshotDivergence.swift \
    -o "$ROOT/$PRIVATE/SnapshotDivergence" > "$ROOT/$PRIVATE/divergence-build.log" 2>&1; then
    cat "$ROOT/$PRIVATE/divergence-build.log" >&2
    exit 1
fi
ENTITY_TRACE="$ROOT/$PRIVATE/west-entity-trace-v2.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" \
    reverse_engineering/analysis/west-exit-schedule.json 256 --trace > "$TEMP_ENTITY"
if [[ -e "$ENTITY_TRACE" ]]; then
    if ! cmp -s "$ENTITY_TRACE" "$TEMP_ENTITY"; then
        printf 'Existing private entity comparison differs; refusing to overwrite %s\n' "$ENTITY_TRACE" >&2
        exit 1
    fi
else
    mv "$TEMP_ENTITY" "$ENTITY_TRACE"
fi

ENTITY_REFERENCE="$ROOT/$PRIVATE/west-entity-reference.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" \
    reverse_engineering/analysis/west-exit-schedule.json 256 \
    --trace --reference-timing --require-ram-parity > "$TEMP_ENTITY_REFERENCE"
if [[ -e "$ENTITY_REFERENCE" ]]; then
    if ! cmp -s "$ENTITY_REFERENCE" "$TEMP_ENTITY_REFERENCE"; then
        printf 'Existing private frame-aligned entity trace differs; refusing to overwrite %s\n' "$ENTITY_REFERENCE" >&2
        exit 1
    fi
else
    mv "$TEMP_ENTITY_REFERENCE" "$ENTITY_REFERENCE"
fi

printf 'Preparing three verified 190-frame pre-contact T/no-T/unrelated-key comparisons...\n'
for scenario in fire-before-contact no-fire-encounter unrelated-a-control; do
    SCHEDULE="reverse_engineering/analysis/$scenario-schedule.json"
    SCENARIO_REPLAY="$ROOT/$PRIVATE/replay-$scenario-190.json"
    SCENARIO_TRACE="$ROOT/$PRIVATE/trace-$scenario-190.json"
    "$ROOT/$PRIVATE/SnapshotReplay" "$ROM" "$GAME" \
        --schedule "$SCHEDULE" 190 --reference-timing --actor-kind > "$TEMP_COMBAT"
    if [[ -e "$SCENARIO_REPLAY" ]]; then
        if ! cmp -s "$SCENARIO_REPLAY" "$TEMP_COMBAT"; then
            printf 'Existing private attack comparison differs; refusing to overwrite %s\n' "$SCENARIO_REPLAY" >&2
            exit 1
        fi
    else
        mv "$TEMP_COMBAT" "$SCENARIO_REPLAY"
    fi
    "$ROOT/$PRIVATE/VerifyReferenceReplay" "$ROM" "$GAME" "$SCENARIO_REPLAY"
    "$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" "$SCHEDULE" 190 \
        --trace --reference-timing --require-ram-parity > "$TEMP_COMBAT_ENTITY"
    if [[ -e "$SCENARIO_TRACE" ]]; then
        if ! cmp -s "$SCENARIO_TRACE" "$TEMP_COMBAT_ENTITY"; then
            printf 'Existing private entity comparison differs; refusing to overwrite %s\n' "$SCENARIO_TRACE" >&2
            exit 1
        fi
    else
        mv "$TEMP_COMBAT_ENTITY" "$SCENARIO_TRACE"
    fi
done
printf 'Preparing four private 150-frame held-direction references...\n'
for key in q w e r; do
    HELD="$ROOT/$PRIVATE/hold-$key-150.json"
    "$ROOT/$PRIVATE/SnapshotReplay" "$ROM" "$GAME" "$key" 150 --hold > "$TEMP_HELD"
    if [[ -e "$HELD" ]]; then
        if ! cmp -s "$HELD" "$TEMP_HELD"; then
            printf 'Existing private held-direction replay differs; refusing to overwrite %s\n' "$HELD" >&2
            exit 1
        fi
    else
        mv "$TEMP_HELD" "$HELD"
    fi
done

MENU_PNG="$ROOT/$PRIVATE/snapshot-${MENU_SHA:0:12}-screen.png"
GAME_PNG="$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-screen.png"
WORLD_MAP="$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-world.html"
BACKGROUND_ATLAS="$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-background-atlas-v1.json"
SPRITE_ATLAS="$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-sprite-atlas-v1.json"
require_file "$MENU_PNG"
require_file "$GAME_PNG"
require_file "$WORLD_MAP"
require_file "$BACKGROUND_ATLAS"
require_file "$SPRITE_ATLAS"

if ! command -v xcodegen >/dev/null 2>&1; then
    printf 'Missing xcodegen. Reference images are ready in %s, but the native prototype cannot be built.\n' "$PRIVATE" >&2
    exit 1
fi
printf 'Building the native macOS app (placeholder gameplay plus separate measured movement preview)...\n'
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
printf 'Inside the app, import %s to scrub a recorded Q-key actor path.\n' "$REPLAY"
printf 'Import %s to scrub a recorded transition into the adjacent room.\n' "$TRANSITION"
printf 'Import %s to scrub a recorded return to the captured room.\n' "$ROUND_TRIP"
printf 'Import %s for a provisional west exit; an enemy changes the independent emulator actor state before late Q.\n' "$WEST_EXIT"
printf 'Import %s for the same schedule aligned to the full emulator (enemy contact included in the recorded state).\n' "$WEST_REFERENCE"
printf 'Import %s to observe T-key actor state without claiming native combat.\n' "$FIRE_REPLAY"
printf 'Import %s for a provisional east return; a moving enemy blocks the source at frame 280.\n' "$EAST_RETURN"
printf 'Import %s with the legacy west replay to compare different enemy paths, or %s with the aligned replay to inspect matching paths.\n' "$ENTITY_TRACE" "$ENTITY_REFERENCE"
printf 'Import replay-fire-before-contact-190.json or replay-no-fire-encounter-190.json from %s, each with its matching trace-*.json, to compare source attack effects.\n' "$PRIVATE"
printf 'Use replay-unrelated-a-control-190.json and its matching trace as a keyboard-timing control, not a combat outcome.\n'
printf 'Import the private world JSON, then select Start measured movement (partial) to run the source-backed movement slice.\n'
printf 'Import %s to preview decoded background geometry in all source rooms.\n' "$BACKGROUND_ATLAS"
printf 'Import %s to browse decoded private bitmap silhouettes without bundled source art.\n' "$SPRITE_ATLAS"
printf 'Use Command-Tab to switch. The captures/map are not playable and the prototype is not yet the 1984 game.\n'
