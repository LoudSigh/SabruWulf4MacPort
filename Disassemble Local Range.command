#!/bin/bash
set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "$0")" && pwd -P)"
cd "$ROOT"
RAM="$ROOT/reverse_engineering/private/snapshot-803e4197989c-48k.bin"
RAM_SHA="6de170c1b2518c82c5bfefc0f7dbfc8b8766097e020950d51b01baf045064864"

if [[ $# != 2 || ! "$1" =~ ^0[xX][0-9a-fA-F]{4}$ || ! "$2" =~ ^[0-9]+$ ]]; then
    printf 'Usage: %s <RAM start address, 0x4000..0xFFFF> <byte count, 1..4096>\n' "$0" >&2
    exit 1
fi
start=$((16#${1:2}))
length=$((10#$2))
if (( start < 0x4000 || start > 0xFFFF || length < 1 || length > 4096
    || start + length > 0x10000 )); then
    printf 'The requested range must fit inside the captured 48K RAM and be at most 4096 bytes.\n' >&2
    exit 1
fi
if ! command -v z80dasm >/dev/null 2>&1; then
    printf 'Install z80dasm to produce an ignored, provisional local listing.\n' >&2
    exit 1
fi
if [[ ! -f "$RAM" || "$(shasum -a 256 "$RAM" | awk '{print $1}')" != "$RAM_SHA" ]]; then
    printf 'Missing or changed private 48K RAM extraction. Run the preview launcher with the verified gameplay snapshot first.\n' >&2
    exit 1
fi

printf -v label '%04X' "$start"
output="$ROOT/reverse_engineering/private/linear-${label}-${length}.asm"
if [[ -e "$output" ]]; then
    printf 'Refusing to overwrite existing private disassembly: %s\n' "$output" >&2
    exit 1
fi
if [[ -n "$(git ls-files -- "$output")" ]] || ! git check-ignore -q "$output"; then
    printf 'The disassembly output is not safely ignored by Git: %s\n' "$output" >&2
    exit 1
fi

work="$(mktemp -d "$ROOT/reverse_engineering/private/.disassemble-XXXXXXXX")"
trap 'rm -f "$work/range.bin" "$work/range.asm"; rmdir "$work"' EXIT
dd if="$RAM" of="$work/range.bin" bs=1 skip="$((start - 0x4000))" \
    count="$length" status=none
z80dasm -g "$start" -a -l -o "$work/range.asm" "$work/range.bin" >/dev/null
{
    printf '; PROVISIONAL local linear decoding of a bounded RAM range.\n'
    printf '; Unknown bytes may be data or mutable; this does not establish executed code or original tape equivalence.\n'
    cat "$work/range.asm"
} > "$output"
printf 'Ignored private listing ready: %s\nDo not add disassembly or source bytes to GitHub.\n' "$output"
