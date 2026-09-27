# Sabre Wulf: ZX Spectrum 48K analysis and native Apple port

Status: implementation specification; **no game tape, snapshot, original source, or rights documentation has yet been identified in this workspace**. Do not claim the port is started or complete until those inputs are inventoried. The associated [Autopilot prompt](./COPILOT_PROMPT.md) tells the coding agent how to execute this spec.

## 1. Outcome and boundaries

Analyze the user-supplied ZX Spectrum 48K edition of Ultimate's *Sabre Wulf*: recover its loaded program, code/data boundaries, graphics, room data, audio behavior, rules, and observable interactions. Deliver independently launchable, native macOS, iOS, and visionOS apps implemented in Swift. The playable port must implement the recovered behavior, not embed a Spectrum emulator as its game runtime. Use the emulator only as a reference, test oracle, and analysis tool.

The repository named by the user is `https://github.com/LoudSigh/SabruWulf4MacPort` (retain that spelling). At the time of this spec it is empty; this local directory is not a Git repository. Bootstrap it only when repository access and intended work location have been checked. Never overwrite the emulator backup or assume that changes here have been pushed. Keep private source media and extracted game content out of public commits unless redistribution rights have been confirmed.

Rights are **not** established by the existence of files or this spec. Record provenance and permitted uses of each supplied file before copying, publishing, or bundling it. If rights to distribute original graphics, sound, text, or code are unknown, keep extracted material local and untracked, and use clearly identified original placeholder art in distributable builds. Do not label a placeholder build a faithful release. Do not download an unauthorized game image, ROM, or asset to fill a gap. Emulator code and ROMs have separate licensing/redistribution questions; inspect their terms before reuse or packaging.

### Hard stops

Continue independent work, but explicitly report a blocker rather than fabricate data when: no usable game source is supplied; tape decoding cannot determine loaded bytes; an essential rule is unverified; source rights prevent the intended distribution; required Apple SDKs, signing credentials, or hardware are absent. No invented source addresses, behavior, sprites, test passes, or platform support. Ask for the smallest missing input only after exhausting local, lawful evidence.

## 2. Inputs, provenance, and immutable baselines

Inspect first, without moving or changing anything:

| Input | Location | Treatment |
| --- | --- | --- |
| Working spec | `Spec.md` in this workspace | Plan and acceptance contract |
| Original game files | User to provide: TAP/TZX, snapshots, dumps, assembler files and/or recordings | Local read-only originals; hash and inventory individually |
| Reference emulator backup | `/Volumes/July2025inclOct2022/Visual Studio Code Backups/Carbon Neural/2025-09-13_22-10-25/CarbonNeural_portable_2025-09-13_22-10-25` | Read-only upstream reference; no wholesale copy |
| Associated emulator archive/bundle | Parent backup directory | Preserve as backup, not an input to overwrite |
| Target remote | `https://github.com/LoudSigh/SabruWulf4MacPort` | Empty at spec time; check access before first push |

The inspected emulator has `Package.swift` with macOS 12+, Swift tools 5.9, a `SpeccyCore` library, `speccy` CLI, macOS `CarbonNeural` executable, and tests. It contains `TAP.swift`, `TZX.swift`, `SNASnapshot.swift`, `Z80Snapshot.swift`, `Memory.swift`, `ULA.swift`, and `SpeccyDebug.swift`; these filenames show possible entry points, **not** proof that instruction tracing or Sabre Wulf-specific extraction already exists. Verify actual APIs before choosing reuse. The backup's `.vscode/extensions.json` recommends `swiftlang.swift`, `vadimcn.vscode-lldb`, `github.copilot-chat`, and optional `maziac.dezog`.

Create a local input manifest (`reverse_engineering/input-manifest.json`) with, per item: path relative to the local input root, file format, byte length, SHA-256, origin, edition/revision, permission/redistribution status, and whether it may enter source control. Store raw media under `local-inputs/` (gitignored); do not edit originals. Validate hashes after every transformation. Keep generated extracts in `reverse_engineering/generated/` with provenance back to input hashes, tape block and memory address or time/frame. Do not commit a generated binary merely because it was generated.

