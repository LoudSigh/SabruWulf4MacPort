# Release test plan

Status: release gates. The placeholder core's XCTest tests and all three native app builds passed locally; an iOS simulator visibly launched the app, while a Vision Pro simulator launched its process but headless window visibility and interaction remain unverified. User-captured 48K `.z80` snapshots provide verified **menu and in-game screen/RAM images**; bounded, independently checked replays cross a few room boundaries. **Full original-game parity and cross-platform control-interaction UI tests remain unverified.** XCTest is the selected automated framework. Source-specific cases require authorized local media and reproducible reference state; public CI uses synthetic fixtures.

## Functional and integration cases

### TC-001: Reject malformed tape
- **Priority**: P0
- **Preconditions**: Build `TapeInventory`; use rights-safe synthetic TZX fixtures.
- **Steps**:
  1. Inspect valid header, standard data and BASIC header fixture.
  2. Inspect a truncated payload and an unknown block ID.
- **Expected Result**: Valid metadata and checksums are reported; malformed inputs exit nonzero with explicit offset/ID. No input is modified or payload bytes emitted.
- **Edge Cases / Variants**: Empty file, length exceeding EOF, corrupt checksum and unsupported control block.

### TC-002: Reference loading and golden baseline
- **Priority**: P0
- **Preconditions**: Verified 48K ROM, exact TZX SHA-256 from the input manifest and a controlled input replay.
- **Steps**:
  1. Boot the 48K emulator from the supplied TZX without assuming an instant CODE load.
  2. In an isolated CPU copy, check the Z80 `RRA` flag fix against a synthetic ROM header, then separately verify transient RAM matches for the two standard TZX blocks. Keep the backup and tape untouched.
  3. Compare the first following pure-data block against an equal-duration steady-EAR control; distinguish interrupt keyboard scans from foreground tape reads by the FE port-row selectors.
  4. Record loaded memory, first playable frame, game-state markers and frame-indexed controls; repeat with the same ROM, emulator version and inputs.
- **Expected Result**: Repeated reference captures match; the dump identifies program intervals and loader state. If loading fails, document the blocking cause rather than invent a baseline.
- **Edge Cases / Variants**: Pure-data pulses, BASIC autostart, loader timing and slow/fast emulation.

### TC-002A: Resume captured menu into gameplay
- **Priority**: P0
- **Preconditions**: Verify the SHA-256 and 48K model of `SNAPSHOTS/Snapshot.z80`; load it with a known-hash ROM in the emulator that produced it.
- **Steps**:
  1. Confirm the 256×192 menu renders with `0` as the start option.
  2. Wait for the captured ULA pulse/delay segment to finish, then record frame-indexed keyboard/joystick actions and FE input reads while selecting controls and starting the game.
  3. Save a new snapshot during visible gameplay and compare RAM/frame hashes on repeated replay.
- **Expected Result**: Gameplay screen and code state transition are reproducible. If the emulator does not reach keyboard polling or ignores inputs after reaching it, diagnose its input/resume path rather than treating menu RAM as a gameplay trace.
- **Edge Cases / Variants**: Different ROM, pause/joystick selection, short and held 0-key presses.

### TC-002B: Compare menu and in-game captures
- **Priority**: P0
- **Preconditions**: Two hash-verified 48K `.z80` inputs from the input manifest.
- **Steps**:
  1. Restore each independently with the same reference ROM and compare screen/48K RAM hashes.
  2. Count changed bytes in the bitmap, attributes, system area and remaining RAM without publishing the bytes.
  3. Test replay only if the emulator continues in game-owned code and input changes game-state markers.
- **Expected Result**: The first two steps yield the baseline counts in `gameplay-reference.json`; otherwise the source revision has changed. Bounded gameplay replay now advances with scheduled input, but tape-boot parity is unresolved.
- **Edge Cases / Variants**: Snapshot taken during interrupt, display FLASH and RAM self-modification.

### TC-002C: Input-driven reference replay diagnostic
- **Priority**: P0
- **Preconditions**: SHA-verified in-game snapshot and 48K ROM; private `SnapshotReplay` built against the local backup.
- **Steps**:
  1. Run 100 frames without input and with Q held during frame indexes 20–39; repeat the Q run.
  2. Compare per-frame hashes and count RAM CPU steps and FE reads, not only the PC at the frame boundary.
  3. Repeat with A/O/P/Space, then validate observed effects against a functioning independent emulator.
- **Expected Result**: Repeated Q run has identical JSON and diverges from no-input after the scheduled key press. Input-dependent hashes are not promoted to golden gameplay rules until the independently observed actions agree.
- **Edge Cases / Variants**: Cached FE reads, incomplete port simulation, interrupt reentry, ROM timing and snapshot phase.

### TC-003: Native gameplay regression
- **Priority**: P0
- **Preconditions**: Source-backed room, entity and rule contracts from TC-002; authorized local imported assets where needed.
- **Steps**:
  1. Replay start, four-direction movement, obstacle collision, transition, attack, damage, item pickup and restart.
  2. At checkpoints compare room, position, lives, inventory, score/events and rendered state with the reference.
- **Expected Result**: Every checked state transition matches or carries an explicit approved discrepancy; no gameplay rule depends on render cadence or platform.
- **Edge Cases / Variants**: Boundary coordinates, held keys, simultaneous actions, zero lives, repeated transitions.

### TC-004: Three native app targets
- **Priority**: P0
- **Preconditions**: Xcode targets, supported SDKs and macOS/iOS/visionOS simulator destinations.
- **Steps**:
  1. Build and launch each app, open a new game, move, pause/resume and restart.
  2. Exercise keyboard/controller on macOS, touch/controller on iOS, and windowed controls on visionOS.
  3. Background/resume each app and inspect accessible control labels.
- **Expected Result**: Each app bundle launches with usable controls, preserves/reset state deliberately, and avoids trapping or inaccessible buttons.
- **Edge Cases / Variants**: Small windows, iPhone safe areas, focus loss, reduced motion, dynamic text and controller disconnect.

### TC-005: Asset-import and release boundary
- **Priority**: P0
- **Preconditions**: A public build without copyrighted game media and a separately authorized local import.
- **Steps**:
  1. Install the public build; confirm placeholders are identified and private assets absent.
  2. Attempt import of valid tape, wrong SHA-256, truncated tape and unsupported format.
- **Expected Result**: Only a verified, authorized source is accepted; failure is actionable and does not appear as a successful import. No private ROM, tape, dump, or extracted assets appear in the public Git history or app bundle.
- **Edge Cases / Variants**: Read-only original path, revoked file access, repeated import and low disk space.

