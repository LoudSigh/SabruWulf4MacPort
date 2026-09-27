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

Two read-only snapshot candidates also exist in this backup: `ROMS/z80 files/Sabre Wulf (1984)(Ultimate Play The Game).z80` (39,457 bytes; CLI reports 48K hardware and PC `0x1F3E`) and `Test Files/Sabre Wulf (1984)(Ultimate Play The Game).sna` (49,179 bytes, a 48K-sized snapshot). Their SHA-256 values are recorded in [input-manifest.json](../reverse_engineering/input-manifest.json). Matching filenames do not prove a playable state or that the RAM corresponds to the supplied tape; validate both independently before using them for reverse engineering.

Isolated snapshot restoration confirmed both are 48K images, **not playable reference states**. The `.z80` has a nonblank screen, 6,895 of 6,912 screen bytes matching the TZX screen block, and starts in ROM at PC `0x1F3E`; after 50 frames it remains in ROM with unchanged screen. This is strong evidence of a matching title/loading image, not of a game run. The `.sna` starts at PC `0x0000` with a blank screen and stays blank. Their RAM images differ; neither yields game-state traces or a justified disassembly entry point. Only hashes and metrics, not source bytes or images, were retained in the isolated probe.

An isolated waveform/48K emulator probe consumed a full synthesized tape without a playable frame, so it is not a source-of-truth RAM dump. A shorter instruction-level trace corrected an initial misleading observation: ROM `0x0574` enters a countdown with no FE reads, but polling resumes later. The first 19-byte standard header still was not accepted (no payload in RAM and no observed IX advance), including when EAR polarity was inverted. Next isolate waveform edge semantics, ROM loader entry and keyboard/tape-start timing with a synthetic standard header before trying another full-tape run. The isolated probe and logs remain outside Git in the session's `files/reference-probe/` directory; no RAM or game bytes have been committed.

## Additional user-provided references

The user reattached `Test Files/Sabre Wulf (1984)(Ultimate Play The Game).sna`; its size (49,179 bytes) and SHA-256 (`dcc35fc21803f25cf097d05b7bde7d9d5d8453e53c6fd1c04d89382417dc8897`) are **identical** to the previously inspected blank snapshot. It does not unblock a playable reference capture.

The newly tagged workspace `SNAPSHOTS/Sabre Wulf (1984)(Ultimate Play The Game).sna` was byte-compared to that backup snapshot (`cmp` exit 0), then independently restored through the existing 48K `SNASnapshot`/`Speccy48Emulator` APIs with the recorded ROM. At frames 0, 1, 10 and 50 it had no nonzero bitmap bytes, the same screen hash `71c642b31e5890a15ef92f3cbeba34edfb6e2e9f63079ecbda13a89d426f7d8b`, and no playable frame. Its saved PC is `0x0000`, obtained from the SNA stack by the parser, and the emulator's PC remains in ROM at frame 50. This does **not** dispute that another emulator or different capture may run the game; it establishes only that these exact bytes do not provide a self-contained playable baseline under the tested restore. To investigate the user's observation, capture the emulator/model/ROM, any post-load input or tape continuation, and a snapshot saved while gameplay is visibly active; compare its SHA-256 to the manifest.

The workspace also contains a short `Sabre Wulf (Europe).mp4` clip with an observable Spectrum-style playfield; it is a **visual reference only**, not proof of equivalence to this TZX or a substitute for RAM/state traces. A separately named `(En,Fr,De)` video depicts a visually different later edition and must not be mixed into the 48K reconstruction. All clips and images remain untracked under the ignored `SNAPSHOTS/` directory.

The converted `Ultimate Sabre Wulf.md` is unreferenced secondary commentary: it explicitly says the loader description is synthesized without cited sources. It suggests testing a custom EAR pulse reader after a ROM-compatible stub, but claims a small CODE bootstrap, no loading-screen block and uniformly black screen. This particular TZX instead has a 1,562-byte BASIC program header, a 6,913-byte pure-data block closely matching a nonblank screen snapshot, and no CODE header. Treat the claims about pulse thresholds, decryption, self-modification and timing as **hypotheses to test against measured loader execution**, not authoritative facts or license to invent game behavior. First diagnose why the standard header is not accepted; only then trace the BASIC bootstrap and subsequent pure-data blocks.

The 913-byte `AY Music/ProjectAY/Spectrum/Games/SabreWulf.ay` begins with the `ZXAYEMUL` signature. Its filename and macOS `file` identification as a Spectrum 128 tune do not show that the original 48K game played it. `Sources/Chiptune/AYChiptuneEngine.swift` in the emulator backup contains a ZXAYEMUL parser/Z80 playback implementation; inspect licenses and test this exact file before reusing any implementation. If supported, offer the AY music as a clearly labeled optional, user-supplied **modern soundtrack**, not as a recovered 48K sound effect; never bundle it while rights remain unverified.

