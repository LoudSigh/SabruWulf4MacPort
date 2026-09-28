# Release test plan

Status: release gates. The placeholder core's XCTest tests and all three native app builds passed locally; macOS, iOS and visionOS apps were launched, with visible layouts inspected on iOS and visionOS simulators. User-captured 48K `.z80` snapshots provide verified **menu and in-game screen/RAM images**; a bounded, independently checked replay now crosses one room boundary. **Full original-game parity, a native original-game simulator and control-interaction UI tests remain unverified.** XCTest is the selected automated framework. Source-specific cases require authorized local media and reproducible reference state; public CI uses synthetic fixtures.

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
  2. Record loaded memory, first playable frame, game-state markers and frame-indexed controls.
  3. Repeat with the same ROM, emulator version and inputs.
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
- **Expected Result**: The grid shows 256 selectable positions and the selected template's placement count/markers; version-2 imports also show measured orange bounds. Navigation stops at world bounds. Invalid files show an error. The separate placeholder gameplay state is unchanged.
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
  1. Confirm Q/W/E/R/T map to left/right/down/up/fire; unrelated A/P/Space do not acquire invented original bindings.
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
- **Expected Result**: The actor path crosses the room boundary at frame 68 without changing the separately playable placeholder. Core tests reject invalid scheduled metadata. Manual CPU stepping and the unmodified emulator agree on room/X/Y for all 180 frames, but six transient redraw screen hashes differ; do not demand pixel identity for frames 68–73.
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
- **Expected Result**: Native state matches all 256 manual reference frames. Independent `stepFrame()` first diverges in gameplay RNG state at frame 101, in a moving entity at frame 102, then has an encounter at frame 163 and changes player mode at frame 164; its actor room/X/Y agrees only through frame 182. **Do not certify the west branch** as independently validated until RNG and dynamic-actor routes are reconciled. No moving-actor pause is hard-coded into native gameplay.
- **Edge Cases / Variants**: Fresh keyboard-port reads, reference timing/cache differences, moving entities blocking X=27 in room 152 or X=170 in room 151.

### TC-014: Compare private moving-entity paths without simulating them
- **Priority**: P1
- **Preconditions**: Import private version-2 world, matching `replay-west-exit-256.json`, and `west-entity-trace.json` from the preview launcher.
- **Steps**:
  1. Scrub to frames 101–102; inspect the first RNG and moving-entity divergence in the private diagnostic.
  2. Scrub to frame 163; confirm orange manual entity position X=161/Y=130 and purple unmodified-emulator entity position X=104/Y=135 in room 152 near the cyan player X=121/Y=126.
  3. Import the entity trace alongside a replay with a different frame count or player trajectory.
- **Expected Result**: Matching traces render generic markers only while the entity is active and show numeric positions even if inactive. Mismatched replay/trace pairs show an explicit error instead of misleading markers. No enemy AI, collision or original sprite pixels are bundled.
- **Edge Cases / Variants**: Imported file truncated/oversized, inactive entity kind, switching replay after a trace import, VoiceOver marker labels.

### TC-015: Provisional east return stops before damage
- **Priority**: P1
- **Preconditions**: Import the private world and `replay-east-return-279.json` generated from [east-return-schedule.json](../reverse_engineering/analysis/east-return-schedule.json).
- **Steps**:
  1. Follow W frames 20–29, E 30–99, Q 180–225, W 233–278, with no input in the gaps.
  2. Confirm room 151 -> 152 at frame 246 and X=0/Y=126 at frame 253.
  3. Compare source/manual and native room/X/Y through frame 279; inspect frame 280 privately without extending native parity.
- **Expected Result**: Native actor matches the manual reference for 279 frames. At frame 280 a moving entity near X=85/Y=130 triggers source player damage; native enemy logic is still absent. The route is **not independently certified** because its earlier westward portion has a different RNG/enemy path in the full emulator.
- **Edge Cases / Variants**: East edge threshold, seven-frame redraw pause, missing room geometry, early action changes and damage-state timing.

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