### TC-006: Private 16x16 source-backed world viewer
- **Priority**: P1
- **Preconditions**: Locally generated `reverse_engineering/private/snapshot-803e4197989c-world-v2.json` from both SHA-verified snapshots; app running on macOS, iOS or visionOS.
- **Steps**:
  1. Expand the read-only world disclosure and import the JSON through the platform file picker.
  2. Visit a corner and a far-edge room using the grid and North/West/East/South selection buttons.
  3. Import a truncated file, an invalid 49th room type and a file claiming another snapshot hash.
- **Expected Result**: The grid shows 256 selectable positions and the selected template's placement count/markers; version-2 imports also show measured orange bounds after **layout, pointer table, room-record and placement-bound hashes** agree. Navigation stops at world bounds. Altering one otherwise valid-looking version-2 X/Y or width causes a visible import error; version-1 data is labeled legacy topology only. The separate placeholder gameplay state is unchanged.
- **Edge Cases / Variants**: Move the private file to iOS/visionOS through an authorized Files provider; verify keyboard/VoiceOver focus and labels. This is source structure, not verified original movement or collision.

### TC-007: Optional private background overlay
- **Priority**: P2
- **Preconditions**: TC-006 source world imported; authorized local background PNG directory supplied outside the app bundle.
- **Steps**:
  1. Choose “Preview private background images” and select the directory.
  2. Visit a room with several placements, then another room with missing artwork.
  3. Try an empty folder and a folder with malformed or oversized files.
- **Expected Result**: Available local images appear at source coordinates; missing addresses retain markers and the displayed count reports partial coverage. An empty folder reports an error, not success. Artwork is not copied into the app or repository and gameplay state remains unchanged.
- **Edge Cases / Variants**: Files-provider access expiry, macOS Retina versus iOS image scaling, VoiceOver labels and performance with 41 images.

### TC-008: Original keyboard actions remain separate from native controls
- **Priority**: P1
- **Preconditions**: User-captured 1-player keyboard snapshot and the linked 48K control handler; `OriginalAction` mapping tests.
- **Steps**:
  1. Confirm Q/W/E/R/T map to left/right/up/down/fire; unrelated A/P/Space do not acquire invented original bindings.
  2. Run a 100-frame no-input replay and repeat each Q/W/E/R/T held from frame index 20 through 39 with fresh FE reads.
  3. Check divergence frames and re-run one scenario to confirm deterministic JSON; compare visible outcomes to the user's working original emulator.
- **Expected Result**: The action mapping is stable and each source-row key changes the approximate reference trace. Do **not** accept changed hashes alone as proof of exact movement, collision, or fire behavior in the native game.
- **Edge Cases / Variants**: Key repeat, simultaneous actions and remapped platform controllers; source-art overlay must not affect action output.

### TC-009: Source actor position checkpoints
- **Priority**: P0
- **Preconditions**: The 48K gameplay capture, verified actor entity at `0x9702`, and a local CPU replay with fresh FE reads.
- **Steps**:
  1. Run the no-input reference for 100 frames; verify room 168 and position (57,112).
  2. Press Q/W/E/R/T at zero-based frame 20 and release at 40; compare actor fields at frame 40 to [reference-replay.json](../reverse_engineering/analysis/reference-replay.json).
  3. Hold each action through frame 150 and confirm the recorded room ID and positions; repeat one scenario to test determinism.
- **Expected Result**: No input holds position; directional keys produce distinct X/Y outcomes; fire leaves position unchanged in these cases. All five held-input runs stay in room 168. For the six 100-frame schedules, screen hashes and actor room/X/Y at frames 40 and 100 also match the unmodified reference emulator. This tests one captured room and selected times only, not the whole-world collision or quest.
- **Edge Cases / Variants**: World boundaries, blocked left route, keyboard repeat, enemy motion and differences in a cycle-accurate emulator.

### TC-010: Import private replay into the native world viewer
- **Priority**: P1
- **Preconditions**: Import the validated world JSON first; generate `replay-q-100.json` with the local preview launcher.
- **Steps**:
  1. Import the private replay and scrub to frames 1, 40 and 100.
  2. Confirm the captured room remains 168, with recorded coordinates displayed and the cyan ring staying in the selected room.
  3. Select a different room, then scrub; the view should return to the recorded room.
  4. Import malformed JSON, a different snapshot hash, or nonsequential frame numbers.
- **Expected Result**: A read-only actor marker follows the imported frame data; invalid inputs report errors. The separate prototype gameplay state is unaffected. No original media is bundled.
- **Edge Cases / Variants**: iOS/visionOS Files provider permissions, VoiceOver slider labels, last-frame clamping, incomplete artwork coverage.

### TC-011: Scrub a controlled transition between source rooms
- **Priority**: P1
- **Preconditions**: Import version-2 private world data; use the preview launcher to create `replay-upper-exit-180.json` from [upper-exit-schedule.json](../reverse_engineering/analysis/upper-exit-schedule.json).
- **Steps**:
  1. Import the scheduled private replay in the read-only viewer.
  2. Scrub between frame 67 (room 168) and frame 68 (room 152); compare reported X=121/Y=42.
  3. Confirm the selected grid cell follows the new room, the cyan marker stays visible, and the input label changes from W to E or NONE as appropriate.
  4. Attempt import of overlapping intervals, an invalid key, or an interval extending beyond the last frame.
- **Expected Result**: The actor path crosses the room boundary at frame 68 without changing the separately playable placeholder. Core tests reject invalid scheduled metadata. The absolute-boundary replay agrees on room/X/Y for all 180 frames but differs on six screen hashes; the reference-relative diagnostic agrees on **all 180 RAM frames**. Do not treat the absolute replay's redraw frames as pixel-exact goldens.
- **Edge Cases / Variants**: Scrub backward across the boundary; import old single-key schema-1 replay; missing bounds in a version-1 world.

### TC-012: Run the captured native movement slice
- **Priority**: P0
- **Preconditions**: Version-2 private world and scheduled transition replay imported; partial measured movement selected (pink marker).
- **Steps**:
  1. Advance 20 frames with no key, 10 with W, and 150 with E; use the step button for exact timing.
  2. Compare the pink measured marker against the cyan source replay marker and numerical room/X/Y for every frame.
  3. At frames 67–75 verify the north exit moves to room 152, freezes the actor for the redraw, then rebases to Y=191.
  4. Try an unverified exit and verify playback pauses with an explicit error; reset and confirm frame zero is restored.