## User-captured menu snapshot (new baseline)

`SNAPSHOTS/Snapshot.z80` is **not** the earlier blank snapshot: 41,293 bytes, SHA-256 `34d98ec3dc55d60755a7d9ceebe45c3a7e345ce5961692d25d2d6718bcdc20ea`. The existing emulator parser reports 48K hardware, and an independent restore with the recorded ROM yields PC `0xBDAF` in RAM, SP `0x5FF8`, 3,135 nonzero screen bitmap bytes and a recognizable 256×192 *Sabre Wulf* main menu. Its unmodified 48K RAM hash and menu screen hash are recorded in [menu-reference.json](../reverse_engineering/analysis/menu-reference.json). The rendered menu offers one/two-player selection, keyboard/joystick control options and `0` to start. **This is a verified static menu/loaded-RAM reference**, so static program and graphics investigation no longer requires getting the tape to load first; do not claim the snapshot's RAM corresponds byte-for-byte to the supplied TZX without additional evidence.

After applying the snapshot, the tested emulator reached 150 frames with no screen-RAM change and no unimplemented opcode. Separate short presses of Space, Enter, 1, 0 and S did not advance the menu; for the 0 key at frames 5–9, FE read counters were zero on the sampled frames. This identifies an **emulator-input or snapshot-resume validation gap**, not proof that the source game ignores those keys. Compare against the user's working emulator and capture the first *gameplay* snapshot plus exact controls. Keep rendered frames, snapshot RAM and extracted artwork local pending redistribution clearance.

## In-game snapshot (second verified state)

The user supplied `SNAPSHOTS/Snapshot_GamePlay.z80`, captured with one player and keyboard selected. SHA-256 `803e4197989c73408cfc5113f8f30c81ac0269958aa9e105b474b6f52437203c` and 43,308 bytes distinguish it from the menu and earlier blank snapshots. Restored as 48K with the same ROM, it starts at PC `0xB8A1` and renders an in-game jungle view with score/status and a player figure. Its full 48K RAM SHA-256 is `6de170c1b2518c82c5bfefc0f7dbfc8b8766097e020950d51b01baf045064864`. The two source states differ at 4,558 byte positions: 3,159 display bitmap, 445 color attributes, 44 system-area and 910 elsewhere. See [gameplay-reference.json](../reverse_engineering/analysis/gameplay-reference.json) and [memory-map.md](../reverse_engineering/analysis/memory-map.md). The differences enable comparative static investigation, not a proof of specific rules or program-data boundaries.

In the backup emulator, execution resumed in ROM by frame 1; the in-game display remained unchanged through frame 50. Short isolated key presses of likely controls produced divergent later RAM hashes, but because the CPU had left the game, these are **not** accepted as game movement/action traces. The user's capture verifies a real static in-game screen and RAM, while repeatable running gameplay remains a separate validation step. The screenshot/ROM/snapshot bytes were inspected privately, never added to Git.

A diagnostic replay with maskable interrupts initially disabled still entered ROM, so simply masking interrupts does not recover the gameplay loop. Do not derive combat or movement timing from either replay.

### Repeat the private, metadata-only RAM comparison

The repository's `reverse_engineering/tools/SnapshotCompare.swift` compiles **against the read-only emulator backup's SpeccyCore sources**, without copying them into this repository. It accepts a 16 KiB ROM and two 48K `.z80` images, fails explicitly for unsupported images, and prints SHA-256 hashes, screen statistics and changed-byte counts—never snapshot bytes:

```sh
SPECCY_CORE_DIR='/Volumes/July2025inclOct2022/Visual Studio Code Backups/Carbon Neural/2025-09-13_22-10-25/CarbonNeural_portable_2025-09-13_22-10-25/Sources/SpeccyCore'
ROM='/Volumes/July2025inclOct2022/Visual Studio Code Backups/Carbon Neural/2025-09-13_22-10-25/CarbonNeural_portable_2025-09-13_22-10-25/ROMS/48.rom'
OUT="$(mktemp -d)"
swiftc -O -parse-as-library "$SPECCY_CORE_DIR"/*.swift reverse_engineering/tools/SnapshotCompare.swift -o "$OUT/SnapshotCompare"
"$OUT/SnapshotCompare" --self-test
"$OUT/SnapshotCompare" "$ROM" SNAPSHOTS/Snapshot.z80 SNAPSHOTS/Snapshot_GamePlay.z80
```

Keep generated local binaries and any later raw RAM dumps out of Git. The tool uses the backup's snapshot parser for **private analysis only**; its license must be reviewed before incorporating emulator code in a distributed app.
