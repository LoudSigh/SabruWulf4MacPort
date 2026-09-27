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