- **Expected Result**: Room/X/Y matches all 180 north-exit frames, 200 round-trip frames and 600 held-direction frames; the separate placeholder remains unaffected. Locally run `SABRE_PRIVATE_WORLD=<private-world-v2.json> SABRE_PRIVATE_REPLAY=<private-replay-upper-exit-180.json> SABRE_PRIVATE_ROUND_TRIP=<private-replay-round-trip-200.json> SABRE_PRIVATE_HELD_REPLAY_DIR=<private-directory> swift test --filter CapturedMovementTests` for automated parity. This gate does not validate attacks, enemies, score or most room exits.
- **Edge Cases / Variants**: Play at 50 Hz versus single-step, app background/resume, missing version-2 bounds and alternate inputs that reach an unsupported exit.

### TC-013: Provisional west exit and dynamic-actor blocker
- **Priority**: P1
- **Preconditions**: Private version-2 world and `replay-west-exit-256.json` generated from [west-exit-schedule.json](../reverse_engineering/analysis/west-exit-schedule.json).
- **Steps**:
  1. Run the W/E/idle/Q schedule and compare native room/X/Y to the manual CPU reference for frames 1–256.
  2. Observe room 152 -> 151 at frame 226 and actor X rebasing to 239 at frame 233.
  3. Compare the same schedule to the unmodified `stepFrame()` reference path; record the earliest input-dependent mismatch.
  4. Probe beyond frame 256 privately; diagnose moving-actor collisions before extending the native implementation.
- **Expected Result**: Native static state matches all 256 *legacy absolute-boundary* frames. In that mode the full emulator first diverges in RNG at frame 101 and enemy placement at 102; the enemy encounters the player at frame 163. In **reference-relative mode**, verify **256/256 complete RAM-frame matches** instead, including the encounter. The native static-only west branch does **not** match that gameplay after damage; no moving-actor pause should be hard-coded.
- **Edge Cases / Variants**: Fresh keyboard-port reads, reference timing/cache differences, moving entities blocking X=27 in room 152 or X=170 in room 151.

### TC-014: Compare private moving-entity paths without simulating them
- **Priority**: P1
- **Preconditions**: Import private version-2 world, matching `replay-west-exit-256.json` and `west-entity-trace-v2.json`, or the reference-timed `replay-west-reference-256.json` and `west-entity-reference.json` pair from the preview launcher.
- **Steps**:
  1. Scrub to frames 101–102; inspect the first RNG and moving-entity divergence in the private diagnostic.
  2. Scrub to frame 163; confirm orange manual entity position X=161/Y=130 and purple unmodified-emulator entity position X=104/Y=135 in room 152 near the cyan player X=121/Y=126.
  3. Switch to the reference-timed pair; at frame 163 verify both entity markers agree at X=104/Y=135. Run the private `--require-ram-parity` diagnostic to require all 256 RAM frames.
  4. Import either trace alongside a replay with a different frame count, timing mode or player trajectory.
- **Expected Result**: Matching traces render generic markers only while the entity is active and show numeric positions even if inactive. The reference-timed trace reports 256/256 matching RAM frames. Mismatched replay/trace pairs show an explicit error instead of misleading markers. No enemy AI, collision or original sprite pixels are bundled.
- **Edge Cases / Variants**: Imported file truncated/oversized, inactive entity kind, switching replay after a trace import, VoiceOver marker labels.

### TC-015: Provisional east return stops before damage
- **Priority**: P1
- **Preconditions**: Import the private world and `replay-east-return-279.json` generated from [east-return-schedule.json](../reverse_engineering/analysis/east-return-schedule.json).
- **Steps**:
  1. Follow W frames 20–29, E 30–99, Q 180–225, W 233–278, with no input in the gaps.
  2. Confirm room 151 -> 152 at frame 246 and X=0/Y=126 at frame 253.
  3. Compare source/manual and native room/X/Y through frame 279; inspect frame 280 privately without extending native parity.
- **Expected Result**: Native actor matches the legacy absolute-boundary reference for 279 frames. At frame 280 a moving entity near X=85/Y=130 triggers source player damage; native enemy logic is still absent. This route remains provisional native behavior and has **not** been checked frame-by-frame in reference-relative mode.
- **Edge Cases / Variants**: East edge threshold, seven-frame redraw pause, missing room geometry, early action changes and damage-state timing.

### TC-016: Private sprite silhouette preview
- **Priority**: P2
- **Preconditions**: An authorized local `SNAPSHOTS/graphics/downloaded/` folder with previously checked `10.png` and `15.png`; private world imported.
- **Steps**:
  1. Import the folder with “Preview private sprite silhouettes (optional)”.
  2. Inspect both labeled thumbnails while stepping the measured movement preview and resizing the scene.
  3. Repeat with an empty folder and with samples of incorrect dimensions.
- **Expected Result**: Only correctly sized local samples appear, with no pixel files in the app bundle or Git. Empty/entirely invalid input reports an error, while a single correctly sized sample may be previewed alone. The importer does not authenticate artwork content. Sprite inspection does not affect native actor state; room geometry retains its 4:3 aspect.
- **Edge Cases / Variants**: iOS/visionOS Files provider permissions, VoiceOver thumbnail labels and import after replacing the world data.

### TC-017: Observe source attack without claiming native combat
- **Priority**: P1
- **Preconditions**: Private world and `replay-fire-reference-100.json` generated by the preview launcher from [fire-observation-schedule.json](../reverse_engineering/analysis/fire-observation-schedule.json).
- **Steps**:
  1. Import and scrub frames 20, 21, 23, 27, 31, 35, 40, 41 and 100; compare displayed actor state and coordinates to [reference-fire-observation.json](../reverse_engineering/analysis/reference-fire-observation.json).
  2. Run `VerifyReferenceReplay` on the private replay; require exactly 100/100 RAM and screen hashes.
  3. Select Fire in a core action test and confirm unsupported native combat still reports an explicit error.
- **Expected Result**: Recorded T action changes actor state, not position, in the checked room. The native game does not imply verified hit detection, enemies or animation from the observed state numbers.
- **Edge Cases / Variants**: Wrong snapshot hash, missing actor-state field on older replay imports, changing from T to a directional key.

### TC-018: Import and browse locally extracted sprite masks
- **Priority**: P1
- **Preconditions**: `SnapshotSpriteIndex --private-atlas` has verified both private 48K captures; the app's world viewer has imported the matching world JSON.
- **Steps**:
  1. Import `snapshot-803e4197989c-sprite-atlas-v1.json` through the app's private atlas picker.
  2. Visit IDs 0, 16, 21 and 195. Verify the sentinel is empty, samples 16/21 have 16×21 and 16×22 dimensions, and other IDs render only decoded monochrome pixels.
  3. Attempt a malformed base64 record, a changed pointer address, and a wrong snapshot hash.
