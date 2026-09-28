# Private snapshot analysis workflow

**No original disassembly, raw game RAM, recovered art or music may be stored on GitHub.** Git ignores `SNAPSHOTS/`, `reverse_engineering/private/`, `reverse_engineering/generated/` and common assembly/listing formats. Check staged content explicitly before every push; a forced `git add -f` bypasses ignores. The source tools below are safe to commit because they contain no original game bytes.

The source images and ROM remain read-only. Set `SPECCY_CORE_DIR` to the `Sources/SpeccyCore` directory in the user's *local* Carbon Neural emulator backup, and `ROM` to the 16 KiB `ROMS/48.rom` from that backup. Compile the analysis tools against that backup **locally**; do not vendor its source into this repository without a license review. From the repository root:

```sh
SPECCY_CORE_DIR='/Volumes/July2025inclOct2022/Visual Studio Code Backups/Carbon Neural/2025-09-13_22-10-25/CarbonNeural_portable_2025-09-13_22-10-25/Sources/SpeccyCore'
ROM='/Volumes/July2025inclOct2022/Visual Studio Code Backups/Carbon Neural/2025-09-13_22-10-25/CarbonNeural_portable_2025-09-13_22-10-25/ROMS/48.rom'
OUT="$(mktemp -d)"
mkdir -p reverse_engineering/private
git check-ignore reverse_engineering/private/
swiftc -O -parse-as-library "$SPECCY_CORE_DIR"/*.swift reverse_engineering/tools/SnapshotTrace.swift -o "$OUT/SnapshotTrace"
"$OUT/SnapshotTrace" --self-test
"$OUT/SnapshotTrace" "$ROM" SNAPSHOTS/Snapshot_GamePlay.z80 200000 > reverse_engineering/private/gameplay-trace-200k.json
"$OUT/SnapshotTrace" "$ROM" SNAPSHOTS/Snapshot.z80 200000 > reverse_engineering/private/menu-trace-200k.json
"$OUT/SnapshotTrace" "$ROM" SNAPSHOTS/Snapshot_GamePlay.z80 200000 --key q > reverse_engineering/private/gameplay-trace-q-200k.json
```

[`SnapshotTrace.swift`](../reverse_engineering/tools/SnapshotTrace.swift) deliberately stops after a bounded number of CPU steps; its JSON contains numeric PC/call/write addresses, counts and hashes, **not** assembly or instruction bytes. An optional held key (`q`, `a`, `o`, `p`, `space`) can be compared with the no-input run, but the CPU copy still has no frame interrupts or precise port timing; this is an exploratory code-location map, **not** an authentic gameplay trace or proof of control mapping. The verified aggregate counts appear in [trace-summary.json](../reverse_engineering/analysis/trace-summary.json).

Only if you need a **private** disassembler input, export the RAM explicitly into the ignored local directory:

```sh
swiftc -O -parse-as-library "$SPECCY_CORE_DIR"/*.swift reverse_engineering/tools/SnapshotExport.swift -o "$OUT/SnapshotExport"
"$OUT/SnapshotExport" SNAPSHOTS/Snapshot_GamePlay.z80
git check-ignore reverse_engineering/private/snapshot-803e4197989c-48k.bin
"$OUT/SnapshotExport" SNAPSHOTS/Snapshot_GamePlay.z80 --screen "$ROM"
git check-ignore reverse_engineering/private/snapshot-803e4197989c-screen.png
```

The RAM export must be exactly 49,152 bytes and have SHA-256 `6de170c1b2518c82c5bfefc0f7dbfc8b8766097e020950d51b01baf045064864`. The optional `--screen` output is a 256×192 PNG for **private visual inspection only**, not a public app resource; both menu and gameplay screens were tested. `SnapshotExport` refuses to run outside a repository root containing the private-directory ignore rule. It never writes into tracked paths. On this Mac `z80dasm` 1.2.0 is available as a *separate command-line tool*; for example, a local-only exploratory pass over `9000-BFFF` can be made with:

```sh
umask 077
dd if=reverse_engineering/private/snapshot-803e4197989c-48k.bin of=reverse_engineering/private/gameplay-9000-bfff.bin bs=4096 skip=5 count=3
z80dasm -a -l -g 0x9000 -o reverse_engineering/private/gameplay-9000-bfff-unverified.dis reverse_engineering/private/gameplay-9000-bfff.bin
git check-ignore reverse_engineering/private/gameplay-9000-bfff-unverified.dis
```