If multiple game editions are supplied, choose one baseline by hash and machine model (48K); keep other editions separate, and do not merge assets or trace addresses between them without evidence. Record the ROM identity/hash used for reference runs, but do not commit or redistribute a ROM without permission.

## 3. Development stack and workspace

- Swift 6 for game logic, app targets and platform adapters; deterministic `GameCore` in a Swift package with no SwiftUI, Metal, platform UI or emulator dependency.
- SwiftUI for three distinct app targets in an Xcode project/workspace. Shared Swift package for model, decoding, resources metadata and platform-independent runtime. Use Xcode build settings/asset catalogs and separate macOS, iOS, visionOS app bundle IDs, entitlements and deployment targets. A Swift package alone does **not** produce three installable app bundles.
- Metal for the common 2D pixel-oriented renderer if its implementation is viable on all three targets; one documented rendering contract for viewport, scaling, palette, layers and frame capture. On visionOS begin with a functional windowed 2D app; an immersive RealityKit scene is optional, not a release prerequisite. Use supported visionOS presentation and test in simulator/device.
- AVFoundation/AVFAudio for audio playback with a platform-independent sound-event representation. Add persistence only for real save/settings needs; SwiftData is optional, not a default architectural burden.
- Python for offline analysis/extraction only, with a pinned supported version selected after inspecting installed tools. SkoolKit and z80dasm are optional aids, not prerequisites: verify availability, license and output before depending on them. Rust only with a benchmark demonstrating a real need.
- XCTest for Swift core/runtime/app smoke tests; Python's existing standard-library `unittest` or repository-standard runner for extractors. Introduce additional test tools only for a demonstrated need.

Toolchain: a Mac with Xcode and matching macOS/iOS/visionOS SDKs, relevant simulators, Swift, Python, Git, and VS Code with GitHub Copilot Chat and Swift (`github.copilot-chat`, `swiftlang.swift`). Recommended debugging extension: CodeLLDB (`vadimcn.vscode-lldb`); optional Z80 debugging: DeZog (`maziac.dezog`) if the selected emulator/debug adapter supports it. Do not require redundant autonomous-agent extensions (Continue/Cline/Roo) or an extension merely to edit Markdown/YAML. VS Code is the editor/agent host; Xcode's toolchain, simulators, signing and provisioning remain authoritative for building Apple apps. Check local `xcodebuild -version`, SDK listing and simulators before selecting deployment targets. Never embed signing secrets in the project or CI.

Suggested layout (create incrementally, not as empty scaffolding):

```text
Spec.md
COPILOT_PROMPT.md
.gitignore                         # includes local-inputs/, private dumps, build output
.vscode/extensions.json             # required/recommended extensions
Package.swift                       # shared testable Swift code
Sources/GameCore/
Sources/GameRuntime/
Tests/GameCoreTests/
SabreWulf.xcodeproj/                # three app targets linked to shared package
Apps/macOS/
Apps/iOS/
Apps/visionOS/
Tools/                            # offline tape/disassembly/extraction tools
ToolsTests/
reverse_engineering/input-manifest.json
reverse_engineering/analysis/       # maps, evidence, unknowns, function inventory
reverse_engineering/generated/      # provenance-tagged, permitted outputs only
docs/                              # architecture, controls, fidelity and build guides
.github/workflows/
```

If the game assets cannot lawfully be distributed, keep a local asset import step and reproducible verified placeholders; document how an authorized user supplies originals. Any public CI must use legal fixtures, synthetic bytes and independently authored art, not private tape images.

## 4. Phases, artifacts and exit gates

Execute in dependency order. Maintain a small task list showing evidence, owner, status, next action and blockers. At each gate, run the smallest relevant test and record commands/results. Do not silently substitute stubs for a required input.