- **Expected Result**: All 196 pointer IDs are selectable; 152 distinct nonempty records decode and 14 IDs reuse the empty sentinel. The importer verifies table and record hashes, rejects changed source data explicitly and neither changes movement nor bundles bitmap bytes.
- **Edge Cases / Variants**: iOS/visionOS Files provider permissions, VoiceOver slider labels, resetting atlas on world replacement, smallest/largest sprite and unsupported color/animation claims.

### TC-019: Resolve recorded T-state silhouettes privately
- **Priority**: P1
- **Preconditions**: Private world, hash-validated sprite atlas and `replay-fire-reference-100.json` imported into the same viewer.
- **Steps**:
  1. Scrub the T-key frames 20–41 and check the displayed silhouette ID follows the recorded actor state, including 42 at frame 21 and 20 at frame 41.
  2. Import an older replay with no actor-state field; inspect the manual atlas slider independently.
  3. Replace the world and confirm the atlas and replay are cleared rather than silently paired with new data.
- **Expected Result**: All 100 T-run actor-state IDs resolve to nonempty source masks. No bitmap payload is bundled or pushed, and source-mask display never changes movement or claims full animation/combat fidelity.
- **Edge Cases / Variants**: Invalid actor ID, empty sentinel ID, file permission loss and large text/accessibility settings.

### TC-020: Render source background bitmaps from local snapshots
- **Priority**: P1
- **Preconditions**: `SnapshotRoomIndex --private-map` has generated the private world and background atlas from both verified captures.
- **Steps**:
  1. Import the matching world, then `snapshot-803e4197989c-background-atlas-v1.json`.
  2. Visit several world positions and confirm native mint 1-bit shapes align with orange measured bounds; source Y=136/height=56 begins at screen Y=136, and E/up moves the actor marker toward the screen top.
  3. Toggle the approximate attribute-color preview; verify synthetic ink/paper/bright/FLASH-bit tests and complementing the source bitmap bit for ink/paper selection, but do not claim screen parity.
  4. Import local PNG backgrounds as well, then replace the world. Check that source atlas precedence is clear and stale art/atlas data is removed when world data changes.
  5. Attempt a modified bitmap byte, a malformed attribute header, an oversized file and an atlas missing one of 41 referenced records.
- **Expected Result**: The importer verifies 41 unique background records, 9,686 source bytes and all 919 references. Invalid data reports an error, with no silent fallback to invented bitmaps. Bitmap placement and actor markers use source X/Y directly; the same `BackgroundScene` code used by the native color preview matches covered RGB pixels with bit inversion in the captured room (29,056/29,056), north-exit room (28,544/28,544) and west-exit room (30,720/30,720). Uncovered pixels in its in-memory image are transparent; the west-exit replay also matches all 260 RAM frames in the backup emulator. FLASH timing, dynamic sprites, native display scaling and other room templates remain unverified. No original pixels are bundled or pushed.
- **Edge Cases / Variants**: Multi-placement overlap, 4:3 resizing, VoiceOver room summary and iOS/visionOS private file access.

### TC-021: Controlled fire/no-fire/unrelated-key enemy approach
- **Priority**: P0
- **Preconditions**: Generate three private 190-frame replays and matching entity traces with [fire-before-contact-schedule.json](../reverse_engineering/analysis/fire-before-contact-schedule.json), [no-fire-encounter-schedule.json](../reverse_engineering/analysis/no-fire-encounter-schedule.json) and [unrelated-a-control-schedule.json](../reverse_engineering/analysis/unrelated-a-control-schedule.json).
- **Steps**:
  1. Verify all 190 RAM and screen hashes of **each of the three** replays against the unmodified emulator.
  2. Import each replay/trace pair in turn; inspect actor state at frame 146, enemy state at 156, enemy X at 159 and actor/enemy at frames 163–164.
  3. Compare the A-key control at frames 156, 159, 164 and 170, then compare source-free [reference-fire-encounter.json](../reverse_engineering/analysis/reference-fire-encounter.json) checkpoints.
- **Expected Result**: Input-dependent trajectories match the recorded evidence; the first T-specific enemy-state change follows the low-three-bit RNG choice of **signed X velocity** at frame 156, after T's RNG diverged at frame 146. The source tests the chosen velocity sign, **not RNG bit 7**. An unrelated key changes RNG and encounter timing but also chooses positive X like no-T and does not prevent damage through frame 190. The preview stays read-only and native combat is still explicitly unsupported.
- **Edge Cases / Variants**: Same key held different frame counts, RNG phase changes, different enemy direction, missing private trace and damage-state timing.

### TC-022: Bottom-anchored player sprite preview
- **Priority**: P1
- **Preconditions**: SHA-verified private sprite atlas, world data and `VerifyActorScreen` built with the user's local emulator; native macOS/iOS/visionOS apps available.
- **Steps**:
  1. Run `VerifyActorScreen` for Q/W/E/R/T and require the exact frame and pixel counts in [actor-screen.json](../reverse_engineering/analysis/actor-screen.json).
  2. Import world and private sprite atlas in the app; without a replay, inspect actor-state 21 at X=57/Y=112 in room 168. Hide and show the recorded-player overlay.
  3. Import a replay with actor-state IDs, scrub T at frame 21 (kind 42), then movement and W frames 43–53. Resize the room and exercise VoiceOver's silhouette label.
  4. Replace the private world, then import a replay without actor-state IDs; verify the old atlas clears and no fabricated animated sprite appears.
- **Expected Result**: Source mask rows are reversed for screen orientation and bottom-aligned at actor Y; the verifier finds 489/500 exact frame rectangles and 173,348/173,472 matching white/off pixels. W frames 43–53 remain explicitly qualified: 48 bit-and-white, 76 white-only and 16 additional bit-only disagreements have an unresolved cause. The white overlay shows a recorded silhouette only when the matching private atlas and state exist; it never becomes native animation or combat.
- **Edge Cases / Variants**: Empty pointer sentinel, invalid actor ID, missing private atlas, recorded room different from selected room, small windows and other platforms' file providers.

### TC-023: Source contact carry versus native predicate
- **Priority**: P0
- **Preconditions**: Verified 48K gameplay snapshot and ROM, `SnapshotDivergence` compiled with `SpeccyCore` and `GameCore`, six published source-free input schedules.
- **Steps**:
  1. Run each schedule with `--reference-timing --require-ram-parity --require-contact-parity`; keep detailed JSON only in the ignored private directory.
  2. Check [reference-contact.json](../reverse_engineering/analysis/reference-contact.json) counts and positive-call frames, including no-T/west 162, A 169 and no positives on the T path.
  3. Exercise synthetic core tests for strict unequal thresholds, player kind 16/31 versus 32/47, room mismatch, byte-5 guard and nonzero suppression gate.
  4. Compare contact frame 162 against damage state at 164 (and A contact 169 against damage 170); verify the native movement preview still does not invent life loss or enemy AI.