This **blind pass also interprets data as instructions**. Its labels and any self-modifying-code warnings are not proof of actual code or behavior. Confirm routines against the executed-PC trace, RAM writes and future controlled input captures before naming them. Neither private listing nor raw exported RAM belongs in a commit or pull request; public analysis should contain only derived hashes, numeric metadata and independently worded findings.

The current local analysis exported the complete 49,152-byte RAM image into `reverse_engineering/private/` and produced two **private, unverified** passes: a `6000-FFFF` listing (33,343 lines) and a focused `9000-BFFF` listing (8,654 lines). Both remain ignored, and neither is being treated as proof that every byte is an instruction. A candidate ULA pulse/delay segment observed around the menu snapshot PC is described only at a high level in [functions.json](../reverse_engineering/analysis/functions.json), not reproduced as assembly.

For a source-free sprite *pointer index* (not sprite images or frame data), compile and run:

```sh
swiftc -O -parse-as-library "$SPECCY_CORE_DIR"/*.swift reverse_engineering/tools/SnapshotSpriteIndex.swift -o "$OUT/SnapshotSpriteIndex"
"$OUT/SnapshotSpriteIndex" --self-test
"$OUT/SnapshotSpriteIndex" SNAPSHOTS/Snapshot.z80 SNAPSHOTS/Snapshot_GamePlay.z80
"$OUT/SnapshotSpriteIndex" SNAPSHOTS/Snapshot.z80 SNAPSHOTS/Snapshot_GamePlay.z80 --private-atlas \
  > reverse_engineering/private/sprite-index-report.json
git check-ignore reverse_engineering/private/snapshot-803e4197989c-sprite-atlas-v1.json
```

The numeric result is summarized in [sprite-index.json](../reverse_engineering/analysis/sprite-index.json). Without `--private-atlas`, the tool emits no original bytes. With the flag, it checks both captures agree before writing the 196-pointer table and 153 bounded records **only** to the ignored private JSON file. One 0×0 record is an explicit empty sentinel reused by 14 IDs; the other 152 records contain bitmap shapes. Never stage or distribute the atlas. Its raw bitmap format was verified for two examples; palette, compositor and animation remain unverified.

## Private, bounded input comparison

`SnapshotReplay.swift` schedules one keyboard key at frame index 20 and releases it at index 40, with a 48K IM1 boundary at 69,888 cycles. It reads the FE keyboard matrix on **every** I/O read rather than relying on a frozen emulator time counter. It records numeric instruction/read/write counts and frame hashes, no screen pixels or original code:

```sh
swiftc -O -parse-as-library "$SPECCY_CORE_DIR"/*.swift reverse_engineering/tools/SnapshotReplay.swift -o "$OUT/SnapshotReplay"
"$OUT/SnapshotReplay" --self-test
"$OUT/SnapshotReplay" "$ROM" SNAPSHOTS/Snapshot_GamePlay.z80 none 100 > reverse_engineering/private/replay-none-100.json
"$OUT/SnapshotReplay" "$ROM" SNAPSHOTS/Snapshot_GamePlay.z80 q 100 > reverse_engineering/private/replay-q-100.json
"$OUT/SnapshotReplay" "$ROM" SNAPSHOTS/Snapshot_GamePlay.z80 w 150 --hold > reverse_engineering/private/replay-w-150-hold.json
```

Valid keys: `q`, `w`, `e`, `r`, `t`, `a`, `o`, `p`, `space`; `none` is the comparison baseline. `--hold` keeps the chosen key down beyond frame index 40. A second Q run matched the first's output byte-for-byte. The linked SkoolKit handler and a private snapshot check confirm Q/W/E/R/T as the selected keyboard row; controlled Q/W/E/R/T inputs each altered frame hashes. During one T run the documented PlayerMovement entry was observed with IX `0x9702`; the tool tracks that entity's room and X/Y bytes at every frame, distinct from the transient saved-actor buffer. The [public summary](../reverse_engineering/analysis/reference-replay.json) contains only numeric checkpoints and hashes. This is **not** a cycle-accurate emulator: peripheral I/O beyond the keyboard, ULA contention, tape and audio are incomplete. Do not infer exact combat, collision masks or all room transitions from one starting position. Compare visually and with the user's working emulator before promoting outcomes to faithful core tests.

