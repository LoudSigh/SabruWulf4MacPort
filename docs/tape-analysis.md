# Read-only tape inventory

The user-identified source image is outside this Git repository. Configure its path locally:

```sh
export SABRE_WULF_TZX='/Volumes/July2025inclOct2022/Visual Studio Code Backups/Carbon Neural/2025-09-13_22-10-25/CarbonNeural_portable_2025-09-13_22-10-25/ROMS/Sabre Wulf (1984)(Ultimate Play The Game).tzx'
swiftc -parse-as-library Tools/TapeInventory.swift -o /tmp/TapeInventory
/tmp/TapeInventory --self-test
/tmp/TapeInventory "$SABRE_WULF_TZX" > /tmp/tape-inventory.json
```

`TapeInventory` emits structural JSON only: block IDs, byte offsets/lengths, header fields, standard-block checksum results and XOR values for other data blocks. A zero XOR on a pure-data block is only a byte observation, **not** proof that its waveform obeys a ROM checksum convention. The tool does **not** save payload bytes, perform ROM loading, execute tape flow control, or modify the original file. Unsupported block IDs, truncated inputs and bad standard-block checksums fail explicitly. Do not commit the local `/tmp/tape-inventory.json` output without reviewing it.

For the recorded SHA-256 in [input-manifest.json](../reverse_engineering/input-manifest.json), independent local parsing found:

- TZX 1.10, 45,805 bytes, 204 structural blocks; IDs `0x10`, `0x12`, `0x13`, `0x14`, `0x21`, `0x22`, `0x32`.
- Five tape data blocks (two standard speed with valid XOR checksums, three pure data whose payloads also XOR to zero); the reference `speccy --verify` reports five parsed data blocks and `SABRE`.
- A BASIC `PROGRAM` header named `SABRE`: 1,562 declared program bytes, autostart line zero, variable-area offset 1,182 (not the variable-area *length*). No standard `CODE` header was found.
- Pure-tone and pulse-sequence blocks mean that recording precise loading behavior requires pulse timing. An instant loader that only handles standard/turbo CODE blocks cannot substitute for a demonstrated 48K boot here. A checksum passing is not evidence that the game ran.

The inventory tool attempts to validate the BASIC line directory without outputting source text. For this image it reports an **explicit parse error** at program offset 703 (next candidate line 40073, declared length 39040); it does not assert a BASIC line count or an entry address. Investigate whether the variable-area boundary, embedded loader data or nonstandard layout explains this before relying on line metadata.

**Next experiment:** run an isolated reference emulator with a known-hash 48K ROM, this TZX, controlled inputs and a bounded tape trace; capture the loaded RAM layout and first playable frame. A separate emulator working copy may be instrumented if no safe memory-dump/debug hook exists. Track loader/decompression transitions before declaring any memory byte to be game code. Keep the tape, ROM, RAM dumps and recovered media out of the public repository pending rights review.

The backup contains `ROMS/48.rom` (16,384 bytes; SHA-256 `d55daa439b673b0e3f5897f99ac37ecb45f974d1862b4dadb85dec34af99cb42`). A bounded CLI probe with this ROM, the supplied TZX and `--cycles 3500000` returned `TZX: 5 block(s)` and `Ran cycles: 3500000`. It did **not** provide a RAM dump, frame capture or any evidence that the tape finished loading. Do not count it as a passed boot test.

An isolated waveform/48K emulator probe consumed a full synthesized tape without a playable frame, so it is not a source-of-truth RAM dump. A shorter instruction-level trace corrected an initial misleading observation: ROM `0x0574` enters a countdown with no FE reads, but polling resumes later. The first 19-byte standard header still was not accepted (no payload in RAM and no observed IX advance), including when EAR polarity was inverted. Next isolate waveform edge semantics, ROM loader entry and keyboard/tape-start timing with a synthetic standard header before trying another full-tape run. The isolated probe and logs remain outside Git in the session's `files/reference-probe/` directory; no RAM or game bytes have been committed.