- **Expected Result**: All **3,881** called contact returns match the pure predicate while all **1,206** RAM frames match the unmodified emulator. This is a contact check, not an implementation of enemy movement or delayed damage.
- **Edge Cases / Variants**: Rejected timing modes, missing or corrupted ROM, an unsupported key schedule, next-room entity and active attack player kind.

### TC-024: Observe extended injury and life byte without native damage
- **Priority**: P0
- **Preconditions**: Verified 48K snapshot/ROM and the no-fire, T and A source-free schedules; private reference emulator available.
- **Steps**:
  1. Replay each schedule for 600 reference-relative frames with actor kind enabled; require 600/600 RAM and screen hashes per run.
  2. For each run, require contact and first-injury parity; compare first and second positive frames in [reference-damage.json](../reverse_engineering/analysis/reference-damage.json). Check 63/63 source actor-update transitions per first injury.
  3. In the viewer import `replay-no-fire-600.json`; scrub frames 162, 164, 165, 230, 231, 298 and 318. Compare the displayed source life byte and actor kind with the numeric evidence.
  4. Scrub T through frame 228 and 297; confirm the previous 190-frame no-contact observation is not mislabeled as permanent protection. Confirm the measured native movement slice does not apply a fabricated injury transition.
- **Expected Result**: The source life byte drops 1→0 after 63 kind-65 **actor updates** spread across 66 displayed frames in each first-injury run. The pure core tick matches 189/189 source transitions; the kind-64 duration, actor-update scheduling and subsequent zero-life kinds still differ or remain unmodeled. The viewer remains read-only; native health and end-state behavior are **not** asserted from these bounded traces.
- **Edge Cases / Variants**: Long replay import limit (900), replay mismatch/timing mode, second contact after lives byte reaches zero, T held during a later encounter and unsupported damage model.

### TC-025: Verify bounded return to menu
- **Priority**: P0
- **Preconditions**: Both hash-checked menu/gameplay snapshots, verified ROM, three source-free encounter schedules.
- **Steps**:
  1. Generate an 800-frame reference-relative replay for each schedule and verify every RAM/screen hash against the unmodified emulator.
  2. Run `VerifyReferenceReplay --menu SNAPSHOTS/Snapshot.z80` with expected first menu-text frames 503 (no T), 510 (A), and 679 (T); reject an intentionally incorrect expected frame.
  3. Also require `SnapshotDivergence --require-menu-sequence` alongside reference/RAM/contact parity: verify menu setup at second contact+68, menu return routine at +199, and first exact text at +205 in all three schedules.
  4. Scrub each imported replay just before and after that frame; note that the viewer **does not render the replay's menu screen** and the numeric player fields left in memory are inactive once the menu appears.
  5. Check import accepts up to 900 frames and rejects 901; verify the private replay and screen are not bundled or committed.
- **Expected Result**: All 2,400 RAM and screen hashes match, while the first exact central menu-text region matches 2,560/2,560 RGB pixels only at the expected frame in each run. The result proves this bounded visible return, not full-screen parity, starting a new game, or a native game-over implementation.
- **Edge Cases / Variants**: FLASH/color phase, changed menu snapshot, replay hash corruption, later matching frames, app slider on final frame.

### TC-026: Restart source game with zero key after menu return
- **Priority**: P0
- **Preconditions**: Verified 48K gameplay/menu snapshots, 48K ROM and private world/background atlases; [restart-after-menu-schedule.json](../reverse_engineering/analysis/restart-after-menu-schedule.json).
- **Steps**:
  1. Run an 800-frame reference-relative replay and verify all RAM and screen hashes against the unmodified emulator, plus contact/injury/menu sequence parity.
  2. Compare `0` held at frames 530–534 with a one-frame `0` tap and 10/20-frame holds; do not infer key response from held duration alone.
  3. Verify the actor room clears at frame 535, returns to room 168 at 654, and settles at X=120/Y=112, kind 16, life byte 4 from frame 660.
  4. Run the source background verifier at frame 663 (expected non-match: 27,318/29,056 covered pixels) and frame 664 (expected exact: 29,056/29,056).
- **Expected Result**: The reference-timed `0` path recovers one rendered source-game start; the native viewer can scrub its recorded actor bytes, but no native start-game, enemy or quest initialization is claimed. Do not infer immediate keyboard movement from a static early-start frame.
- **Edge Cases / Variants**: Menu polling phase, new-game redrawing versus actor-byte initialization, option choice, different pre-menu input history and input release.

### TC-027: Keyboard-selected movement after recorded restart
- **Priority**: P1
- **Preconditions**: The two private 48K snapshots, 48K ROM, world/background atlases, and [restart-keyboard-movement-schedule.json](../reverse_engineering/analysis/restart-keyboard-movement-schedule.json).
- **Steps**:
  1. Replay the menu `3`/`0`/long-W schedule for 800 reference-relative frames and verify every RAM/screen hash and 2,309 contact returns against the unmodified emulator.
  2. Assert actor X stays 120 through frame 788, first reaches 121 at 789 and reaches 148 (kind 22, life byte 4) at frame 800. Assert covered room 168 static pixels match 29,056/29,056 at 800.
  3. Compare a no-`3` schedule with W still held long enough; it first moves at frame 793 and reaches X=136 at 800. Verify short W holds through frame 720 do not prove input is broken.
- **Expected Result**: A bounded post-start actor motion path is observable in source RAM; native game initialization, enemy AI and input polling cadence are still incomplete. Menu `3` changes RAM and polling phase, so its four-frame movement shift is **not** labeled a verified control-mode effect.
- **Edge Cases / Variants**: Different menu phase, W held/released during setup, player collision after X=193 and alternate life counts.

### TC-028: Play only verified post-setup native movement
- **Priority**: P0
- **Preconditions**: Hash-verified private version-2 world and [restart-ready-movement-schedule.json](../reverse_engineering/analysis/restart-ready-movement-schedule.json) exported to a 900-frame private replay.
- **Steps**:
  1. Require every 900-frame RAM/screen hash for each Q/W/E/R input, all 10,648 contact returns and the covered room RGB pixels at frame 900 to agree with the reference (28,544 pixels in the north room for E; 29,056 for the others).
  2. Initialize the native measured state at `.observedNewGameReady`; confirm source frame offset 790, room ID 168 and X=120/Y=112.
  3. For Q/W/E separately, hold one direction for 60 measured frames then None for 50 and compare room/X/Y **and bitmap ID** at frames 791–900. Check W X=136 at 800 and 193 by 820; E enters room 152 at 819 and rebases at 825.
  4. For R, compare position and bitmap ID only at frames 791–866 (76 frames); its frame-867 native step must fail explicitly before the one-pixel source difference.
  5. Try a mid-run direction change, Fire, or an extra 111th step on Q/W/E; ensure the preview rejects unverified input/range without silently advancing.