For bounded multi-key schedules, use a source-free JSON file containing sorted, nonoverlapping zero-based `{ "key", "startFrame", "endFrame" }` intervals. The [north-exit](../reverse_engineering/analysis/upper-exit-schedule.json), [round-trip](../reverse_engineering/analysis/round-trip-schedule.json) and [provisional west-exit](../reverse_engineering/analysis/west-exit-schedule.json) schedules are examples. Results are private:

```sh
"$OUT/SnapshotReplay" "$ROM" SNAPSHOTS/Snapshot_GamePlay.z80 --schedule \
  reverse_engineering/analysis/west-exit-schedule.json 256 \
  > reverse_engineering/private/replay-west-exit-256.json
swiftc -O -parse-as-library "$SPECCY_CORE_DIR"/*.swift \
  reverse_engineering/tools/SnapshotDivergence.swift -o "$OUT/SnapshotDivergence"
"$OUT/SnapshotDivergence" --self-test
"$OUT/SnapshotDivergence" "$ROM" SNAPSHOTS/Snapshot_GamePlay.z80 \
  reverse_engineering/analysis/west-exit-schedule.json 256 \
  > reverse_engineering/private/west-divergence.json
"$OUT/SnapshotDivergence" "$ROM" SNAPSHOTS/Snapshot_GamePlay.z80 \
  reverse_engineering/analysis/west-exit-schedule.json 256 --trace \
  > reverse_engineering/private/west-entity-trace-v2.json
"$OUT/SnapshotDivergence" "$ROM" SNAPSHOTS/Snapshot_GamePlay.z80 \
  reverse_engineering/analysis/west-exit-schedule.json 256 \
  --trace --reference-timing --require-ram-parity \
  > reverse_engineering/private/west-entity-reference.json
"$OUT/SnapshotReplay" "$ROM" SNAPSHOTS/Snapshot_GamePlay.z80 --schedule \
  reverse_engineering/analysis/west-exit-schedule.json 256 --reference-timing \
  > reverse_engineering/private/replay-west-reference-256.json
swiftc -O -parse-as-library "$SPECCY_CORE_DIR"/*.swift \
  reverse_engineering/tools/VerifyReferenceReplay.swift -o "$OUT/VerifyReferenceReplay"
"$OUT/VerifyReferenceReplay" "$ROM" SNAPSHOTS/Snapshot_GamePlay.z80 \
  reverse_engineering/private/replay-west-reference-256.json
jq '{firstRNGDifference,firstMovingEntityDifference,firstPlayerStateDifference,firstPlayerPositionDifference}' \
  reverse_engineering/private/west-divergence.json
```

The divergence tool compares fresh-FE CPU stepping with the unmodified emulator's `stepFrame()` under the same inputs; it emits hashes and selected numeric state, not RAM or instructions. With the original **absolute** frame boundaries, the first RNG, moving-entity, player-state and position differences are frames 101, 102, 163 and 183. The unmodified emulator's `stepFrame()` instead advances 69,888 cycles **from its current cycle count per call**, retaining overshoot between frames. `--reference-timing` matches that boundary and reproduces **256/256 RAM frames** for the west schedule, **200/200** for the round trip and **180/180** for the north exit. `--require-ram-parity` exits nonzero if even one RAM frame differs. `VerifyReferenceReplay` additionally verifies the **actual JSON replay's 256 individual RAM and screen hashes** against the unmodified emulator; it rejects corrupted hashes and legacy absolute-timing reports. The legacy replay output is unchanged unless the new flag is supplied. The old RNG/enemy split was due to frame timing, **not** a keyboard or missing player-action rule. Neither mode establishes tape-boot equivalence or full native enemy simulation. Never publish private replays or original game bytes.
The optional `--trace` records numeric positions for one moving-entity slot and both player positions per frame. Import `replay-west-exit-256.json` with `west-entity-trace-v2.json` to examine the old timing drift; import `replay-west-reference-256.json` with `west-entity-reference.json` to examine aligned positions. The app rejects frame-count, timing-mode and player-path mismatches. Both pairs remain ignored local data and do not simulate enemies.
