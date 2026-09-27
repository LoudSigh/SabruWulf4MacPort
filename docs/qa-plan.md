# Release test plan

Status: release gates. The placeholder core's XCTest tests and all three native app builds passed locally; macOS, iOS and visionOS apps were launched, with visible layouts inspected on iOS and visionOS simulators. A newly supplied 48K `.z80` provides a verified **menu and RAM image**, but **gameplay input replay, original-game parity and control-interaction UI tests remain unverified**. XCTest is the selected automated framework. Source-specific cases require authorized local media and reproducible reference state; public CI uses synthetic fixtures.

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
  2. Record frame-indexed keyboard/joystick actions and FE input reads while selecting controls and starting the game.
  3. Save a new snapshot during visible gameplay and compare RAM/frame hashes on repeated replay.
- **Expected Result**: Gameplay screen and code state transition are reproducible. If the emulator ignores inputs, diagnose its input/resume path rather than treating menu RAM as a gameplay trace.
- **Edge Cases / Variants**: Different ROM, pause/joystick selection, short and held 0-key presses.

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

## Regression cadence and coverage

| ID | Scenario | Type | Risk | Automated? | Gate |
| --- | --- | --- | --- | --- | --- |
| RS-001 | Tape block bounds/checksum/metadata | Unit | High | Yes, synthetic | Every commit |
| RS-002 | Deterministic state updates and input boundaries | Unit | High | Yes, XCTest | Every commit |
| RS-003 | Original replay parity | Integration | High | Local only until fixtures are rights-cleared | Each source/logic change |
| RS-004 | Three-target builds and launch | Simulator smoke | High | Builds in CI; launches locally | Every release |
| RS-005 | Touch, controller, focus, accessibility | Manual | Medium | Partial | Every release |
| RS-006 | Asset provenance and leak review | Manual | High | Ignore checks + review | Every push/release |

Track the number of passing tests and reference checkpoints explicitly. Add a regression test for each verified bug. The release sign-off requires functional tests for happy paths and errors, app-to-core integration, simulator smoke tests, manual accessibility checks, and a reviewed rights boundary. A generic playable prototype does not pass original-game fidelity.
