#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd -P)"
SOURCE="$ROOT/SNAPSHOTS/SabreWulf.ay"
SOURCE_SHA="7643bfae575c172413fafe2877c04eab0f618af73483dc82fc6b4fe17eba2cfb"
PLAYER="${SLOPAY_BIN:-SlopAY}"
SONG="${1:-0}"

case "$SONG" in
    0|1|2|3) ;;
    *)
        printf 'Choose AY song index 0, 1, 2 or 3.\n' >&2
        exit 1
        ;;
esac
OUTPUT="$ROOT/SNAPSHOTS/SabreWulf-local-song-${SONG}.wav"

if [[ ! -f "$SOURCE" ]]; then
    printf 'Missing your local AY file: %s\n' "$SOURCE" >&2
    exit 1
fi
if [[ "$(shasum -a 256 "$SOURCE" | awk '{print $1}')" != "$SOURCE_SHA" ]]; then
    printf 'The AY file differs from the supplied source. Refusing to render a mislabeled soundtrack.\n' >&2
    exit 1
fi
if ! command -v "$PLAYER" >/dev/null 2>&1; then
    printf 'SlopAY is required to render ZX Spectrum AY music. Build the MIT-licensed player from https://github.com/dpt/SlopAY and set SLOPAY_BIN to its executable.\n' >&2
    exit 1
fi

WORK="$(mktemp -d "$ROOT/SNAPSHOTS/.alternative-audio-XXXXXXXX")"
trap 'rm -f "$WORK/render.wav"; rmdir "$WORK"' EXIT
"$PLAYER" -s "$SONG" -t 0 -w "$WORK/render.wav" "$SOURCE"
afinfo "$WORK/render.wav" >/dev/null
if [[ -e "$OUTPUT" ]]; then
    if ! cmp -s "$OUTPUT" "$WORK/render.wav"; then
        printf 'Existing alternative soundtrack differs; refusing to overwrite %s\n' "$OUTPUT" >&2
        exit 1
    fi
else
    mv "$WORK/render.wav" "$OUTPUT"
fi
printf 'Private AY beeper recording ready: %s\nImport it in the app. Its timing has not been checked against the supplied gameplay snapshot.\n' "$OUTPUT"
