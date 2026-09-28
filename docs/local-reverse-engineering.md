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

After local atlas extraction, check the player's screen placement across five independent 100-frame source replays:

```sh
swiftc -O -parse-as-library "$SPECCY_CORE_DIR"/*.swift Sources/GameCore/*.swift \
  reverse_engineering/tools/VerifyActorScreen.swift -o "$OUT/VerifyActorScreen"
for key in q w e r t; do
  "$OUT/VerifyActorScreen" "$ROM" SNAPSHOTS/Snapshot_GamePlay.z80 \
    reverse_engineering/private/snapshot-803e4197989c-sprite-atlas-v1.json \
    "$key" > "reverse_engineering/private/actor-screen-$key.json"
done
```

The verifier reads the unmodified emulator screen and compares every projected player-mask pixel, including blank pixels. Source X is the mask's left edge; source Y is its **bottom**, and bitmap record rows are reversed for top-down display. [Source-free counts](../reverse_engineering/analysis/actor-screen.json) show **489/500 exact frame rectangles** and **173,348/173,472 agreeing pixels**: Q/E/R/T match all 100 frames each, while W has 124 white/off mismatches during frames 43–53. A private follow-up finds 64 bitmap-bit discrepancies: 48 also disagree in white/off color, 16 do not; 76 further mismatches have the expected bitmap bit but different color. Whether overlap, redraw phase or attribute changes caused them remains unresolved. The native viewer offers a hideable, locally imported white actor silhouette with this placement, **not** verified sprite-overlap rules or an attack simulation. No original sprite or screen pixels enter the report or Git.

The room exporter has a similar local output:

```sh
swiftc -O -parse-as-library "$SPECCY_CORE_DIR"/*.swift \
  reverse_engineering/tools/SnapshotRoomIndex.swift -o "$OUT/SnapshotRoomIndex"
"$OUT/SnapshotRoomIndex" SNAPSHOTS/Snapshot.z80 SNAPSHOTS/Snapshot_GamePlay.z80 --private-map \
  > reverse_engineering/private/room-index-report.json
git check-ignore reverse_engineering/private/snapshot-803e4197989c-background-atlas-v1.json
```

This additionally checks the bitmap and attribute headers of all 41 background records, matches the complete records across snapshots, and writes their bytes **only** under the ignored private directory. The native app validates the aggregate hash and placement dimensions before drawing 1-bit room geometry. [background-index.json](../reverse_engineering/analysis/background-index.json) contains numeric evidence, not graphics or instruction bytes.

For an exact, bounded screen check of the captured room after extracting both private atlases:

```sh
swiftc -O -parse-as-library "$SPECCY_CORE_DIR"/*.swift Sources/GameCore/*.swift \
  reverse_engineering/tools/VerifyBackgroundScreen.swift -o "$OUT/VerifyBackgroundScreen"
"$OUT/VerifyBackgroundScreen" "$ROM" SNAPSHOTS/Snapshot_GamePlay.z80 \
  reverse_engineering/private/snapshot-803e4197989c-world-v2.json \
  reverse_engineering/private/snapshot-803e4197989c-background-atlas-v1.json \
  > reverse_engineering/private/background-pixel-parity.json
```

The tool fails unless the bitmap-bit inversion and source-direct X/Y reproduce **29,056/29,056 covered RGB pixels** in room 168 of the unmodified snapshot. The remaining 20,096 screen pixels are **uncovered**, not claimed as correct. It prints only numeric evidence and never writes a screenshot or source pixels outside the ignored private directory. To compare later reference-timed frames in other rooms, pass a sorted, nonoverlapping source-free keyboard schedule and frame count:

```sh
"$OUT/VerifyBackgroundScreen" "$ROM" SNAPSHOTS/Snapshot_GamePlay.z80 \
  reverse_engineering/private/snapshot-803e4197989c-world-v2.json \
  reverse_engineering/private/snapshot-803e4197989c-background-atlas-v1.json \
  --schedule reverse_engineering/analysis/upper-exit-schedule.json 180 \
  > reverse_engineering/private/background-north-parity.json
"$OUT/VerifyBackgroundScreen" "$ROM" SNAPSHOTS/Snapshot_GamePlay.z80 \
  reverse_engineering/private/snapshot-803e4197989c-world-v2.json \
  reverse_engineering/private/snapshot-803e4197989c-background-atlas-v1.json \
  --schedule reverse_engineering/analysis/west-early-schedule.json 260 \
  > reverse_engineering/private/background-west-parity.json
```

The north exit matches **28,544/28,544** covered pixels in room 152 (template 6); the earlier west exit matches **30,720/30,720** in room 151 (template 14), with **260/260 RAM frames** also matching the backup emulator. The verifier now calls shared `GameCore.BackgroundScene`, which also produces the native viewer's locally cached, transparent 256×192 color images. The launcher repeats all three checks locally. Their uncovered areas, native display scaling, dynamic sprites and other room templates remain unverified.

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
swiftc -O -parse-as-library "$SPECCY_CORE_DIR"/*.swift Sources/GameCore/*.swift \
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

For a bounded, **non-disassembly** executed-PC inventory, append `--coverage` to `SnapshotDivergence --reference-timing --require-ram-parity` and save each output **only** under ignored `reverse_engineering/private/`. Repeat for no-T/A/T (800 frames) and straight Q/W/E/R and mixed W→E post-setup schedules (900 frames). Build the [union checker](../reverse_engineering/tools/CoverageUnion.swift) with `swiftc -parse-as-library Sources/GameCore/*.swift reverse_engineering/tools/CoverageUnion.swift -o "$OUT/CoverageUnion"`; pass the public `byte-coverage.json`, the ignored private sprite atlas, then all eight private coverage JSON paths. It checks selected interpreter/snapshot hashes, per-run sorted address hashes and page counts, source RAM-frame parity, and rejects any executed PC start inside known world/graphics/sprite records. The [source-free summary](../reverse_engineering/analysis/executed-pc-coverage.json) records **6,900/6,900 reference RAM frames**, **2,589 distinct executed RAM PC starts**, their hash, and **zero known-data overlaps**. The private JSON contains numeric addresses, not opcodes; an executed PC is **not** an entire instruction, and the captured RAM may change before execution. Do not mark the 19,974 remaining unknown snapshot bytes as code or publish preliminary disassembly.

`--require-contact-parity` additionally checks the pure shared `CapturedActorContact` predicate against the source routine's carry result for every call it reaches. It requires both `--reference-timing` and `--require-ram-parity`, and writes its numeric JSON only to ignored private storage:

```sh
for spec in 'no-fire-encounter 190' 'fire-before-contact 190' \
            'unrelated-a-control 190' 'upper-exit 180' \
            'round-trip 200' 'west-exit 256'; do
  set -- $spec
  "$OUT/SnapshotDivergence" "$ROM" SNAPSHOTS/Snapshot_GamePlay.z80 \
    "reverse_engineering/analysis/$1-schedule.json" "$2" \
    --reference-timing --require-ram-parity --require-contact-parity \
    > "reverse_engineering/private/contact-check-$1.json"
done
```

The [source-free contact summary](../reverse_engineering/analysis/reference-contact.json) has **3,881/3,881 matching routine returns** and **1,206/1,206 matching complete RAM frames** across six paths. The no-T and west paths produce a positive slot-12 contact at frame 162; unrelated A at frame 169; T produces no positive contact through frame 190. These are earlier than the observed damage-state changes, **not** proof that a simple overlap immediately changes health. The predicate takes the source caller's two radii as inputs, has an asymmetric X bound for player kinds 16–31 versus 32–47, and leaves the meaning of player byte 5 otherwise unclassified. Do not apply damage, score or combat outcomes in the native core based solely on this geometry.

The independent slot-12 [entity-motion rule](../Sources/GameCore/CapturedEntityMotion.swift) checks one movement **when a source entity update is supplied**. With the privately imported room-152 world, the no-T/A/T 190-frame traces select signed horizontal velocities +96/+48/−48 and vertical +80 in sixteenth-pixel units. The source first moves from (92,130) to (98,135), (95,135) or (89,135); subsequent vertical candidates stop at Y=135 against measured room backgrounds. An extended 250-frame T trace includes a second choice of X=−80 and three more matching updates. Private tests now match **2+4+8+3=17/17** changed X/Y events against [numeric-only evidence](../reverse_engineering/analysis/reference-entity-motion.json). Run `SABRE_PRIVATE_WORLD=<private-world-v2.json> SABRE_PRIVATE_ENTITY_TRACE_DIR=<ignored-private-dir> SABRE_PRIVATE_FIRE_EXTENDED_TRACE=<private-trace-250.json> SABRE_PRIVATE_FIRE_EXTENDED_REPLAY=<private-replay-250.json> swift test --filter CapturedEntityMotionTests` after the launcher creates the verified pairs.
The [direction chooser](../Sources/GameCore/CapturedEnemyDirection.swift) translates the low three bits of the supplied RNG and clock bytes to eight signed velocities: indexes 0–3 use −96 + 16×index, indexes 4–7 use 48 + 16×(index−4). The selected horizontal velocity's **sign** determines enemy-kind bit 1. `SABRE_PRIVATE_MENU_RAM=<ignored-menu-48k.bin> SABRE_PRIVATE_GAME_RAM=<ignored-game-48k.bin> swift test --filter CapturedEnemyDirectionTests` checks the derived rule against matching small bounded data regions in both SHA-checked captures without committing them. `SnapshotDivergence --reference-timing --require-ram-parity --require-enemy-direction-parity` checks **four actual slot-12 decisions** in the three pre-contact schedules plus the 250-frame T extension; [numeric evidence](../reverse_engineering/analysis/reference-enemy-direction.json) includes inputs and outcomes, not original bytes. This chooses from externally supplied values; it does **not** synthesize the Z80 refresh-register RNG, schedule enemy updates or cause native contact/damage.
The two [RNG write-site rules](../Sources/GameCore/CapturedRNGStep.swift) have a separate opt-in `SnapshotDivergence --reference-timing --require-ram-parity --require-rng-step-parity` gate. The frequent site adds the **supplied** refresh-register operand and carry to the prior byte, modulo 256. The other adds a **supplied** low counter byte and clock byte to the prior RNG byte. Three 190-frame paths and one 250-frame T path compare **8,740/8,740** executed writes and **820/820** complete RAM frames; the launcher checks the ignored private reports with `SABRE_PRIVATE_ENTITY_TRACE_DIR=<ignored-private-dir> swift test --filter CapturedRNGStepTests`. Only [numeric totals](../reverse_engineering/analysis/reference-rng-step.json), not the original routine or RAM, are published. Neither native refresh/operand production nor the execution-path-dependent call cadence has been implemented.
The [active-enemy state](../Sources/GameCore/CapturedActiveEnemyState.swift) additionally models kind-bit toggles and timer decrements for the bounded moving slot-12 entity. A timer decrement can land in the display frame **before** the corresponding position/kind change; `advanceCountdownOnSourceUpdate()` and `advanceOnSourceUpdate(world:countdownOccurred:)` therefore accept separately observed events. The opt-in `SnapshotDivergence --reference-timing --require-ram-parity --require-entity-phase-parity` reads `SABRE_PRIVATE_WORLD=<ignored-world-v2.json>`, compares the resulting kind/timer/position to source, rejects mismatches and emits a private report. The launcher checks three 190-frame paths (8+2+4 moving updates and 1+0+2 countdown-only frames); `SABRE_PRIVATE_ENTITY_TRACE_DIR=<ignored-private-dir> swift test --filter CapturedActiveEnemyStateTests` asserts exact counts and frame indices. Only [numeric evidence](../reverse_engineering/analysis/reference-active-enemy-state.json) is public. This does **not** generate source events, handle timer expiry, schedule enemies, or apply contact damage.
For finer timing, `SnapshotDivergence --reference-timing --require-ram-parity --watch-entity-state` writes numeric slot-12 byte changes, instruction-start addresses and emulator cycles **only to ignored private reports**. In these three paths, the countdown write and kind toggle occur at distinct source instruction sites, sometimes separated by a frame boundary; the private test asserts ordering and a bounded cycle gap. PC starts alone do not reveal complete instructions or a general actor-update scheduler. Keep the write traces out of Git.
The T path counts down 1→0 at frame 184, clears velocity and reseeds the timer to 13 in that display frame, then has two further timer writes before frame 190. A second timer expiry at frame 220 instead chooses a new X velocity of −80 and Y +80, leaves the timer at zero and next decrements it to 255 at frame 224. Private source-branch inspection establishes that the decision tests whether **either** prior velocity byte is nonzero: movement clears both velocity bytes and reseeds to `(rng & 7) | 8`, whereas rest selects a new direction from supplied RNG/clock. The bounded [expiry helper](../Sources/GameCore/CapturedEnemyExpiry.swift) matches **2/2 source routine returns** with 250/250 full RAM frames using `SnapshotDivergence --reference-timing --require-ram-parity --require-enemy-expiry-parity`. Its private report is checked by `SABRE_PRIVATE_ENEMY_EXPIRY_REPORT=<ignored-report.json> swift test --filter CapturedEnemyExpiryTests`; no code bytes or detailed trace are committed. `CapturedActiveEnemyState` still rejects timer 1; this decision helper does not schedule expiries, generate randomness, or model subsequent timer wraparound and combat.

To observe the longer injury/life sequence without inventing a health rule, run the same three pre-contact schedules for **600** frames with `SnapshotReplay --reference-timing --actor-kind`, then check each private replay with `VerifyReferenceReplay`; run `SnapshotDivergence` for 600 frames with the three parity flags above. [Numeric-only extended evidence](../reverse_engineering/analysis/reference-damage.json) confirms **600/600 complete RAM and screen hashes** per run and **4,477/4,477 contact returns** across those three overlapping paths. The first contact precedes kind 64 by one or two frames; kind 65 then lasts **66 frames** before the life byte at 38589 falls from 1 to 0. T avoids contact through frame 190 but is contacted at frame 228 and also loses that life byte at frame 297. All paths experience another contact later; their following actor kinds differ. Do not turn **display-frame counts** into an injury timer, invulnerability or ending implementation without recovering the causal source transitions.
The first kind-65 countdown is now a **separate source-actor-update rule** in `CapturedFirstInjuryTick`. To verify it, add `--require-first-injury-parity` to the 600-frame `SnapshotDivergence --reference-timing --require-ram-parity --require-contact-parity` command for each schedule, keeping outputs private. It matches **189/189 timer/kind/life-byte transitions** (63 in each run): timer 63 counts down per **source actor update**, not per display frame; the last update at timer 1 yields kind 17, timer 0 and life byte 0. It intentionally rejects any other starting kind, timer, life byte or final zero-life/game-over state. The one- or two-frame kind-64 lead-in and the source update cadence still need their own verified native model, so this does **not** make injury playable in the native preview.

To verify the visible return to the menu without publishing the original screen, replay each of the three schedules for **800** reference-relative frames with `SnapshotReplay --actor-kind` and use `VerifyReferenceReplay --menu SNAPSHOTS/Snapshot.z80 <expected-first-frame>`. The expected frames are **503** (no T), **510** (A control), and **679** (T). The optional menu check fails unless every one of 2,560 RGB pixels in the center title/menu-text region (X=48–207, Y=72–87) agrees with the separately captured 48K menu snapshot for the **first** time at the expected frame; it still verifies all **800/800** individual RAM and screen hashes per run. `SnapshotDivergence` with `--reference-timing --require-ram-parity --require-contact-parity --require-first-injury-parity --require-menu-sequence` additionally confirms **4,477/4,477** contact returns and **189/189** first-injury updates across the three longer runs. Source menu setup occurs **68 frames after the second contact**, its return routine **199 frames after**, and the first exact text **205 frames after** in all three. The [public menu-return evidence](../reverse_engineering/analysis/reference-menu-return.json) contains only numeric counts/hashes. These offsets do not prove a general frame timer: this does not certify the entire menu screen, selection/start behavior, a generalized game-over state machine or tape boot.

The published, source-free [restart schedule](../reverse_engineering/analysis/restart-after-menu-schedule.json) extends the no-T path with `0` held during zero-based frames 530–534. Replay it for 800 frames with `SnapshotReplay --reference-timing --actor-kind`, then use `VerifyReferenceReplay --menu SNAPSHOTS/Snapshot.z80 503` and all five `SnapshotDivergence` parity/sequence options above. Use `VerifyBackgroundScreen --schedule reverse_engineering/analysis/restart-after-menu-schedule.json 664` with the private world/atlas to require **29,056/29,056** covered RGB pixels in returned room 168. The screen at frame 663 matches only **27,318/29,056** covered pixels: source redraw is not instantaneous when the actor bytes reset. [Numeric restart evidence](../reverse_engineering/analysis/reference-restart.json) includes the stable new actor at X=120/Y=112 and source life byte 4 from frame 660; a one-frame press misses the menu poll, while 5/10/20-frame holds yield identical 800-frame RAM hashes on this captured path. This is a reproducible **observation**, not native gameplay initialization or a tape-boot proof.
The [keyboard-and-start schedule](../reverse_engineering/analysis/restart-keyboard-movement-schedule.json) adds menu `3` (frames 515–524), `0` (530–539) and held `W` (680–799). It verifies **800/800** independent RAM/screen hashes, **2,309/2,309** contact returns and **29,056/29,056** covered static pixels in room 168 at frame 800; source actor X first changes at frame **789**, reaching X=148 at frame 800. A control without menu `3` but the same long W hold first changes X at 793 and reaches X=136. The 3 key also changes the earlier menu polling phase, so that four-frame shift **does not prove a distinct controller mapping**. Short W holds at frames 680–719 change RAM but not actor X/kind before frame 800: the new-game action cadence and original palette/animation layer are not yet modeled. [Numeric keyboard restart evidence](../reverse_engineering/analysis/reference-restart-keyboard.json) is source-free; private replay JSONs remain ignored.
For the **separately checked, playable post-setup slices**, the source-free [late-W schedule](../reverse_engineering/analysis/restart-ready-movement-schedule.json) and [Q](../reverse_engineering/analysis/restart-ready-q-schedule.json), [E](../reverse_engineering/analysis/restart-ready-e-schedule.json), [R](../reverse_engineering/analysis/restart-ready-r-schedule.json) alternatives press a direction at frame index 788 and release at 850. All four 900-frame reference-relative paths reproduce every RAM/screen hash and **10,648/10,648** source contact returns in total. Initialize `CapturedMovementState(world: world, origin: .observedNewGameReady)` at source frame 790 and keep **one** Q/W/E direction for frames 791–850, then None through 900; each matches **110/110 room/X/Y and numeric player bitmap-ID frames**. E exits north at frame 819 and rebases to Y=191 at 825 (one frame earlier than the original mid-game crossing); its sprite phase also shifts at redraw. The R route agrees on both position and bitmap ID for **76/76** through frame 866; at 867 static-only native would move to Y=135 while the source remains at 134. Its cause is unclassified, so native R pauses before that step. The native viewer's locally imported pink player silhouette uses these IDs, but colors, occlusion and other sprites remain unverified. These slices do not simulate 790 preceding frames, **arbitrary** mixed inputs, enemies or an unbounded world. [Numeric evidence](../reverse_engineering/analysis/reference-new-game-movement.json) contains no private replay data.
One additional [W→E schedule](../reverse_engineering/analysis/restart-ready-w-e-schedule.json) switches from W to E at zero-based frame 808, releases at 850, and then idles through 900. The full 900-frame source RAM/screen, **2,661/2,661** contact results and **29,056/29,056** covered room pixels match the reference. Native static movement also matches **110/110 room/X/Y** frames, with X=208/Y=86 at 900. Numeric bitmap ID matches **76/76** frames through 866; after release, source changes kind at 867 while the native color/phase rule is unproven, so the measured bitmap ID becomes unavailable and the pink position marker continues. This is *one* allowable mixed schedule, not permission to accept arbitrary direction switches. See the source-free [mixed observation](../reverse_engineering/analysis/reference-new-game-mixed.json).
The optional `--trace` records numeric positions for one moving-entity slot and both player positions per frame. Import `replay-west-exit-256.json` with `west-entity-trace-v2.json` to examine the old timing drift; import `replay-west-reference-256.json` with `west-entity-reference.json` to examine aligned positions. The app rejects frame-count, timing-mode and player-path mismatches. Both pairs remain ignored local data and do not simulate enemies.

For a bounded, source-only actor-state/RNG comparison, add `--watch-actor-state` alongside `--reference-timing --require-ram-parity` for each of the three [pre-contact schedules](../reverse_engineering/analysis/reference-fire-encounter.json), writing the JSON reports **only under `reverse_engineering/private/`**. The diagnostic records changed player and slot-12 kind bytes with the executing instruction address, previous/new numeric value and RNG at that write; it also reports each frame's RNG and the numeric addresses and values of changed RNG writes. It never exports the instruction bytes, disassembly, graphics or complete RAM. The three verified paths first diverge in RNG at frame 146 (T) and frame 147 (A) relative to no fire. A private source check shows the frequent RNG update at `0x99D7` mixes in the Z80 refresh register: in frame 146, the same previous RNG value 177 becomes 235 with T and 212 without T. Replicating source RNG parity in an independent high-level core therefore needs a verified replacement for this instruction-path-sensitive input, not just a byte-state formula. At frame 156 the enemy enters kind 108 in all paths; RNG 227/55/28 selects source-table indexes **3/7/4**, yielding X velocity **−48/+96/+48** respectively. The source then tests the selected **velocity sign** and changes kind to 110 only for positive X (no-T/A). The earlier inference that it tested RNG bit 7 directly was wrong. This first enemy-state difference is **not evidence of a sword hit**; trace collisions, enemy damage and scoring independently before promoting combat behavior into `GameCore`.

For a **deliberately altered, non-parity experiment**, run the [RNG intervention probe](../reverse_engineering/tools/RNGIntervention.swift) locally. It accepts the same three source-free schedules, forces a chosen byte on every RNG write starting at zero-based frame 145, and writes only bounded actor positions/kinds/RNG values into ignored private JSON:

```sh
swiftc -O -parse-as-library "$SPECCY_CORE_DIR"/*.swift \
  reverse_engineering/tools/RNGIntervention.swift -o "$OUT/RNGIntervention"
for byte in 0 255; do
  for scenario in fire-before-contact no-fire-encounter unrelated-a-control; do
    "$OUT/RNGIntervention" "$ROM" SNAPSHOTS/Snapshot_GamePlay.z80 \
      "reverse_engineering/analysis/$scenario-schedule.json" 190 "$byte" 145 \
      > "reverse_engineering/private/intervention-$scenario-$byte.json"
  done
done
```

The [numeric summary](../reverse_engineering/analysis/rng-intervention.json) records that fixed RNG **0** prevents the control paths' damage through frame 190 too; fixed **255** retains damage at frame 164 without T/A while T still avoids it. T also changes player animation and execution timing and can alter enemy update cadence even with RNG forced. These **counterfactual runs do not match the unmodified emulator after intervention** and do not establish sword damage or collision rules. Keep them distinct from the three fully reference-verified 190-frame replays.