- **Expected Result**: Q/W/E each match 110 checked room/X/Y and bitmap-ID frames, R matches 76 before a source disagreement of unclassified cause, and the captured-midgame origin remains unchanged. Importing the private sprite atlas adds a clearly labeled pink measured shape; it is not original palette or layering. The viewer does not imply that menu polling, initial actor state, enemies, damage or full new-game state are simulated.
- **Edge Cases / Variants**: Shorter unrelated imported replay, reset/switch origins, app background/resume and first frame after release.

### TC-029: Bounded W-then-E movement and animation uncertainty
- **Priority**: P1
- **Preconditions**: Private source world and atlas, and a 900-frame replay exported from [restart-ready-w-e-schedule.json](../reverse_engineering/analysis/restart-ready-w-e-schedule.json).
- **Steps**:
  1. Verify 900/900 source RAM/screen hashes, 2,661 contact returns and 29,056/29,056 covered RGB pixels at frame 900.
  2. Initialize the native `.observedNewGameReady` origin; hold W for 18 measured frames, E for 42, then None for 50.
  3. Require **110/110** room/X/Y matches and **76/76** bitmap ID matches through source frame 866. At 867 and later, verify native ID is unavailable (no falsely animated pink bitmap) while the position marker continues to X=208/Y=86 at frame 900.
  4. Try switching to E one frame early or back to W afterwards; verify the unmeasured combination fails without advancing.
- **Expected Result**: Only the published W→E input change is accepted. Later actor bitmap selection is explicitly unverified; no dynamic AI or general mixed-input capability is claimed.
- **Edge Cases / Variants**: Input release during coasting, short imported replay, missing private sprite atlas, transition to other rooms.

### TC-030: One source-driven enemy motion update
- **Priority**: P1
- **Preconditions**: Verified version-2 private world and three 190-frame T/no-T/A replay/entity-trace pairs; source `CapturedEntityMotion` available.
- **Steps**:
  1. For slot 12 in room 152, feed observed signed X velocities −48/+48/+96 and Y +80 to the pure source-update helper only on frames when the verified reference entity changes position. Extend T to frame 250 with a second source-selected X velocity of −80.
  2. Compare all changed X/Y values with the full emulator trace: require 8/8 early T, 3/3 extended T, 2/2 no-T and 4/4 A updates.
  3. Confirm Y moves from 130 to 135 once, then static room collision holds it at 135; reject unsupported kinds, rooms and velocities explicitly.
  4. Ensure the native measured preview still does **not** autonomously spawn entities, choose RNG directions or convert contact directly to damage.
- **Expected Result**: **17/17** bounded, caller-driven source movement updates match. This proves a per-update motion rule, not enemy AI timing, RNG generation, all room collisions or a playable combat system.
- **Edge Cases / Variants**: Unsigned wraparound, non-multiple-of-16 velocities, obstacle boundaries, killed entity kind and changed room.

### TC-031: RNG-supplied enemy direction without a Z80 runtime
- **Priority**: P1
- **Preconditions**: SHA-checked private menu/gameplay RAM exports, 48K ROM, and T/no-T/A source encounter schedules.
- **Steps**:
  1. Test all eight derived signed velocity values against the bounded, identical direction data in both user captures, without committing source bytes.
  2. Run `SnapshotDivergence --reference-timing --require-ram-parity --require-enemy-direction-parity` for all three 190-frame paths and extended T to 250.
  3. Check low-three-bit RNG values 55/28/227/153 and clock values 230/38 yield +96/+48/−48/−80 horizontally and +80 vertically; the horizontal velocity's sign sets or clears enemy-kind bit 1.
  4. Verify unsupported entity kinds fail and that the native preview does not fabricate RNG data or schedule enemy updates.
- **Expected Result**: Four observed routine calls and all 250 extended-fire RAM/screen hashes agree with the source. The choice rule is correct for **supplied** values, but source randomness, update cadence and autonomous enemy behavior remain unimplemented.
- **Edge Cases / Variants**: High RNG bits, signed minimum, source clock offset, zero-life actor state and different entity slot.

### TC-032: Verify executed-PC evidence without publishing disassembly
- **Priority**: P1
- **Preconditions**: Hash-checked gameplay snapshot/ROM, eight published source-free schedules, private validated sprite atlas and reference emulator.
- **Steps**:
  1. For each schedule, run `SnapshotDivergence --reference-timing --require-ram-parity --coverage`, writing private reports only.
  2. Run `CoverageUnion` against [byte-coverage.json](../reverse_engineering/analysis/byte-coverage.json), the private atlas and eight reports. Compare [executed-pc-coverage.json](../reverse_engineering/analysis/executed-pc-coverage.json) numeric totals and union hash.
  3. Supply a corrupted sorted-PC hash, unsorted list or known-data PC to the union checker and require explicit rejection; confirm the public Git index has no RAM, opcode listing or private PC list.
- **Expected Result**: All 6,900 reference RAM frames agree; 2,589 distinct executed RAM PC starts have zero overlap with known immutable data and validated sprite records. Original instruction lengths and the other 19,974 RAM bytes remain **unclassified**, not inferred from a PC-start count.
- **Edge Cases / Variants**: Source self-modification, alternate menu path, ROM code versus RAM, omitted schedule and PC at a data interval boundary.

### TC-033: Source-driven active-enemy phase and countdown
- **Priority**: P1
- **Preconditions**: SHA-checked 48K ROM and gameplay snapshot, private version-2 world, and three 190-frame encounter schedules.
- **Steps**:
  1. Run the launcher or `SnapshotDivergence --reference-timing --require-ram-parity --require-entity-phase-parity` with `SABRE_PRIVATE_WORLD` set to the ignored private world for each T/no-T/A schedule.
  2. Run `CapturedActiveEnemyStateTests` with the private encounter-report directory and require 8/2/4 moving-update frames, 1/0/2 countdown-only frames, and 190/190 full RAM frames per path.
  3. Confirm an independent countdown at frame 166 followed by movement at frame 167 on the T path preserves timer 6 across the movement, while kind and position change.
  4. Compare ignored private `--watch-entity-state` reports: every observed kind toggle must follow a countdown write by fewer than 20,000 emulator cycles and share its display frame with a position write.
  5. Reject unsupported timer expiry, actor kinds, rooms and velocities; ensure the app never treats these supplied events as autonomous combat.
