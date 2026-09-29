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

printf 'Checking the source actor-kind handler pointer table without exporting pointers...\n'
if ! swiftc -O -parse-as-library -module-cache-path "$ROOT/$PRIVATE/module-cache" \
    "$CORE"/*.swift Sources/GameCore/*.swift \
    reverse_engineering/tools/SnapshotHandlerIndex.swift \
    -o "$ROOT/$PRIVATE/SnapshotHandlerIndex" \
    > "$ROOT/$PRIVATE/handler-index-build.log" 2>&1; then
    cat "$ROOT/$PRIVATE/handler-index-build.log" >&2
    exit 1
fi
"$ROOT/$PRIVATE/SnapshotHandlerIndex" --self-test \
    > "$ROOT/$PRIVATE/handler-index-self-test.log"
"$ROOT/$PRIVATE/SnapshotHandlerIndex" "$MENU" "$GAME" \
    > "$ROOT/$PRIVATE/handler-index-report.json"
if ! jq -e --slurpfile published reverse_engineering/analysis/actor-handler-index.json '
    .schemaVersion == $published[0].schemaVersion
    and .menuSnapshotSHA256 == $published[0].menuSnapshotSHA256
    and .gameplaySnapshotSHA256 == $published[0].gameplaySnapshotSHA256
    and .start == $published[0].start
    and .endExclusive == $published[0].endExclusive
    and .pointerCount == $published[0].pointerCount
    and .dataByteCount == $published[0].dataByteCount
    and .distinctTargets == $published[0].distinctTargets
    and .pointerBytesSHA256 == $published[0].pointerBytesSHA256
    and .lowPlayerKindGroupSharedTarget
    and .highPlayerKindGroupSharedTarget
    and .playerKindGroupsDistinct
    and .enemyKindGroupSharedTarget
    and .fourRecordKindGroupSharedTarget
    and .twoGuardianKindGroupSharedTarget
' "$ROOT/$PRIVATE/handler-index-report.json" >/dev/null; then
    printf 'Source actor-handler index does not match published numeric evidence.\n' >&2
    exit 1
fi

printf 'Checking bottom-anchored player sprite pixels in five private 100-frame runs...\n'
if ! swiftc -O -parse-as-library -module-cache-path "$ROOT/$PRIVATE/module-cache" \
    "$CORE"/*.swift Sources/GameCore/*.swift \
    reverse_engineering/tools/VerifyActorScreen.swift \
    -o "$ROOT/$PRIVATE/VerifyActorScreen" \
    > "$ROOT/$PRIVATE/actor-screen-build.log" 2>&1; then
    cat "$ROOT/$PRIVATE/actor-screen-build.log" >&2
    exit 1
fi
ACTOR_TEMP="$(mktemp "$ROOT/$PRIVATE/.actor-screen-XXXXXXXX.json")"
trap 'rm -f "$ACTOR_TEMP"' EXIT
for key in q w e r t; do
    REPORT="$ROOT/$PRIVATE/actor-screen-$key.json"
    "$ROOT/$PRIVATE/VerifyActorScreen" "$ROM" "$GAME" \
        "$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-sprite-atlas-v1.json" \
        "$key" > "$ACTOR_TEMP"
    if [[ -e "$REPORT" ]]; then
        if ! cmp -s "$REPORT" "$ACTOR_TEMP"; then
            printf 'Existing private actor-screen comparison differs: %s\n' "$REPORT" >&2
            exit 1
        fi
    else
        mv "$ACTOR_TEMP" "$REPORT"
    fi
done
rm -f "$ACTOR_TEMP"
ACTOR_DIAGNOSTIC="$ROOT/$PRIVATE/actor-screen-w-overlap-v1.json"
DIAGNOSTIC_TEMP="$(mktemp "$ROOT/$PRIVATE/.actor-overlap-XXXXXXXX.json")"
trap 'rm -f "$DIAGNOSTIC_TEMP"' EXIT
"$ROOT/$PRIVATE/VerifyActorScreen" "$ROM" "$GAME" \
    "$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-sprite-atlas-v1.json" \
    w --diagnose > "$DIAGNOSTIC_TEMP"
if ! jq -e '
    .report.nonmatchingFrames == [range(43;54)]
    and (.mismatchDetails | length) == 11
    and ([.mismatchDetails[].pixelCount] | add) == 124
    and ([.mismatchDetails[].pixelsInsideOverlappingActorBounds] | add) == 98
    and ([.mismatchDetails[].pixelsOnOverlappingActorMasks] | add) == 48
    and ([.mismatchDetails[].pixelsInOverlappingActorAttributeCells] | add) == 124
    and all(.mismatchDetails[]; .overlappingActorSlots == [18])
' "$DIAGNOSTIC_TEMP" >/dev/null; then
    printf 'Player/actor overlap diagnosis changed; stop before claiming layer fidelity.\n' >&2
    exit 1
fi
if [[ -e "$ACTOR_DIAGNOSTIC" ]]; then
    if ! cmp -s "$ACTOR_DIAGNOSTIC" "$DIAGNOSTIC_TEMP"; then
        printf 'Existing private actor overlap diagnosis differs: %s\n' "$ACTOR_DIAGNOSTIC" >&2
        exit 1
    fi
else
    mv "$DIAGNOSTIC_TEMP" "$ACTOR_DIAGNOSTIC"
fi
rm -f "$DIAGNOSTIC_TEMP"
BIT_DIAGNOSTIC="$ROOT/$PRIVATE/actor-screen-w-bits-v2.json"
DIAGNOSTIC_TEMP="$(mktemp "$ROOT/$PRIVATE/.actor-bits-XXXXXXXX.json")"
"$ROOT/$PRIVATE/VerifyActorScreen" "$ROM" "$GAME" \
    "$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-sprite-atlas-v1.json" \
    w --diagnose-bits > "$DIAGNOSTIC_TEMP"
if ! jq -e '
    .bitmapXorSourceFrames == 11
    and .checkedBitmapXorPixels == 3776
    and .matchingBitmapXorPixels == 3776
    and .bitmapDifferencesAllFrames == 64
    and .bitmapDifferencesMismatchFrames == 64
    and .bitmapDifferencesOnOtherActorMasks == 64
    and .otherActorMaskPixelsInsidePlayer == 64
    and .bitmapXorMismatchPixels == 0
    and .playerOffSourceOn == 38
    and .playerOnSourceOff == 26
' "$DIAGNOSTIC_TEMP" >/dev/null; then
    printf 'Observed two-actor bitmap XOR parity changed.\n' >&2
    exit 1
fi
if [[ -e "$BIT_DIAGNOSTIC" ]]; then
    if ! cmp -s "$BIT_DIAGNOSTIC" "$DIAGNOSTIC_TEMP"; then
        printf 'Existing private bitmap diagnosis differs: %s\n' "$BIT_DIAGNOSTIC" >&2
        exit 1
    fi
else
    mv "$DIAGNOSTIC_TEMP" "$BIT_DIAGNOSTIC"
fi
rm -f "$DIAGNOSTIC_TEMP"

printf 'Checking the captured room against source background pixels...\n'
if ! swiftc -O -parse-as-library -module-cache-path "$ROOT/$PRIVATE/module-cache" \
    "$CORE"/*.swift Sources/GameCore/*.swift \
    reverse_engineering/tools/VerifyBackgroundScreen.swift \
    -o "$ROOT/$PRIVATE/VerifyBackgroundScreen" \
    > "$ROOT/$PRIVATE/background-screen-build.log" 2>&1; then
    cat "$ROOT/$PRIVATE/background-screen-build.log" >&2
    exit 1
fi
"$ROOT/$PRIVATE/VerifyBackgroundScreen" "$ROM" "$GAME" \
    "$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-world-v2.json" \
    "$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-background-atlas-v1.json" \
    > "$ROOT/$PRIVATE/background-pixel-parity.json"
"$ROOT/$PRIVATE/VerifyBackgroundScreen" "$ROM" "$GAME" \
    "$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-world-v2.json" \
    "$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-background-atlas-v1.json" \
    --schedule reverse_engineering/analysis/upper-exit-schedule.json 180 \
    > "$ROOT/$PRIVATE/background-north-parity.json"
"$ROOT/$PRIVATE/VerifyBackgroundScreen" "$ROM" "$GAME" \
    "$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-world-v2.json" \
    "$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-background-atlas-v1.json" \
    --schedule reverse_engineering/analysis/west-early-schedule.json 260 \
    > "$ROOT/$PRIVATE/background-west-parity.json"

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
TEMP_CONTACT="$(mktemp "$ROOT/$PRIVATE/.contact-XXXXXXXX.json")"
TEMP_LONG="$(mktemp "$ROOT/$PRIVATE/.long-replay-XXXXXXXX.json")"
TEMP_LONG_CONTACT="$(mktemp "$ROOT/$PRIVATE/.long-contact-XXXXXXXX.json")"
TEMP_LONG_INJURY="$(mktemp "$ROOT/$PRIVATE/.long-injury-XXXXXXXX.json")"
TEMP_MENU="$(mktemp "$ROOT/$PRIVATE/.menu-return-XXXXXXXX.json")"
TEMP_MENU_CONTACT="$(mktemp "$ROOT/$PRIVATE/.menu-contact-XXXXXXXX.json")"
TEMP_RESTART_SCREEN="$(mktemp "$ROOT/$PRIVATE/.restart-screen-XXXXXXXX.json")"
TEMP_KEYBOARD_SCREEN="$(mktemp "$ROOT/$PRIVATE/.keyboard-screen-XXXXXXXX.json")"
TEMP_READY_SCREEN="$(mktemp "$ROOT/$PRIVATE/.ready-screen-XXXXXXXX.json")"
TEMP_PLACEMENT="$(mktemp "$ROOT/$PRIVATE/.placement-XXXXXXXX.json")"
TEMP_ATTR="$(mktemp "$ROOT/$PRIVATE/.attribute-write-XXXXXXXX.json")"
TEMP_OVERLAP="$(mktemp "$ROOT/$PRIVATE/.overlap-viewer-XXXXXXXX.json")"
TEMP_BEEPER="$(mktemp "$ROOT/$PRIVATE/.beeper-XXXXXXXX.json")"
trap 'rm -f "$TEMP_REPLAY" "$TEMP_TRANSITION" "$TEMP_HELD" "$TEMP_ROUND" "$TEMP_WEST" "$TEMP_ENTITY" "$TEMP_EAST" "$TEMP_WEST_REFERENCE" "$TEMP_ENTITY_REFERENCE" "$TEMP_FIRE" "$TEMP_COMBAT" "$TEMP_COMBAT_ENTITY" "$TEMP_CONTACT" "$TEMP_LONG" "$TEMP_LONG_CONTACT" "$TEMP_LONG_INJURY" "$TEMP_MENU" "$TEMP_MENU_CONTACT" "$TEMP_RESTART_SCREEN" "$TEMP_KEYBOARD_SCREEN" "$TEMP_READY_SCREEN" "$TEMP_PLACEMENT" "$TEMP_ATTR" "$TEMP_OVERLAP" "$TEMP_BEEPER"' EXIT
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
    "$CORE"/*.swift Sources/GameCore/*.swift \
    reverse_engineering/tools/SnapshotDivergence.swift \
    -o "$ROOT/$PRIVATE/SnapshotDivergence" > "$ROOT/$PRIVATE/divergence-build.log" 2>&1; then
    cat "$ROOT/$PRIVATE/divergence-build.log" >&2
    exit 1
fi
ATTR_REPORT="$ROOT/$PRIVATE/actor-screen-w-attribute-writes-v1.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" \
    reverse_engineering/analysis/actor-screen-w-schedule.json 100 \
    --reference-timing --require-ram-parity --watch-overlap-attributes \
    > "$TEMP_ATTR"
if ! jq -e '
    .framesCompared == 100 and .matchingRAMFrames == 100
    and (.overlapAttributeWrites | length) == 94
    and ([.overlapAttributeWrites[] | select(.previous != .value)] | length) == 31
    and ([.overlapAttributeWrites[].instructionAddress] | unique | length) == 1
    and ([.overlapAttributeWrites[] |
        select(.frame >= 43 and .frame <= 53 and .previous != .value
            and .address >= 22895 and .address <= 22896)] | length) == 22
    and ([.overlapAttributeWrites[] |
        select(.frame >= 43 and .frame <= 53 and .previous != .value
            and .address >= 22895 and .address <= 22896) |
        .frame] | unique | length) == 11
' "$TEMP_ATTR" >/dev/null; then
    printf 'Private W-overlap attribute-write observation changed.\n' >&2
    exit 1
fi
if [[ -e "$ATTR_REPORT" ]]; then
    if ! cmp -s "$ATTR_REPORT" "$TEMP_ATTR"; then
        printf 'Existing private attribute-write report differs: %s\n' "$ATTR_REPORT" >&2
        exit 1
    fi
else
    mv "$TEMP_ATTR" "$ATTR_REPORT"
fi
ATTR_CONTEXT="$ROOT/$PRIVATE/actor-screen-w-attribute-context-v1.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" \
    reverse_engineering/analysis/actor-screen-w-schedule.json 100 \
    --reference-timing --require-ram-parity --watch-overlap-registers \
    > "$TEMP_ATTR"
if ! jq -e '
    .framesCompared == 100 and .matchingRAMFrames == 100
    and (.overlapAttributeWrites | length) == 94
    and (.overlapRegisterContext | length) == 94
    and ([.overlapRegisterContext[] | select(.ix == 38658)] | length) == 78
    and ([.overlapRegisterContext[] | select(.ix == 38874)] | length) == 16
    and ([.overlapRegisterContext[] |
        select(.ix != 38658 and .ix != 38874)] | length) == 0
    and ([.overlapRegisterContext[] |
        select(.ix == 38658 and .matchingActorRecordOffsets == [5])] | length) == 78
    and ([.overlapRegisterContext[] |
        select(.ix == 38874 and .matchingActorRecordOffsets == [])] | length) == 16
    and ([range(0; (.overlapAttributeWrites | length)) as $i |
        select(.overlapRegisterContext[$i].ix == 38658
            and (.overlapAttributeWrites[$i].value % 8) == 7)] | length) == 78
    and ([range(0; (.overlapAttributeWrites | length)) as $i |
        select(.overlapRegisterContext[$i].ix == 38874
            and (.overlapAttributeWrites[$i].value % 8) != 7)] | length) == 16
    and ([range(0; (.overlapAttributeWrites | length)) as $i |
        select(.overlapAttributeWrites[$i].frame >= 43
            and .overlapAttributeWrites[$i].frame <= 53
            and .overlapAttributeWrites[$i].address >= 22895
            and .overlapAttributeWrites[$i].address <= 22896
            and .overlapAttributeWrites[$i].previous != .overlapAttributeWrites[$i].value
            and .overlapRegisterContext[$i].ix == 38658)] | length) == 11
    and ([range(0; (.overlapAttributeWrites | length)) as $i |
        select(.overlapAttributeWrites[$i].frame >= 43
            and .overlapAttributeWrites[$i].frame <= 53
            and .overlapAttributeWrites[$i].address >= 22895
            and .overlapAttributeWrites[$i].address <= 22896
            and .overlapAttributeWrites[$i].previous != .overlapAttributeWrites[$i].value
            and .overlapRegisterContext[$i].ix == 38874)] | length) == 11
' "$TEMP_ATTR" >/dev/null; then
    printf 'Private W-overlap actor-indexed attribute context changed.\n' >&2
    exit 1
fi
if [[ -e "$ATTR_CONTEXT" ]]; then
    if ! cmp -s "$ATTR_CONTEXT" "$TEMP_ATTR"; then
        printf 'Existing private attribute context differs: %s\n' "$ATTR_CONTEXT" >&2
        exit 1
    fi
else
    mv "$TEMP_ATTR" "$ATTR_CONTEXT"
fi
OVERLAP_REPLAY="$ROOT/$PRIVATE/replay-w-overlap-100-with-kind.json"
"$ROOT/$PRIVATE/SnapshotReplay" "$ROM" "$GAME" \
    --schedule reverse_engineering/analysis/actor-screen-w-schedule.json 100 \
    --reference-timing --actor-kind > "$TEMP_OVERLAP"
if [[ -e "$OVERLAP_REPLAY" ]]; then
    if ! cmp -s "$OVERLAP_REPLAY" "$TEMP_OVERLAP"; then
        printf 'Existing private W overlap replay differs: %s\n' "$OVERLAP_REPLAY" >&2
        exit 1
    fi
else
    mv "$TEMP_OVERLAP" "$OVERLAP_REPLAY"
fi
if ! "$ROOT/$PRIVATE/VerifyReferenceReplay" "$ROM" "$GAME" "$OVERLAP_REPLAY" \
    > "$ROOT/$PRIVATE/w-overlap-replay-parity.log" 2>&1; then
    cat "$ROOT/$PRIVATE/w-overlap-replay-parity.log" >&2
    exit 1
fi
if ! grep -Fx 'Verified 100/100 RAM and screen hashes against the unmodified emulator' \
    "$ROOT/$PRIVATE/w-overlap-replay-parity.log" >/dev/null; then
    printf 'Private W overlap replay has an unexpected verification result.\n' >&2
    exit 1
fi
OVERLAP_TRACE="$ROOT/$PRIVATE/trace-w-overlap-slot18-100.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" \
    reverse_engineering/analysis/actor-screen-w-schedule.json 100 \
    --trace --trace-overlap-actor --reference-timing --require-ram-parity \
    > "$TEMP_OVERLAP"
if ! jq -e '
    .framesCompared == 100 and .matchingRAMFrames == 100
    and .frameBoundaryMode == "reference-relative" and .entitySlot == 18
    and (.trace | length) == 100
    and ([.trace[] | select(.manualEntity == .fullEmulatorEntity)] | length) == 100
    and ([.trace[] | select(.index >= 43 and .index <= 53
        and .manualEntity.kind > 0
        and .manualEntity.roomID == .manualPlayer.roomID)] | length) == 11
' "$TEMP_OVERLAP" >/dev/null; then
    printf 'Private W overlap actor trace changed.\n' >&2
    exit 1
fi
if [[ -e "$OVERLAP_TRACE" ]]; then
    if ! cmp -s "$OVERLAP_TRACE" "$TEMP_OVERLAP"; then
        printf 'Existing private W overlap actor trace differs: %s\n' "$OVERLAP_TRACE" >&2
        exit 1
    fi
else
    mv "$TEMP_OVERLAP" "$OVERLAP_TRACE"
fi
if ! SABRE_PRIVATE_OVERLAP_TRACE="$OVERLAP_TRACE" \
    SABRE_PRIVATE_OVERLAP_REPLAY="$OVERLAP_REPLAY" \
    SABRE_PRIVATE_SPRITE_ATLAS="$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-sprite-atlas-v1.json" \
    swift test --filter ReferenceEntityTraceTests \
    > "$ROOT/$PRIVATE/w-overlap-import-tests.log" 2>&1; then
    cat "$ROOT/$PRIVATE/w-overlap-import-tests.log" >&2
    exit 1
fi
printf 'Checking five bounded 48K beeper-edge observations...\n'
for entry in \
    'w100|actor-screen-w-schedule.json|100|20|228' \
    't100|fire-observation-schedule.json|100|13|180' \
    'fire190|fire-before-contact-schedule.json|190|20|184' \
    'no-fire190|no-fire-encounter-schedule.json|190|26|408' \
    'unrelated190|unrelated-a-control-schedule.json|190|25|408'; do
    IFS='|' read -r name schedule frames active toggles <<< "$entry"
    "$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" \
        "reverse_engineering/analysis/$schedule" "$frames" \
        --reference-timing --require-ram-parity --watch-beeper > "$TEMP_BEEPER"
    if ! jq -e --argjson frames "$frames" --argjson active "$active" \
        --argjson toggles "$toggles" '
        .framesCompared == $frames and .matchingRAMFrames == $frames
        and (.beeperFrames | length) == $active
        and ([.beeperFrames[].evenPortWrites] | add) == $toggles
        and ([.beeperFrames[].manualToggles] | add) == $toggles
        and ([.beeperFrames[].fullEmulatorToggles] | add) == $toggles
        and ([.beeperFrames[] |
            select(.manualToggles != .fullEmulatorToggles)] | length) == 0
    ' "$TEMP_BEEPER" >/dev/null; then
        printf 'Source beeper parity changed for %s.\n' "$name" >&2
        exit 1
    fi
    REPORT="$ROOT/$PRIVATE/beeper-$name.json"
    if [[ -e "$REPORT" ]]; then
        if ! cmp -s "$REPORT" "$TEMP_BEEPER"; then
            printf 'Existing private beeper report differs: %s\n' "$REPORT" >&2
            exit 1
        fi
    else
        mv "$TEMP_BEEPER" "$REPORT"
    fi
done
if ! jq -s -e '
    def countAt($report; $frame):
        ([$report.beeperFrames[] | select(.frame == $frame) | .manualToggles][0] // 0);
    def togglesIn($report; $start; $end):
        ([ $report.beeperFrames[] |
            select(.frame >= $start and .frame <= $end) | .manualToggles ] | add // 0);
    .[0] as $fire | .[1] as $noFire | .[2] as $other |
    ([range(1; 191) as $frame |
        select(countAt($fire; $frame) != countAt($noFire; $frame)) |
        $frame][0]) == 153
    and togglesIn($noFire; 163; 168) == 224
    and togglesIn($other; 169; 174) == 224
    and togglesIn($fire; 163; 168) == 0
' "$ROOT/$PRIVATE/beeper-fire190.json" \
    "$ROOT/$PRIVATE/beeper-no-fire190.json" \
    "$ROOT/$PRIVATE/beeper-unrelated190.json" >/dev/null; then
    printf 'Bounded contact-adjacent beeper observations changed.\n' >&2
    exit 1
fi
for entry in \
    'fire190|fire-before-contact-schedule.json|184|92|163|174|0' \
    'no-fire190|no-fire-encounter-schedule.json|408|204|163|168|112' \
    'unrelated190|unrelated-a-control-schedule.json|408|204|169|174|112'; do
    IFS='|' read -r name schedule writes half start end burstHalf <<< "$entry"
    "$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" \
        "reverse_engineering/analysis/$schedule" 190 \
        --reference-timing --require-ram-parity \
        --watch-beeper --watch-beeper-writers > "$TEMP_BEEPER"
    if ! jq -e --argjson writes "$writes" --argjson half "$half" \
        --argjson start "$start" --argjson end "$end" \
        --argjson burstHalf "$burstHalf" '
        .framesCompared == 190 and .matchingRAMFrames == 190
        and (.beeperWrites | length) == $writes
        and ([.beeperWrites[].instructionAddress] | unique | length) == 2
        and ([.beeperWrites[].instructionAddress] | unique) as $sites |
            ([$sites[] as $site |
                [.beeperWrites[] | select(.instructionAddress == $site)] | length])
                == [$half, $half]
            and ([$sites[] as $site |
                [.beeperWrites[] | select(.instructionAddress == $site
                    and .frame >= $start and .frame <= $end)] | length])
                == [$burstHalf, $burstHalf]
    ' "$TEMP_BEEPER" >/dev/null; then
        printf 'Beeper writer provenance changed for %s.\n' "$name" >&2
        exit 1
    fi
    REPORT="$ROOT/$PRIVATE/beeper-writers-$name.json"
    if [[ -e "$REPORT" ]]; then
        if ! cmp -s "$REPORT" "$TEMP_BEEPER"; then
            printf 'Existing private beeper writer report differs: %s\n' "$REPORT" >&2
            exit 1
        fi
    else
        mv "$TEMP_BEEPER" "$REPORT"
    fi
done
if ! jq -s -e '
    .[0] as $noFire | .[1] as $other |
    ([$noFire.beeperWrites[] |
        select(.frame >= 163 and .frame <= 168) | .cycle]) as $noCycles |
    ([$other.beeperWrites[] |
        select(.frame >= 169 and .frame <= 174) | .cycle]) as $otherCycles |
    ($noCycles | length) == 224 and ($otherCycles | length) == 224
    and ([range(1; 224) as $i |
        select(($noCycles[$i] - $noCycles[$i - 1])
            == ($otherCycles[$i] - $otherCycles[$i - 1]))] | length) == 95
' "$ROOT/$PRIVATE/beeper-writers-no-fire190.json" \
    "$ROOT/$PRIVATE/beeper-writers-unrelated190.json" >/dev/null; then
    printf 'Contact-adjacent beeper pulse-gap comparison changed.\n' >&2
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
    CONTACT_REPORT="$ROOT/$PRIVATE/contact-check-$scenario.json"
    "$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" "$SCHEDULE" 190 \
        --reference-timing --require-ram-parity --require-contact-parity \
        > "$TEMP_CONTACT"
    if [[ -e "$CONTACT_REPORT" ]]; then
        if ! cmp -s "$CONTACT_REPORT" "$TEMP_CONTACT"; then
            printf 'Existing private contact comparison differs; refusing to overwrite %s\n' "$CONTACT_REPORT" >&2
            exit 1
        fi
    else
        mv "$TEMP_CONTACT" "$CONTACT_REPORT"
    fi
    DIRECTION_REPORT="$ROOT/$PRIVATE/direction-check-$scenario-190.json"
    "$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" "$SCHEDULE" 190 \
        --reference-timing --require-ram-parity --require-enemy-direction-parity \
        > "$TEMP_CONTACT"
    if [[ -e "$DIRECTION_REPORT" ]]; then
        if ! cmp -s "$DIRECTION_REPORT" "$TEMP_CONTACT"; then
            printf 'Existing private direction comparison differs: %s\n' "$DIRECTION_REPORT" >&2
            exit 1
        fi
    else
        mv "$TEMP_CONTACT" "$DIRECTION_REPORT"
    fi
    ACTIVE_ENEMY_REPORT="$ROOT/$PRIVATE/active-enemy-check-$scenario-190.json"
    SABRE_PRIVATE_WORLD="$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-world-v2.json" \
        "$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" "$SCHEDULE" 190 \
        --reference-timing --require-ram-parity --require-entity-phase-parity \
        > "$TEMP_CONTACT"
    if [[ -e "$ACTIVE_ENEMY_REPORT" ]]; then
        if ! cmp -s "$ACTIVE_ENEMY_REPORT" "$TEMP_CONTACT"; then
            printf 'Existing private active-enemy comparison differs: %s\n' "$ACTIVE_ENEMY_REPORT" >&2
            exit 1
        fi
    else
        mv "$TEMP_CONTACT" "$ACTIVE_ENEMY_REPORT"
    fi
    ENTITY_WRITES="$ROOT/$PRIVATE/entity-writes-$scenario-190.json"
    "$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" "$SCHEDULE" 190 \
        --reference-timing --require-ram-parity --watch-entity-state \
        > "$TEMP_CONTACT"
    if [[ -e "$ENTITY_WRITES" ]]; then
        if ! cmp -s "$ENTITY_WRITES" "$TEMP_CONTACT"; then
            printf 'Existing private entity-write trace differs: %s\n' "$ENTITY_WRITES" >&2
            exit 1
        fi
    else
        mv "$TEMP_CONTACT" "$ENTITY_WRITES"
    fi
    if [[ "$scenario" != fire-before-contact ]]; then
        PLAYER_ONSET_REPORT="$ROOT/$PRIVATE/player-onset-$scenario-190.json"
        "$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" "$SCHEDULE" 190 \
            --reference-timing --require-ram-parity --watch-player-state \
            > "$TEMP_CONTACT"
        if [[ -e "$PLAYER_ONSET_REPORT" ]]; then
            if ! cmp -s "$PLAYER_ONSET_REPORT" "$TEMP_CONTACT"; then
                printf 'Existing private injury-entry trace differs: %s\n' "$PLAYER_ONSET_REPORT" >&2
                exit 1
            fi
        else
            mv "$TEMP_CONTACT" "$PLAYER_ONSET_REPORT"
        fi
        SCORE_REPORT="$ROOT/$PRIVATE/score-parity-$scenario-190.json"
        "$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" "$SCHEDULE" 190 \
            --reference-timing --require-ram-parity --require-score-parity \
            > "$TEMP_CONTACT"
        if [[ -e "$SCORE_REPORT" ]]; then
            if ! cmp -s "$SCORE_REPORT" "$TEMP_CONTACT"; then
                printf 'Existing private score comparison differs: %s\n' "$SCORE_REPORT" >&2
                exit 1
            fi
        else
            mv "$TEMP_CONTACT" "$SCORE_REPORT"
        fi
    fi
    RNG_REPORT="$ROOT/$PRIVATE/rng-step-$scenario-190.json"
    "$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" "$SCHEDULE" 190 \
        --reference-timing --require-ram-parity --require-rng-step-parity \
        > "$TEMP_CONTACT"
    if [[ -e "$RNG_REPORT" ]]; then
        if ! cmp -s "$RNG_REPORT" "$TEMP_CONTACT"; then
            printf 'Existing private RNG comparison differs: %s\n' "$RNG_REPORT" >&2
            exit 1
        fi
    else
        mv "$TEMP_CONTACT" "$RNG_REPORT"
    fi
done
printf 'Checking a second RNG-selected enemy heading on the extended T route...\n'
EXTENDED_FIRE="$ROOT/$PRIVATE/replay-fire-before-contact-250.json"
"$ROOT/$PRIVATE/SnapshotReplay" "$ROM" "$GAME" \
    --schedule reverse_engineering/analysis/fire-before-contact-schedule.json 250 \
    --reference-timing --actor-kind > "$TEMP_COMBAT"
if [[ -e "$EXTENDED_FIRE" ]]; then
    if ! cmp -s "$EXTENDED_FIRE" "$TEMP_COMBAT"; then
        printf 'Existing extended private fire replay differs: %s\n' "$EXTENDED_FIRE" >&2
        exit 1
    fi
else
    mv "$TEMP_COMBAT" "$EXTENDED_FIRE"
fi
"$ROOT/$PRIVATE/VerifyReferenceReplay" "$ROM" "$GAME" "$EXTENDED_FIRE"
EXTENDED_ENTITY="$ROOT/$PRIVATE/trace-fire-before-contact-250.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" \
    reverse_engineering/analysis/fire-before-contact-schedule.json 250 \
    --trace --reference-timing --require-ram-parity \
    --require-enemy-direction-parity > "$TEMP_COMBAT_ENTITY"
if [[ -e "$EXTENDED_ENTITY" ]]; then
    if ! cmp -s "$EXTENDED_ENTITY" "$TEMP_COMBAT_ENTITY"; then
        printf 'Existing extended private entity trace differs: %s\n' "$EXTENDED_ENTITY" >&2
        exit 1
    fi
else
    mv "$TEMP_COMBAT_ENTITY" "$EXTENDED_ENTITY"
fi
EXTENDED_WRITES="$ROOT/$PRIVATE/entity-writes-fire-before-contact-250.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" \
    reverse_engineering/analysis/fire-before-contact-schedule.json 250 \
    --reference-timing --require-ram-parity --watch-entity-state \
    > "$TEMP_COMBAT_ENTITY"
if [[ -e "$EXTENDED_WRITES" ]]; then
    if ! cmp -s "$EXTENDED_WRITES" "$TEMP_COMBAT_ENTITY"; then
        printf 'Existing extended private entity-write trace differs: %s\n' "$EXTENDED_WRITES" >&2
        exit 1
    fi
else
    mv "$TEMP_COMBAT_ENTITY" "$EXTENDED_WRITES"
fi
FIRE_ONSET_REPORT="$ROOT/$PRIVATE/player-onset-fire-before-contact-250.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" \
    reverse_engineering/analysis/fire-before-contact-schedule.json 250 \
    --reference-timing --require-ram-parity --watch-player-state \
    > "$TEMP_COMBAT_ENTITY"
if [[ -e "$FIRE_ONSET_REPORT" ]]; then
    if ! cmp -s "$FIRE_ONSET_REPORT" "$TEMP_COMBAT_ENTITY"; then
        printf 'Existing extended private injury-entry trace differs: %s\n' "$FIRE_ONSET_REPORT" >&2
        exit 1
    fi
else
    mv "$TEMP_COMBAT_ENTITY" "$FIRE_ONSET_REPORT"
fi
FIRE_SCORE_REPORT="$ROOT/$PRIVATE/score-parity-fire-before-contact-250.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" \
    reverse_engineering/analysis/fire-before-contact-schedule.json 250 \
    --reference-timing --require-ram-parity --require-score-parity \
    > "$TEMP_COMBAT_ENTITY"
if [[ -e "$FIRE_SCORE_REPORT" ]]; then
    if ! cmp -s "$FIRE_SCORE_REPORT" "$TEMP_COMBAT_ENTITY"; then
        printf 'Existing extended private score comparison differs: %s\n' "$FIRE_SCORE_REPORT" >&2
        exit 1
    fi
else
    mv "$TEMP_COMBAT_ENTITY" "$FIRE_SCORE_REPORT"
fi
EXPIRY_REPORT="$ROOT/$PRIVATE/enemy-expiry-fire-before-contact-250.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" \
    reverse_engineering/analysis/fire-before-contact-schedule.json 250 \
    --reference-timing --require-ram-parity --require-enemy-expiry-parity \
    > "$TEMP_COMBAT_ENTITY"
if [[ -e "$EXPIRY_REPORT" ]]; then
    if ! cmp -s "$EXPIRY_REPORT" "$TEMP_COMBAT_ENTITY"; then
        printf 'Existing private expiry comparison differs: %s\n' "$EXPIRY_REPORT" >&2
        exit 1
    fi
else
    mv "$TEMP_COMBAT_ENTITY" "$EXPIRY_REPORT"
fi
EXTENDED_RNG="$ROOT/$PRIVATE/rng-step-fire-before-contact-250.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" \
    reverse_engineering/analysis/fire-before-contact-schedule.json 250 \
    --reference-timing --require-ram-parity --require-rng-step-parity \
    > "$TEMP_COMBAT_ENTITY"
if [[ -e "$EXTENDED_RNG" ]]; then
    if ! cmp -s "$EXTENDED_RNG" "$TEMP_COMBAT_ENTITY"; then
        printf 'Existing extended private RNG comparison differs: %s\n' "$EXTENDED_RNG" >&2
        exit 1
    fi
else
    mv "$TEMP_COMBAT_ENTITY" "$EXTENDED_RNG"
fi
printf 'Checking source enemy direction values and seventeen private motion steps...\n'
if ! SABRE_PRIVATE_MENU_RAM="$ROOT/$PRIVATE/snapshot-${MENU_SHA:0:12}-48k.bin" \
    SABRE_PRIVATE_GAME_RAM="$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-48k.bin" \
    swift test --filter CapturedEnemyDirectionTests \
    > "$ROOT/$PRIVATE/enemy-direction-test.log" 2>&1; then
    cat "$ROOT/$PRIVATE/enemy-direction-test.log" >&2
    exit 1
fi
if ! SABRE_PRIVATE_WORLD="$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-world-v2.json" \
    SABRE_PRIVATE_ENTITY_TRACE_DIR="$ROOT/$PRIVATE" \
    SABRE_PRIVATE_FIRE_EXTENDED_TRACE="$EXTENDED_ENTITY" \
    SABRE_PRIVATE_FIRE_EXTENDED_REPLAY="$EXTENDED_FIRE" \
    swift test --filter 'CapturedEntityMotionTests/testPrivateEnemyMovesAgainstReferenceWhenProvided' \
    > "$ROOT/$PRIVATE/entity-motion-test.log" 2>&1; then
    cat "$ROOT/$PRIVATE/entity-motion-test.log" >&2
    exit 1
fi
if ! SABRE_PRIVATE_WORLD="$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-world-v2.json" \
    SABRE_PRIVATE_ENTITY_TRACE_DIR="$ROOT/$PRIVATE" \
    SABRE_PRIVATE_FIRE_EXTENDED_WRITES="$EXTENDED_WRITES" \
    swift test --filter CapturedActiveEnemyStateTests \
    > "$ROOT/$PRIVATE/active-enemy-test.log" 2>&1; then
    cat "$ROOT/$PRIVATE/active-enemy-test.log" >&2
    exit 1
fi
if ! SABRE_PRIVATE_ENEMY_EXPIRY_REPORT="$EXPIRY_REPORT" \
    swift test --filter CapturedEnemyExpiryTests \
    > "$ROOT/$PRIVATE/enemy-expiry-test.log" 2>&1; then
    cat "$ROOT/$PRIVATE/enemy-expiry-test.log" >&2
    exit 1
fi
if ! SABRE_PRIVATE_ENTITY_TRACE_DIR="$ROOT/$PRIVATE" \
    swift test --filter CapturedRNGStepTests \
    > "$ROOT/$PRIVATE/rng-step-test.log" 2>&1; then
    cat "$ROOT/$PRIVATE/rng-step-test.log" >&2
    exit 1
fi
printf 'Preparing a private 600-frame injury and remaining-life observation...\n'
LONG_REPLAY="$ROOT/$PRIVATE/replay-no-fire-600.json"
"$ROOT/$PRIVATE/SnapshotReplay" "$ROM" "$GAME" \
    --schedule reverse_engineering/analysis/no-fire-encounter-schedule.json 600 \
    --reference-timing --actor-kind > "$TEMP_LONG"
if [[ -e "$LONG_REPLAY" ]]; then
    if ! cmp -s "$LONG_REPLAY" "$TEMP_LONG"; then
        printf 'Existing private long replay differs; refusing to overwrite %s\n' "$LONG_REPLAY" >&2
        exit 1
    fi
else
    mv "$TEMP_LONG" "$LONG_REPLAY"
fi
"$ROOT/$PRIVATE/VerifyReferenceReplay" "$ROM" "$GAME" "$LONG_REPLAY"
LONG_CONTACT="$ROOT/$PRIVATE/contact-check-no-fire-encounter-600.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" \
    reverse_engineering/analysis/no-fire-encounter-schedule.json 600 \
    --reference-timing --require-ram-parity --require-contact-parity \
    > "$TEMP_LONG_CONTACT"
if [[ -e "$LONG_CONTACT" ]]; then
    if ! cmp -s "$LONG_CONTACT" "$TEMP_LONG_CONTACT"; then
        printf 'Existing private long contact comparison differs; refusing to overwrite %s\n' "$LONG_CONTACT" >&2
        exit 1
    fi
else
    mv "$TEMP_LONG_CONTACT" "$LONG_CONTACT"
fi
LONG_INJURY="$ROOT/$PRIVATE/injury-check-no-fire-encounter-600.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" \
    reverse_engineering/analysis/no-fire-encounter-schedule.json 600 \
    --reference-timing --require-ram-parity --require-contact-parity \
    --require-first-injury-parity > "$TEMP_LONG_INJURY"
if [[ -e "$LONG_INJURY" ]]; then
    if ! cmp -s "$LONG_INJURY" "$TEMP_LONG_INJURY"; then
        printf 'Existing private injury comparison differs; refusing to overwrite %s\n' "$LONG_INJURY" >&2
        exit 1
    fi
else
    mv "$TEMP_LONG_INJURY" "$LONG_INJURY"
fi
printf 'Verifying private returns to the menu after the second contact...\n'
for spec in no-fire-encounter:503 unrelated-a-control:510 fire-before-contact:679; do
    scenario="${spec%%:*}"
    firstMenuFrame="${spec#*:}"
    MENU_REPLAY="$ROOT/$PRIVATE/replay-$scenario-800.json"
    MENU_CONTACT="$ROOT/$PRIVATE/menu-sequence-$scenario-800.json"
    "$ROOT/$PRIVATE/SnapshotReplay" "$ROM" "$GAME" \
        --schedule "reverse_engineering/analysis/$scenario-schedule.json" 800 \
        --reference-timing --actor-kind > "$TEMP_MENU"
    if [[ -e "$MENU_REPLAY" ]]; then
        if ! cmp -s "$MENU_REPLAY" "$TEMP_MENU"; then
            printf 'Existing private menu-return replay differs: %s\n' "$MENU_REPLAY" >&2
            exit 1
        fi
    else
        mv "$TEMP_MENU" "$MENU_REPLAY"
    fi
    "$ROOT/$PRIVATE/VerifyReferenceReplay" "$ROM" "$GAME" "$MENU_REPLAY" \
        --menu "$MENU" "$firstMenuFrame"
    "$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" \
        "reverse_engineering/analysis/$scenario-schedule.json" 800 \
        --reference-timing --require-ram-parity --require-contact-parity \
        --require-first-injury-parity --require-menu-sequence > "$TEMP_MENU_CONTACT"
    if [[ -e "$MENU_CONTACT" ]]; then
        if ! cmp -s "$MENU_CONTACT" "$TEMP_MENU_CONTACT"; then
            printf 'Existing private menu-return contact comparison differs: %s\n' "$MENU_CONTACT" >&2
            exit 1
        fi
    else
        mv "$TEMP_MENU_CONTACT" "$MENU_CONTACT"
    fi
done
printf 'Verifying private zero-key restart and first fully drawn source room...\n'
RESTART_SCHEDULE=reverse_engineering/analysis/restart-after-menu-schedule.json
RESTART_REPLAY="$ROOT/$PRIVATE/replay-restart-after-menu-800.json"
"$ROOT/$PRIVATE/SnapshotReplay" "$ROM" "$GAME" \
    --schedule "$RESTART_SCHEDULE" 800 --reference-timing --actor-kind \
    > "$TEMP_MENU"
if [[ -e "$RESTART_REPLAY" ]]; then
    if ! cmp -s "$RESTART_REPLAY" "$TEMP_MENU"; then
        printf 'Existing private restart replay differs: %s\n' "$RESTART_REPLAY" >&2
        exit 1
    fi
else
    mv "$TEMP_MENU" "$RESTART_REPLAY"
fi
"$ROOT/$PRIVATE/VerifyReferenceReplay" "$ROM" "$GAME" "$RESTART_REPLAY" \
    --menu "$MENU" 503
RESTART_CONTACT="$ROOT/$PRIVATE/restart-contact-800.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" "$RESTART_SCHEDULE" 800 \
    --reference-timing --require-ram-parity --require-contact-parity \
    --require-first-injury-parity --require-menu-sequence \
    > "$TEMP_MENU_CONTACT"
if [[ -e "$RESTART_CONTACT" ]]; then
    if ! cmp -s "$RESTART_CONTACT" "$TEMP_MENU_CONTACT"; then
        printf 'Existing private restart contact check differs: %s\n' "$RESTART_CONTACT" >&2
        exit 1
    fi
else
    mv "$TEMP_MENU_CONTACT" "$RESTART_CONTACT"
fi
RESTART_SCREEN="$ROOT/$PRIVATE/restart-background-664.json"
"$ROOT/$PRIVATE/VerifyBackgroundScreen" "$ROM" "$GAME" \
    "$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-world-v2.json" \
    "$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-background-atlas-v1.json" \
    --schedule "$RESTART_SCHEDULE" 664 > "$TEMP_RESTART_SCREEN"
if [[ -e "$RESTART_SCREEN" ]]; then
    if ! cmp -s "$RESTART_SCREEN" "$TEMP_RESTART_SCREEN"; then
        printf 'Existing private restart screen check differs: %s\n' "$RESTART_SCREEN" >&2
        exit 1
    fi
else
    mv "$TEMP_RESTART_SCREEN" "$RESTART_SCREEN"
fi
printf 'Verifying movement after selecting keyboard control on the returned menu...\n'
KEYBOARD_SCHEDULE=reverse_engineering/analysis/restart-keyboard-movement-schedule.json
KEYBOARD_REPLAY="$ROOT/$PRIVATE/replay-restart-keyboard-movement-800.json"
"$ROOT/$PRIVATE/SnapshotReplay" "$ROM" "$GAME" \
    --schedule "$KEYBOARD_SCHEDULE" 800 --reference-timing --actor-kind \
    > "$TEMP_MENU"
if [[ -e "$KEYBOARD_REPLAY" ]]; then
    if ! cmp -s "$KEYBOARD_REPLAY" "$TEMP_MENU"; then
        printf 'Existing private keyboard-restart replay differs: %s\n' "$KEYBOARD_REPLAY" >&2
        exit 1
    fi
else
    mv "$TEMP_MENU" "$KEYBOARD_REPLAY"
fi
"$ROOT/$PRIVATE/VerifyReferenceReplay" "$ROM" "$GAME" "$KEYBOARD_REPLAY" \
    --menu "$MENU" 503
KEYBOARD_CONTACT="$ROOT/$PRIVATE/restart-keyboard-contact-800.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" "$KEYBOARD_SCHEDULE" 800 \
    --reference-timing --require-ram-parity --require-contact-parity \
    --require-first-injury-parity --require-menu-sequence \
    > "$TEMP_MENU_CONTACT"
if [[ -e "$KEYBOARD_CONTACT" ]]; then
    if ! cmp -s "$KEYBOARD_CONTACT" "$TEMP_MENU_CONTACT"; then
        printf 'Existing private keyboard-restart contact check differs: %s\n' "$KEYBOARD_CONTACT" >&2
        exit 1
    fi
else
    mv "$TEMP_MENU_CONTACT" "$KEYBOARD_CONTACT"
fi
KEYBOARD_SCREEN="$ROOT/$PRIVATE/restart-keyboard-background-800.json"
"$ROOT/$PRIVATE/VerifyBackgroundScreen" "$ROM" "$GAME" \
    "$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-world-v2.json" \
    "$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-background-atlas-v1.json" \
    --schedule "$KEYBOARD_SCHEDULE" 800 > "$TEMP_KEYBOARD_SCREEN"
if [[ -e "$KEYBOARD_SCREEN" ]]; then
    if ! cmp -s "$KEYBOARD_SCREEN" "$TEMP_KEYBOARD_SCREEN"; then
        printf 'Existing private keyboard-restart screen check differs: %s\n' "$KEYBOARD_SCREEN" >&2
        exit 1
    fi
else
    mv "$TEMP_KEYBOARD_SCREEN" "$KEYBOARD_SCREEN"
fi
printf 'Verifying the bounded native movement slice after source new-game setup...\n'
READY_SCHEDULE=reverse_engineering/analysis/restart-ready-movement-schedule.json
READY_REPLAY="$ROOT/$PRIVATE/replay-restart-ready-movement-900.json"
"$ROOT/$PRIVATE/SnapshotReplay" "$ROM" "$GAME" \
    --schedule "$READY_SCHEDULE" 900 --reference-timing --actor-kind \
    > "$TEMP_MENU"
if [[ -e "$READY_REPLAY" ]]; then
    if ! cmp -s "$READY_REPLAY" "$TEMP_MENU"; then
        printf 'Existing private ready-movement replay differs: %s\n' "$READY_REPLAY" >&2
        exit 1
    fi
else
    mv "$TEMP_MENU" "$READY_REPLAY"
fi
"$ROOT/$PRIVATE/VerifyReferenceReplay" "$ROM" "$GAME" "$READY_REPLAY" \
    --menu "$MENU" 503
printf 'Extracting four private, unidentified frame-656 actor records...\n'
if ! swiftc -O -parse-as-library -module-cache-path "$ROOT/$PRIVATE/module-cache" \
    "$CORE"/*.swift Sources/GameCore/*.swift \
    reverse_engineering/tools/SnapshotPlacementExport.swift \
    -o "$ROOT/$PRIVATE/SnapshotPlacementExport" \
    > "$ROOT/$PRIVATE/placement-build.log" 2>&1; then
    cat "$ROOT/$PRIVATE/placement-build.log" >&2
    exit 1
fi
PLACEMENT="$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-placement-frame656-v1.json"
"$ROOT/$PRIVATE/SnapshotPlacementExport" "$ROM" "$GAME" "$READY_REPLAY" \
    "$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-world-v2.json" \
    "$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-sprite-atlas-v1.json" \
    > "$TEMP_PLACEMENT"
if [[ -e "$PLACEMENT" ]]; then
    if ! cmp -s "$PLACEMENT" "$TEMP_PLACEMENT"; then
        printf 'Existing private placement export differs: %s\n' "$PLACEMENT" >&2
        exit 1
    fi
else
    mv "$TEMP_PLACEMENT" "$PLACEMENT"
fi
if ! SABRE_PRIVATE_WORLD="$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-world-v2.json" \
    SABRE_PRIVATE_ATLAS="$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-sprite-atlas-v1.json" \
    SABRE_PRIVATE_PLACEMENT="$PLACEMENT" \
    swift test --filter CapturedPlacementStateTests \
    > "$ROOT/$PRIVATE/placement-import-test.log" 2>&1; then
    cat "$ROOT/$PRIVATE/placement-import-test.log" >&2
    exit 1
fi
READY_CONTACT="$ROOT/$PRIVATE/restart-ready-contact-900.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" "$READY_SCHEDULE" 900 \
    --reference-timing --require-ram-parity --require-contact-parity \
    --require-first-injury-parity --require-menu-sequence \
    > "$TEMP_MENU_CONTACT"
if [[ -e "$READY_CONTACT" ]]; then
    if ! cmp -s "$READY_CONTACT" "$TEMP_MENU_CONTACT"; then
        printf 'Existing private ready-movement contact check differs: %s\n' "$READY_CONTACT" >&2
        exit 1
    fi
else
    mv "$TEMP_MENU_CONTACT" "$READY_CONTACT"
fi
READY_SCREEN="$ROOT/$PRIVATE/restart-ready-background-900.json"
"$ROOT/$PRIVATE/VerifyBackgroundScreen" "$ROM" "$GAME" \
    "$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-world-v2.json" \
    "$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-background-atlas-v1.json" \
    --schedule "$READY_SCHEDULE" 900 > "$TEMP_READY_SCREEN"
if [[ -e "$READY_SCREEN" ]]; then
    if ! cmp -s "$READY_SCREEN" "$TEMP_READY_SCREEN"; then
        printf 'Existing private ready-movement screen check differs: %s\n' "$READY_SCREEN" >&2
        exit 1
    fi
else
    mv "$TEMP_READY_SCREEN" "$READY_SCREEN"
fi
printf 'Checking bounded Q/E/R source paths after new-game setup...\n'
for direction in q e r; do
    READY_SCHEDULE="reverse_engineering/analysis/restart-ready-$direction-schedule.json"
    READY_REPLAY="$ROOT/$PRIVATE/replay-restart-ready-$direction-900.json"
    "$ROOT/$PRIVATE/SnapshotReplay" "$ROM" "$GAME" \
        --schedule "$READY_SCHEDULE" 900 --reference-timing --actor-kind \
        > "$TEMP_MENU"
    if [[ -e "$READY_REPLAY" ]]; then
        if ! cmp -s "$READY_REPLAY" "$TEMP_MENU"; then
            printf 'Existing private %s replay differs: %s\n' "$direction" "$READY_REPLAY" >&2
            exit 1
        fi
    else
        mv "$TEMP_MENU" "$READY_REPLAY"
    fi
    "$ROOT/$PRIVATE/VerifyReferenceReplay" "$ROM" "$GAME" "$READY_REPLAY" \
        --menu "$MENU" 503
    READY_CONTACT="$ROOT/$PRIVATE/restart-ready-contact-$direction-900.json"
    "$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" "$READY_SCHEDULE" 900 \
        --reference-timing --require-ram-parity --require-contact-parity \
        --require-first-injury-parity --require-menu-sequence \
        > "$TEMP_MENU_CONTACT"
    if [[ -e "$READY_CONTACT" ]]; then
        if ! cmp -s "$READY_CONTACT" "$TEMP_MENU_CONTACT"; then
            printf 'Existing private %s contact check differs: %s\n' "$direction" "$READY_CONTACT" >&2
            exit 1
        fi
    else
        mv "$TEMP_MENU_CONTACT" "$READY_CONTACT"
    fi
    READY_SCREEN="$ROOT/$PRIVATE/restart-ready-background-$direction-900.json"
    "$ROOT/$PRIVATE/VerifyBackgroundScreen" "$ROM" "$GAME" \
        "$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-world-v2.json" \
        "$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-background-atlas-v1.json" \
        --schedule "$READY_SCHEDULE" 900 > "$TEMP_READY_SCREEN"
    if [[ -e "$READY_SCREEN" ]]; then
        if ! cmp -s "$READY_SCREEN" "$TEMP_READY_SCREEN"; then
            printf 'Existing private %s screen check differs: %s\n' "$direction" "$READY_SCREEN" >&2
            exit 1
        fi
    else
        mv "$TEMP_READY_SCREEN" "$READY_SCREEN"
    fi
done
printf 'Checking one bounded W-then-E source path after new-game setup...\n'
MIXED_SCHEDULE=reverse_engineering/analysis/restart-ready-w-e-schedule.json
MIXED_REPLAY="$ROOT/$PRIVATE/replay-restart-ready-w-e-900.json"
"$ROOT/$PRIVATE/SnapshotReplay" "$ROM" "$GAME" \
    --schedule "$MIXED_SCHEDULE" 900 --reference-timing --actor-kind \
    > "$TEMP_MENU"
if [[ -e "$MIXED_REPLAY" ]]; then
    if ! cmp -s "$MIXED_REPLAY" "$TEMP_MENU"; then
        printf 'Existing private W/E replay differs: %s\n' "$MIXED_REPLAY" >&2
        exit 1
    fi
else
    mv "$TEMP_MENU" "$MIXED_REPLAY"
fi
"$ROOT/$PRIVATE/VerifyReferenceReplay" "$ROM" "$GAME" "$MIXED_REPLAY" \
    --menu "$MENU" 503
MIXED_CONTACT="$ROOT/$PRIVATE/restart-ready-mixed-contact-900.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" "$MIXED_SCHEDULE" 900 \
    --reference-timing --require-ram-parity --require-contact-parity \
    --require-first-injury-parity --require-menu-sequence \
    > "$TEMP_MENU_CONTACT"
if [[ -e "$MIXED_CONTACT" ]]; then
    if ! cmp -s "$MIXED_CONTACT" "$TEMP_MENU_CONTACT"; then
        printf 'Existing private W/E contact comparison differs: %s\n' "$MIXED_CONTACT" >&2
        exit 1
    fi
else
    mv "$TEMP_MENU_CONTACT" "$MIXED_CONTACT"
fi
MIXED_SCREEN="$ROOT/$PRIVATE/restart-ready-mixed-background-900.json"
"$ROOT/$PRIVATE/VerifyBackgroundScreen" "$ROM" "$GAME" \
    "$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-world-v2.json" \
    "$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-background-atlas-v1.json" \
    --schedule "$MIXED_SCHEDULE" 900 > "$TEMP_READY_SCREEN"
if [[ -e "$MIXED_SCREEN" ]]; then
    if ! cmp -s "$MIXED_SCREEN" "$TEMP_READY_SCREEN"; then
        printf 'Existing private W/E screen comparison differs: %s\n' "$MIXED_SCREEN" >&2
        exit 1
    fi
else
    mv "$TEMP_READY_SCREEN" "$MIXED_SCREEN"
fi
printf 'Checking a bounded W-then-Q reversal after new-game setup...\n'
REVERSE_SCHEDULE=reverse_engineering/analysis/restart-ready-w-q-schedule.json
REVERSE_REPLAY="$ROOT/$PRIVATE/replay-restart-ready-w-q-900.json"
"$ROOT/$PRIVATE/SnapshotReplay" "$ROM" "$GAME" \
    --schedule "$REVERSE_SCHEDULE" 900 --reference-timing --actor-kind \
    > "$TEMP_MENU"
if [[ -e "$REVERSE_REPLAY" ]]; then
    if ! cmp -s "$REVERSE_REPLAY" "$TEMP_MENU"; then
        printf 'Existing private W/Q replay differs: %s\n' "$REVERSE_REPLAY" >&2
        exit 1
    fi
else
    mv "$TEMP_MENU" "$REVERSE_REPLAY"
fi
"$ROOT/$PRIVATE/VerifyReferenceReplay" "$ROM" "$GAME" "$REVERSE_REPLAY" \
    --menu "$MENU" 503
REVERSE_PARITY="$ROOT/$PRIVATE/restart-ready-reverse-contact-900.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" "$REVERSE_SCHEDULE" 900 \
    --reference-timing --require-ram-parity --require-contact-parity \
    --watch-actor-state > "$TEMP_MENU_CONTACT"
if [[ -e "$REVERSE_PARITY" ]]; then
    if ! cmp -s "$REVERSE_PARITY" "$TEMP_MENU_CONTACT"; then
        printf 'Existing private W/Q RAM comparison differs: %s\n' "$REVERSE_PARITY" >&2
        exit 1
    fi
else
    mv "$TEMP_MENU_CONTACT" "$REVERSE_PARITY"
fi
REVERSE_PLAYER_WRITES="$ROOT/$PRIVATE/restart-ready-w-q-player-writes-v2-900.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" "$REVERSE_SCHEDULE" 900 \
    --reference-timing --require-ram-parity --watch-player-state \
    > "$TEMP_MENU_CONTACT"
if [[ -e "$REVERSE_PLAYER_WRITES" ]]; then
    if ! cmp -s "$REVERSE_PLAYER_WRITES" "$TEMP_MENU_CONTACT"; then
        printf 'Existing private W/Q player-write trace differs: %s\n' "$REVERSE_PLAYER_WRITES" >&2
        exit 1
    fi
else
    mv "$TEMP_MENU_CONTACT" "$REVERSE_PLAYER_WRITES"
fi
REVERSE_LONG_INJURY="$ROOT/$PRIVATE/restart-ready-w-q-full-injury-1500.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" "$REVERSE_SCHEDULE" 1500 \
    --reference-timing --require-ram-parity --require-first-injury-parity \
    --watch-player-state > "$TEMP_MENU_CONTACT"
if [[ -e "$REVERSE_LONG_INJURY" ]]; then
    if ! cmp -s "$REVERSE_LONG_INJURY" "$TEMP_MENU_CONTACT"; then
        printf 'Existing private four-life injury comparison differs: %s\n' "$REVERSE_LONG_INJURY" >&2
        exit 1
    fi
else
    mv "$TEMP_MENU_CONTACT" "$REVERSE_LONG_INJURY"
fi
REVERSE_MENU_REPLAY="$ROOT/$PRIVATE/replay-restart-ready-w-q-1800.json"
"$ROOT/$PRIVATE/SnapshotReplay" "$ROM" "$GAME" \
    --schedule "$REVERSE_SCHEDULE" 1800 --reference-timing --actor-kind \
    > "$TEMP_MENU"
if [[ -e "$REVERSE_MENU_REPLAY" ]]; then
    if ! cmp -s "$REVERSE_MENU_REPLAY" "$TEMP_MENU"; then
        printf 'Existing private W/Q menu-return replay differs: %s\n' "$REVERSE_MENU_REPLAY" >&2
        exit 1
    fi
else
    mv "$TEMP_MENU" "$REVERSE_MENU_REPLAY"
fi
"$ROOT/$PRIVATE/VerifyReferenceReplay" "$ROM" "$GAME" \
    "$REVERSE_MENU_REPLAY" --menu-after "$MENU" 1500 1733
REVERSE_SCORE_REPLAY="$ROOT/$PRIVATE/replay-restart-ready-w-q-score-1800.json"
"$ROOT/$PRIVATE/SnapshotReplay" "$ROM" "$GAME" \
    --schedule "$REVERSE_SCHEDULE" 1800 --reference-timing --actor-kind --score \
    > "$TEMP_MENU"
if [[ -e "$REVERSE_SCORE_REPLAY" ]]; then
    if ! cmp -s "$REVERSE_SCORE_REPLAY" "$TEMP_MENU"; then
        printf 'Existing private W/Q score replay differs: %s\n' "$REVERSE_SCORE_REPLAY" >&2
        exit 1
    fi
else
    mv "$TEMP_MENU" "$REVERSE_SCORE_REPLAY"
fi
"$ROOT/$PRIVATE/VerifyReferenceReplay" "$ROM" "$GAME" \
    "$REVERSE_SCORE_REPLAY" --menu-after "$MENU" 1500 1733
REVERSE_MENU_ROUTINES="$ROOT/$PRIVATE/restart-ready-w-q-menu-1800.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" "$REVERSE_SCHEDULE" 1800 \
    --reference-timing --require-ram-parity --watch-player-state \
    --watch-menu-routines > "$TEMP_MENU_CONTACT"
if [[ -e "$REVERSE_MENU_ROUTINES" ]]; then
    if ! cmp -s "$REVERSE_MENU_ROUTINES" "$TEMP_MENU_CONTACT"; then
        printf 'Existing private W/Q menu-routine comparison differs: %s\n' "$REVERSE_MENU_ROUTINES" >&2
        exit 1
    fi
else
    mv "$TEMP_MENU_CONTACT" "$REVERSE_MENU_ROUTINES"
fi
REVERSE_LONG_CONTACT="$ROOT/$PRIVATE/restart-ready-w-q-contact-1800.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" "$REVERSE_SCHEDULE" 1800 \
    --reference-timing --require-ram-parity --require-contact-parity \
    --watch-player-state > "$TEMP_MENU_CONTACT"
if [[ -e "$REVERSE_LONG_CONTACT" ]]; then
    if ! cmp -s "$REVERSE_LONG_CONTACT" "$TEMP_MENU_CONTACT"; then
        printf 'Existing private W/Q long contact comparison differs: %s\n' "$REVERSE_LONG_CONTACT" >&2
        exit 1
    fi
else
    mv "$TEMP_MENU_CONTACT" "$REVERSE_LONG_CONTACT"
fi
REVERSE_SCORE_REPORT="$ROOT/$PRIVATE/score-parity-w-q-1800.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" "$REVERSE_SCHEDULE" 1800 \
    --reference-timing --require-ram-parity --require-score-parity \
    > "$TEMP_MENU_CONTACT"
if [[ -e "$REVERSE_SCORE_REPORT" ]]; then
    if ! cmp -s "$REVERSE_SCORE_REPORT" "$TEMP_MENU_CONTACT"; then
        printf 'Existing private W/Q score comparison differs: %s\n' "$REVERSE_SCORE_REPORT" >&2
        exit 1
    fi
else
    mv "$TEMP_MENU_CONTACT" "$REVERSE_SCORE_REPORT"
fi
printf 'Preparing a healthy E-then-Q source route into the western room...\n'
E_Q_SCHEDULE=reverse_engineering/analysis/restart-ready-e-q-west-schedule.json
E_Q_REPLAY="$ROOT/$PRIVATE/replay-restart-e-q-west-1050.json"
"$ROOT/$PRIVATE/SnapshotReplay" "$ROM" "$GAME" \
    --schedule "$E_Q_SCHEDULE" 1050 --reference-timing --actor-kind \
    > "$TEMP_MENU"
if [[ -e "$E_Q_REPLAY" ]]; then
    if ! cmp -s "$E_Q_REPLAY" "$TEMP_MENU"; then
        printf 'Existing private E/Q west-arrival replay differs: %s\n' "$E_Q_REPLAY" >&2
        exit 1
    fi
else
    mv "$TEMP_MENU" "$E_Q_REPLAY"
fi
if ! "$ROOT/$PRIVATE/VerifyReferenceReplay" "$ROM" "$GAME" "$E_Q_REPLAY" \
    > "$ROOT/$PRIVATE/e-q-west-replay-verification.log" 2>&1; then
    cat "$ROOT/$PRIVATE/e-q-west-replay-verification.log" >&2
    exit 1
fi
if ! grep -Fx 'Verified 1050/1050 RAM and screen hashes against the unmodified emulator' \
    "$ROOT/$PRIVATE/e-q-west-replay-verification.log" >/dev/null; then
    printf 'E/Q replay did not verify exactly 1,050 RAM and screen frames.\n' >&2
    exit 1
fi
if ! jq -e '
    (.frames | length) == 1050
    and .frames[818].playerRoomID == 152
    and .frames[894].playerRoomID == 151
    and .frames[901].playerX == 239
    and .frames[920].playerKind == 18
    and .frames[921].playerKind == 64
    and .frames[1003].reportedLives == 3
' "$E_Q_REPLAY" >/dev/null; then
    printf 'E/Q source room transition or injury checkpoint changed.\n' >&2
    exit 1
fi
E_Q_CONTACT="$ROOT/$PRIVATE/e-q-west-contact-check-1050.json"
"$ROOT/$PRIVATE/SnapshotDivergence" "$ROM" "$GAME" "$E_Q_SCHEDULE" 1050 \
    --reference-timing --require-ram-parity --require-contact-parity \
    > "$TEMP_MENU_CONTACT"
if ! jq -e '
    .framesCompared == 1050 and .matchingRAMFrames == 1050
    and .contactComparison.calls == 3188
    and .contactComparison.matchingCalls == 3188
    and .contactComparison.positiveFrames == [162, 298, 921, 1038]
' "$TEMP_MENU_CONTACT" >/dev/null; then
    printf 'E/Q source contact boundary changed.\n' >&2
    exit 1
fi
if [[ -e "$E_Q_CONTACT" ]]; then
    if ! cmp -s "$E_Q_CONTACT" "$TEMP_MENU_CONTACT"; then
        printf 'Existing private E/Q contact report differs: %s\n' "$E_Q_CONTACT" >&2
        exit 1
    fi
else
    mv "$TEMP_MENU_CONTACT" "$E_Q_CONTACT"
fi
printf 'Checking bounded native post-setup positions and sprite IDs on five paths...\n'
if ! SABRE_PRIVATE_WORLD="$ROOT/$PRIVATE/snapshot-${GAME_SHA:0:12}-world-v2.json" \
    SABRE_PRIVATE_NEW_GAME_REPLAY="$ROOT/$PRIVATE/replay-restart-ready-movement-900.json" \
    SABRE_PRIVATE_NEW_GAME_REPLAY_DIR="$ROOT/$PRIVATE" \
    SABRE_PRIVATE_NEW_GAME_MIXED_REPLAY="$MIXED_REPLAY" \
    SABRE_PRIVATE_NEW_GAME_REVERSE_REPLAY="$REVERSE_REPLAY" \
    SABRE_PRIVATE_NEW_GAME_REVERSE_CONTACT="$REVERSE_PARITY" \
    SABRE_PRIVATE_E_Q_WEST_REPLAY="$E_Q_REPLAY" \
    swift test --filter 'CapturedMovementTests/testPrivate(ObservedNewGameMovementWhenProvided|MixedNewGamePathWhenProvided|ReversedNewGamePathWhenProvided|ReverseContactBoundaryWhenProvided|EThenQWestArrivalWhenProvided)' \
    > "$ROOT/$PRIVATE/new-game-movement-test.log" 2>&1; then
    cat "$ROOT/$PRIVATE/new-game-movement-test.log" >&2
    exit 1
fi
if ! SABRE_PRIVATE_NEW_GAME_INJURY_WRITES="$REVERSE_PLAYER_WRITES" \
    SABRE_PRIVATE_NEW_GAME_INJURY_COUNTDOWN="$REVERSE_LONG_INJURY" \
    swift test --filter 'Captured(NewGame|Intermediate)InjuryTickTests' \
    > "$ROOT/$PRIVATE/new-game-injury-test.log" 2>&1; then
    cat "$ROOT/$PRIVATE/new-game-injury-test.log" >&2
    exit 1
fi
if ! SABRE_PRIVATE_NEW_GAME_INJURY_COUNTDOWN="$REVERSE_LONG_INJURY" \
    swift test --filter 'Captured(First|Final)InjuryTickTests' \
    > "$ROOT/$PRIVATE/injury-countdown-test.log" 2>&1; then
    cat "$ROOT/$PRIVATE/injury-countdown-test.log" >&2
    exit 1
fi
if ! SABRE_PRIVATE_INJURY_START_DIR="$ROOT/$PRIVATE" \
    SABRE_PRIVATE_LONG_WQ_CONTACT="$REVERSE_LONG_CONTACT" \
    swift test --filter CapturedInjuryStartTests \
    > "$ROOT/$PRIVATE/injury-start-test.log" 2>&1; then
    cat "$ROOT/$PRIVATE/injury-start-test.log" >&2
    exit 1
fi
if ! SABRE_PRIVATE_INJURY_START_DIR="$ROOT/$PRIVATE" \
    SABRE_PRIVATE_LONG_WQ_CONTACT="$REVERSE_LONG_CONTACT" \
    swift test --filter CapturedContactArmingTests \
    > "$ROOT/$PRIVATE/contact-arming-test.log" 2>&1; then
    cat "$ROOT/$PRIVATE/contact-arming-test.log" >&2
    exit 1
fi
if ! SABRE_PRIVATE_NEW_GAME_MENU_REPORT="$REVERSE_MENU_ROUTINES" \
    SABRE_PRIVATE_LONG_WQ_REPLAY="$REVERSE_MENU_REPLAY" \
    SABRE_PRIVATE_LONG_SCORE_REPLAY="$REVERSE_SCORE_REPLAY" \
    swift test --filter 'CapturedNewGameMenuReturnTests|ReferenceReplayTests/testPrivateLong(Menu|Score)ReplayWhenProvided' \
    > "$ROOT/$PRIVATE/new-game-menu-return-test.log" 2>&1; then
    cat "$ROOT/$PRIVATE/new-game-menu-return-test.log" >&2
    exit 1
fi
if ! SABRE_PRIVATE_SCORE_REPORT_DIR="$ROOT/$PRIVATE" \
    swift test --filter CapturedScoreStepTests \
    > "$ROOT/$PRIVATE/score-step-test.log" 2>&1; then
    cat "$ROOT/$PRIVATE/score-step-test.log" >&2
    exit 1
fi
AWARD_ORACLE="$ROOT/$PRIVATE/record-award-oracle-frame-792.json"
if [[ -f "$AWARD_ORACLE" ]]; then
    export SABRE_PRIVATE_RECORD_AWARD="$AWARD_ORACLE"
else
    unset SABRE_PRIVATE_RECORD_AWARD
    printf 'Optional original edited-RAM record award oracle absent.\n'
fi
AWARD_REPORTS_PRESENT=1
for id in 0 1 2 3; do
    if [[ ! -f "$ROOT/$PRIVATE/quest-inventory-id-$id.json"
        || ! -f "$ROOT/$PRIVATE/quest-relocation-score-operands-id-$id-private.json" ]]; then
        AWARD_REPORTS_PRESENT=0
    fi
done
if [[ "$AWARD_REPORTS_PRESENT" == 1 ]]; then
    export SABRE_PRIVATE_RECORD_AWARD_DIR="$ROOT/$PRIVATE"
else
    unset SABRE_PRIVATE_RECORD_AWARD_DIR
    printf 'Optional four edited-RAM record/progress oracles absent; testing synthetic results only.\n'
fi
if ! swift test --filter CapturedRecordAwardTests \
    > "$ROOT/$PRIVATE/record-award-test.log" 2>&1; then
    cat "$ROOT/$PRIVATE/record-award-test.log" >&2
    exit 1
fi
unset SABRE_PRIVATE_RECORD_AWARD
unset SABRE_PRIVATE_RECORD_AWARD_DIR
ITEM_REPORTS_PRESENT=1
for id in 0 1 2 3; do
    if [[ ! -f "$ROOT/$PRIVATE/quest-item-contact-id-$id.json"
        || ! -f "$ROOT/$PRIVATE/quest-item-contact-negative-id-$id.json" ]]; then
        ITEM_REPORTS_PRESENT=0
    fi
done
if [[ "$ITEM_REPORTS_PRESENT" == 1 ]]; then
    export SABRE_PRIVATE_ITEM_CONTACT_DIR="$ROOT/$PRIVATE"
else
    unset SABRE_PRIVATE_ITEM_CONTACT_DIR
    printf 'Optional edited-RAM item contact oracles absent; testing synthetic predicate only.\n'
fi
if ! swift test --filter CapturedItemContactTests \
    > "$ROOT/$PRIVATE/item-contact-test.log" 2>&1; then
    cat "$ROOT/$PRIVATE/item-contact-test.log" >&2
    exit 1
fi
unset SABRE_PRIVATE_ITEM_CONTACT_DIR
GUARD_ORACLE="$ROOT/$PRIVATE/guard-gate-branch30.json"
if [[ -f "$GUARD_ORACLE" ]]; then
    export SABRE_PRIVATE_GUARD_GATE="$GUARD_ORACLE"
else
    unset SABRE_PRIVATE_GUARD_GATE
    printf 'Optional edited guardian branch oracle absent; testing synthetic branch choice only.\n'
fi
if ! swift test --filter CapturedGuardianGateTests \
    > "$ROOT/$PRIVATE/guardian-gate-test.log" 2>&1; then
    cat "$ROOT/$PRIVATE/guardian-gate-test.log" >&2
    exit 1
fi
unset SABRE_PRIVATE_GUARD_GATE
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