### Phase A: bootstrap and baseline

1. Inventory this workspace, the supplied game files and the read-only emulator; check repository state, toolchain and disk paths. Compare existing filenames/hashes before treating them as canonical. Verify source-control/redistribution rules and create `.gitignore` first.
2. Record the chosen game revision, format, input SHA-256, emulator version/reference commit if known, 48K ROM hash and starting state. Build and run the emulator's existing narrow tests **in a separate working copy or without modifying its backup** if practical; report pre-existing failures without changing its source.
3. Establish a reproducible boot/load command for the game in the reference emulator or identify precisely why it cannot boot. Capture title/start frame, input mapping, and a bounded reference recording with frame/timing metadata.

**Gate A:** a validated input manifest and reproducible or explicitly blocked reference startup. Without real game input, do independent scaffolding/tests but do not advance the fidelity claim.

### Phase B: reconstruct loaded program and data

1. Parse each tape block with offsets, checksums, header type, BASIC loader instructions, CODE start/length, concatenation and entry point. Separate loader/ROM effects from program bytes. For TZX, handle only evidenced block types and fail explicitly on unsupported blocks. Prefer snapshot-derived memory only after validating it against a known run.
2. Identify self-decompression, relocation, RAM overlays, writable code/data and interrupt modes. Log memory intervals with initial vs post-load hashes and provenance; a byte not yet classified remains `unknown`, not presumed instruction.
3. Produce a 64 KiB 48K memory map with ROM/RAM boundaries, disjoint program/data regions, screen bitmap/attribute regions, stack, variables and write hotspots. Build reachable Z80 disassembly from validated entry points and trace targets; classify code, data, graphics, tables and uncertain bytes. Track jump tables, indirect calls, subroutine inputs/outputs, interrupt behavior, state machines and cross references.
4. Generate `reverse_engineering/analysis/memory-map.md`, `functions.json`, `byte-coverage.json`, and annotated disassembly with address and input hash. For each *verified* routine, explain observable responsibility and evidence. Do not guess a semantic purpose for every instruction. Document ambiguities with confidence and a concrete experiment.

**Gate B:** all loaded memory ranges accounted for by checksum; each game-owned byte is classified `code`, `data`, `padding`, or explicitly `unknown`, with counts reported. Entry points and relocation decisions have reproducible evidence; no invented function coverage percentage.

### Phase C: capture behavior and recover assets

1. Extend only an isolated copy/fork of the emulator if existing inspection APIs are insufficient. Add bounded deterministic trace modes for PC/opcodes, branch targets, calls/returns, register/state snapshots, selected memory writes, screen/attribute changes and input per frame. Version the trace schema; use ring buffers/filters/file streaming to avoid unbounded logs. Do not claim wall-clock emulation or tracing is inherently deterministic: control seed, ROM, input sequence, clocks and frame counts.
2. Capture golden scenarios: load/title, start, movement in four directions, room transitions, static/dynamic collision, weapon/action, damage/lives/death, item pickup and inventory/quest progression, enemy interactions, sound cues, and win/game-over/restart where observable. Capture expected controls and region-dependent gameplay variance. Record what is still unobserved.
3. Derive graphic data layout from memory and rendering evidence, including bitmap/attribute addressing, colors, masks, sprite frame ordering, animation and rooms/maps; retain palette/FLASH semantics only where actually used. Recover sound-event parameters and timing from beeper code/traces and any other source actually present; do not assume AY music exists in a 48K game.
4. Provide repeatable extraction tools with synthetic test fixtures and format validation. Output machine-readable manifests (dimensions, frame order, palette, source offset/address, hash), PNG/JSON or another documented lossless format. Render known frames and compare against emulator captures. Keep extracted copyrighted media local unless publication is authorized.

**Gate C:** tools deterministically re-extract each identified asset from hashed inputs; representative rooms, sprites, colors and sound triggers are traced to source bytes or marked unknown. Golden inputs, expected frame snapshots and state/event traces are versioned in a rights-safe manner.