- **Expected Result**: All 14 observed moving transitions and three separate countdown-only display frames match the source without embedding original code, frames or media.
- **Edge Cases / Variants**: Countdown and move in the same display frame, countdown before move, timer 1, missing private world, no eligible updates and source parity mismatch.

### TC-034: Do not conflate two source enemy timer expiries
- **Priority**: P1
- **Preconditions**: SHA-checked private 250-frame T-key encounter write trace and verified reference-relative RAM parity.
- **Steps**:
  1. Verify slot 12 timer 1→0 at frame 184, velocity clears and the timer is reseeded to 13.
  2. Verify a later 1→0 at frame 220 selects X velocity −80 and Y +80 without resetting the timer, followed by 0→255 at frame 224.
  3. Run the private `--require-enemy-expiry-parity` gate and require two matching routine returns over 250/250 full-RAM frames.
  4. Require the bounded active-movement state to reject timer 1; test the separate expiry decision with supplied RNG/clock bytes and reject unmeasured states.
- **Expected Result**: Both source outcomes match the bounded decision based on whether either prior velocity byte is nonzero. No autonomous scheduling, RNG generation or subsequent countdown wraparound is inferred.
- **Edge Cases / Variants**: RNG-dependent second direction, countdown wraparound, actor removal and different room.

### TC-035: Check both RNG write sites without inventing source timing
- **Priority**: P1
- **Preconditions**: Verified private 48K ROM and gameplay snapshot, three 190-frame encounter schedules and one 250-frame extended T schedule.
- **Steps**:
  1. Run `SnapshotDivergence --reference-timing --require-ram-parity --require-rng-step-parity` for each path.
  2. Compare the frequent site's observed write with `(prior byte + supplied refresh operand + carry) modulo 256`, and the other with `(prior byte + supplied counter low byte + clock) modulo 256`.
  3. Assert 8,421 refresh-site writes and 319 clock-site writes across 820 complete RAM-parity frames. Change a supplied operand in an isolated test and require the predicted byte to change.
  4. Confirm no native code substitutes a guessed PRNG or describes this arithmetic as an autonomous source RNG.
- **Expected Result**: **8,740/8,740** source writes match; source operands and update cadence remain explicitly external.
- **Edge Cases / Variants**: Carry set/clear, modulo-256 wrap, unchanged write values and alternate keyboard timing.

### TC-036: Compose the observed active enemy path
- **Priority**: P1
- **Preconditions**: Private verified world, 250-frame T replay, matching entity trace and ordered source write report.
- **Steps**:
  1. Initialize slot 12 from the source frame-156 kind, timer, position and velocities.
  2. Supply countdown, movement and expiry events in the observed write order; supply the two measured RNG/clock pairs at the expiry calls.
  3. Compare kind, position, timer and velocities at every frame end from 157 through 230 against the reference trace and write report, including timer 2→1 before its final movement and later 0→255→254.
  4. Reject a further unverified countdown after timer 254; confirm no scheduler or native RNG is silently added.
- **Expected Result**: **74/74** consecutive source-backed states match without using an emulator in the core.
- **Edge Cases / Variants**: Countdown/movement split across frames, same-frame countdown before movement, timer-expiry branch choice and stale actor bytes after removal.

### TC-037: Bounded post-setup W/Q reversal
- **Priority**: P1
- **Preconditions**: Private version-2 world, 48K ROM/gameplay snapshot and source-free W/Q restart schedule.
- **Steps**:
  1. Produce a 900-frame reference-relative source replay and require all 900 RAM/screen hashes to match the independent emulator.
  2. Run the native movement state from the frame-790 ready origin; hold W for 18 measured frames, Q for 42, then no input.
  3. Compare room/X/Y for frames 791–870 and sprite ID for 791–850; require unknown idle sprite IDs to be withheld.
  4. Verify all 2,651 source contact returns, including positive frame 868 and player kind 19→64 at frame 870.
  5. Attempt the next frame and require an explicit unsupported-runtime-divergence error instead of inventing injury-state movement.
- **Expected Result**: **80/80** positions and **60/60** sprite IDs match; source frame 871 remains unsupported after measured contact and injury-state entry.
- **Edge Cases / Variants**: Reverse earlier/later than frame 808, wall collision, source enemy contact and idle animation after releasing Q.

### TC-038: Keep observed instruction extents separate from permanent code
- **Priority**: P1
- **Preconditions**: SHA-checked private gameplay snapshot/ROM, isolated CPU fetch probe and T/no-T/A 190-frame schedules.
- **Steps**:
  1. Check synthetic prefix/HALT fetch lengths; replay three 190-frame encounters, one 250-frame T extension, three 800-frame menu returns and five 900-frame restart variants with reference-relative complete RAM parity.
  2. Union fetched RAM byte extents and require 4,915 unique addresses with no overlap with validated immutable game data.
  3. Confirm the two addresses whose fetched values changed stay marked as possible mutable code; do not publish bytes, address lists or disassembly.
  4. Ensure [byte-coverage.json](../reverse_engineering/analysis/byte-coverage.json) retains its static unknown classification instead of treating three paths as complete program coverage.
- **Expected Result**: 7,720/7,720 RAM frames pass, 15,059 originally unknown bytes remain outside the observed candidate-code union, and no immutable code/data partition is claimed.
- **Edge Cases / Variants**: Self-modifying instructions, prefixed operands, unexecuted branches, ROM-only fetches and shared bytes used differently at another time.

### TC-039: Source-driven four-life injury knockback
- **Priority**: P1
- **Preconditions**: Verified W/Q 900-frame replay, extended 1,500-frame private player-write report and life byte 4 from the captured new-game setup.
- **Steps**:
  1. Require 1,500/1,500 complete reference RAM frames and confirm the observed contact at 868 and kind-64 onset at 870.
  2. Pair the source X writes with the subsequent timer writes by execution-cycle order, not display-frame number.
  3. Supply each observed actor tick to `CapturedNewGameInjuryTick` and compare all 45 X results (56→191) and all 45 timer results (32→77), then kind 64→65/timer 63.
  4. Reject other lives, rooms, timers and a further unverified kind-64 tick after timer 77; do not schedule native injury from contact by guesswork.
- **Expected Result**: **45/45** source X/timer tick pairs match; native gameplay remains explicitly bounded before injury-state movement.
- **Edge Cases / Variants**: Frame boundary between writes, obstacle response after X=191, contact-to-injury latency and one-life kind-65 path.

### TC-040: Control transfers are not a complete function inventory
- **Priority**: P1
- **Preconditions**: Isolated private exact-fetch/branch probe, twelve published source-free schedules and hashed 48K inputs.
- **Steps**:
  1. Verify synthetic call/return/jump recognition and 7,720/7,720 complete RAM frames.
  2. Check 104 distinct reached RAM call entries, 232 jump targets and 617 return targets; keep address-level lists private.
  3. Distinguish executed taken jumps from untaken conditional branches, interrupt entries and repeat instructions.
  4. Audit at least one 190-frame path for ROM/RAM transitions; do not infer balanced stacks or function boundaries from aggregate event totals.
