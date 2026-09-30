#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd -P)"
cd "$ROOT"
PRIVATE="$ROOT/reverse_engineering/private"
mkdir -p "$PRIVATE"
if ! git check-ignore -q "$PRIVATE/"; then
    printf 'Private reference directory must be ignored by Git: %s\n' "$PRIVATE" >&2
    exit 1
fi
if ! command -v xcodegen >/dev/null 2>&1; then
    printf 'Install xcodegen to build the native Mac app.\n' >&2
    exit 1
fi

xcodegen generate
xcodebuild -quiet -project SabreWulf.xcodeproj -scheme SabreWulfMac \
    -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath "$PRIVATE/DerivedData" CODE_SIGNING_ALLOWED=NO build

APP="$PRIVATE/DerivedData/Build/Products/Debug/SabreWulfMac.app"
if [[ ! -x "$APP/Contents/MacOS/SabreWulfMac" ]]; then
    printf 'The native Mac app was not produced: %s\n' "$APP" >&2
    exit 1
fi
if [[ -f "$PRIVATE/snapshot-803e4197989c-world-v2.json" ]]; then
    open -n "$APP" --args --local-reference-dir "$PRIVATE" --play-experimental-world
    printf 'Opened the native experimental world using the private reference folder %s.\n' "$PRIVATE"
else
    open -n "$APP"
    printf 'First run Run Sabre Wulf Preview.command to generate the verified, private world files.\n'
fi