### Phase D: behavior-first native port

1. Write a short behavior contract for game states, movement, interactions, AI, inventory, world layout, scoring/progression and restart. Every rule is backed by trace evidence, disassembly, or an explicitly labeled, testable inference. Distinguish original quirks from intentional accessibility/platform adaptation.
2. Implement a fixed-step simulation using input frames and a deterministic seed; define the unit of simulated time by observation, not by an assumed frame rate. Separate `GameCore` state transitions from `GameRuntime` rendering/audio/input. Render from a documented world/sprite representation. Keep pixel and attribute fidelity options if required for verified original appearance.
3. Implement shared menu/play/pause/restart/settings flows. macOS: keyboard and controller, optional pointer-driven menus. iOS: touch controls and controller with safe-area/orientation handling. visionOS: accessible windowed controls and controller/gesture interaction without requiring immersion. All three must offer usable gameplay, audio policy, lifecycle pause/resume, dynamic layout and appropriate accessibility labels. Avoid platform-specific gameplay rules.
4. Implement a permitted asset-import mechanism if originals cannot be bundled; state exactly which source hash/format it accepts. An authorized local build may use recovered assets, but public packaging must reflect the recorded rights.

**Gate D:** on-device or simulator app navigation and gameplay for each platform, with no emulator dependency in the shipped runtime. Golden input replays agree with measured game-state transitions; differences are classified and reviewed, not suppressed.

### Phase E: test, ship and hand off

1. Unit-test decoding, checksums, memory mapping, graphics layout, sound-event conversion, game transitions and save/settings compatibility. Add property/edge tests for truncated/corrupt images and out-of-range map/sprite data. Include seeded deterministic replays from the selected original revision, plus rights-safe synthetic CI fixtures.
2. For each golden scenario compare time-indexed input, position/room, lives, inventory, collision/events, and frame output at documented checkpoints. Set tolerances only for rendering/audio differences justified by the display/audio backends; do not use image similarity as a substitute for gameplay correctness. Report passing/scenario counts and untested branches, not a blanket "95% complete" claim.
3. Build macOS and run unit tests locally. Build and launch iOS and visionOS simulator apps, and test physical devices if available. Check toolchain support first; report SDK/device/signing blockers precisely. Add GitHub Actions macOS runner jobs for legal-fixture package tests and available platform simulator builds. CI cannot validate private input-dependent fidelity unless rights-safe fixtures are provided.
4. Document architecture, memory/asset schemas, provenance, controls, input-import flow, test/replay instructions, building in VS Code and Xcode, supported SDK versions, known fidelity gaps, and release licensing. Package unsigned development apps locally; sign/notarize or publish only with explicit credentials/approval and rights to included assets.

**Gate E / definition of done:** three separately launchable native app bundles, all core flows playable on their intended supported OS/simulator, repeatable extraction from the authorized original, documented and tested golden behavior, clean legal-fixture CI, explicit rights for distributed contents, and no undisclosed blockers. A build with placeholder assets is a prototype, not a completed faithful port. Do not commit or push merely because the spec says "all code committed": honor repository permissions and review untracked/private content first.

## 5. Immediate next actions

1. Obtain user-supplied original game media/source, license/provenance information and (if permitted) the ROM needed to produce the reference run. Inventory and hash rather than assuming the emulator backup contains this game.
2. Decide whether to bootstrap the empty remote in this directory or clone it into a dedicated directory; initialize safeguards (`.gitignore` and rights-safe fixture policy) before the first commit.
3. Check Xcode SDKs/simulators, VS Code Copilot/Swift extension setup and emulator test baseline. Do not install optional disassembly tooling until a real format/parser need is confirmed.
4. Start Phase A with the [Autopilot prompt](./COPILOT_PROMPT.md), preserve gate evidence, and proceed phase by phase; only claim completeness after Gate E.