- **Expected Result**: Numeric control-flow counts are reproducible, while unexecuted routines and exact routine extents remain unknown and no disassembly appears in Git.
- **Edge Cases / Variants**: Jump-entered/return-terminated code, RST, extended return, interrupt entry, initial snapshot stack and path-end truncation.

### TC-041: Bounded injury entry across lives
- **Priority**: P1
- **Preconditions**: Private player-write reports for no-T/A/T and the 1,800-frame restarted W/Q schedule, with hashed 48K ROM/snapshot.
- **Steps**:
  1. Require 190/190 RAM frames on no-T and A, 250/250 on extended T and 1,800/1,800 on W/Q.
  2. At ordinary entry frames 164/170/229/870/1064/1251, verify timer 1→32, kind →64 and velocity →+3; at final-life frame 1386 verify timer 2→32, kind →68 and velocity →−3.
  3. Feed each observed kind, room, life byte, timer and velocity to `CapturedInjuryStart`; reject unobserved player states.
  4. Keep contact-triggered timer arming and actor-update scheduling external.
- **Expected Result**: **7/7** source-supplied entries match; this is not autonomous damage or a generalized contact delay.
- **Edge Cases / Variants**: Final-life variant, different player kind/room, prior horizontal velocity and unsupported timer.

### TC-042: Arm only the observed positive first contacts
- **Priority**: P1
- **Preconditions**: SHA-checked private T/no-T/A 800-frame menu-return contact reports and W/Q 1,800-frame contact/player-write report.
- **Steps**:
  1. Require 4,200/4,200 full RAM-parity frames and first-injury positive contact frames 162/169/228/868/1063/1250/1385.
  2. Match the six ordinary player timer 0→1 writes and the final-life timer 0→2 write.
  3. Supply a positive contact and each bounded player kind/room/life/velocity input to `CapturedContactArming`; verify timer one.
  4. Reject contact false and all unsupported states. Keep polling cadence and subsequent kind-64 onset external.
- **Expected Result**: **7/7** bounded source arming writes match without asserting a fixed display-frame damage delay.
- **Edge Cases / Variants**: Contact at a display-frame boundary, repeat contact during injury, other life counts and a source contact predicate with no player damage.

### TC-043: Multiple captured kind-65 life countdowns
- **Priority**: P1
- **Preconditions**: Verified 1,500-frame restarted W/Q source run, private player-write report and known-hash ROM/snapshot.
- **Steps**:
  1. Require 1,500/1,500 full RAM frames and source kind-65 entry at frame 918 after four-life knockback.
  2. Check 252/252 source kind-65 actor updates at life-byte changes 231 (1→0 before restart), 983 (4→3), 1131 (3→2) and 1317 (2→1), plus 63/63 kind-69 updates through the final 1499 (1→0).
  3. Assert kind-65/timer 1 yields kind 17/timer 0/life decremented for life bytes 1–4; reject timer outside 1–63 or life outside 1–4.
  4. Check the separately gated `CapturedFinalInjuryTick` kind-69/timer-1 terminal transition to kind 21/timer 0/life 0 at frame 1499; do not infer a menu-return timer.
- **Expected Result**: **315/315** bounded actor updates match without imposing display-frame cadence or claiming a complete game-over rule.
- **Edge Cases / Variants**: Cross-frame terminal write ordering, preceding kind-64 duration, different starting life and kind-69 final defeat.

### TC-044: Source restart through second visible menu
- **Priority**: P1
- **Preconditions**: Known-hash 48K ROM, gameplay/menu snapshots, W/Q source-free schedule and ignored 1,800-frame replay.
- **Steps**:
  1. Require 1,800/1,800 complete RAM and screen hashes against the independent emulator.
  2. Check initial menu setup/return at 366/497 and second setup/return at 1596/1728, with life byte falling to zero at 1499.
  3. Independently render the captured menu and replay frames; after frame 1500 require the first exact match across all 2,560 center-menu RGB pixels at 1733.
  4. Import the private 1,800-frame JSON into the read-only native viewer and scrub both returns; do not treat stale actor RAM bytes as an active player or the inspector as a rendered source screen.
- **Expected Result**: One verified source restart-to-menu path; its state sequence is a future native parity target, not a finished port.
- **Edge Cases / Variants**: Earlier menu match at 503, source actor bytes after menu return, skipped keyboard poll and alternate damage paths.

### TC-045: Final-life reverse knockback before kind 69
- **Priority**: P1
- **Preconditions**: Verified private 1,500-frame W/Q source player-write report and life byte 1 before the final injury.
- **Steps**:
  1. Pair 45 observed X writes (191→56) with 45 timer writes (32→77) by source execution order during kind 68, not display frames.
  2. Supply each measured actor tick to `CapturedNewGameInjuryTick` with room 168, life byte 1 and horizontal velocity −3.
  3. Verify kind 68→69 and timer 77→63 at frame 1434; reject an additional unsupported kind-68 tick.
- **Expected Result**: **45/45** reverse-knockback X/timer updates and the terminal phase match; no general direction choice or automatic native damage is inferred.
- **Edge Cases / Variants**: Last-life contact trigger, wall collision at X=56, cross-frame timer write and subsequent kind-69 countdown.

## Regression cadence and coverage

| ID | Scenario | Type | Risk | Automated? | Gate |
| --- | --- | --- | --- | --- | --- |
| RS-001 | Tape block bounds/checksum/metadata | Unit | High | Yes, synthetic | Every commit |
| RS-002 | Deterministic state updates and input boundaries | Unit | High | Yes, XCTest | Every commit |
| RS-003 | Original replay parity | Integration | High | Local only until fixtures are rights-cleared | Each source/logic change |
| RS-004 | Three-target builds and launch | Simulator smoke | High | Builds in CI; launches locally | Every release |
| RS-005 | Touch, controller, focus, accessibility | Manual | Medium | Partial | Every release |
| RS-006 | Asset provenance and leak review | Manual | High | Ignore checks + review | Every push/release |
| RS-007 | Private world JSON import and boundaries | Unit + manual | Medium | Core parsing automated; file picker manual | Each world-format change |

Track the number of passing tests and reference checkpoints explicitly. Add a regression test for each verified bug. The release sign-off requires functional tests for happy paths and errors, app-to-core integration, simulator smoke tests, manual accessibility checks, and a reviewed rights boundary. A generic playable prototype does not pass original-game fidelity.
