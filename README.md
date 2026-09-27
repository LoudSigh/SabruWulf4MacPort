# Sabre Wulf native-port workbench

**Current result: a rights-safe native prototype, not a completed port of the 1984 game.** The three SwiftUI targets build as separate macOS, iOS and visionOS apps and share a deterministic `GameCore`. The four-room maze, icons, interactions and timing are independently authored placeholders. The original game's loaded code, graphics, room data, audio, rules and winning conditions have **not** been recovered or reproduced.

## Get started

1. Open this repository in VS Code with the recommended [extensions](.vscode/extensions.json). Xcode and its SDKs are required to build Apple app bundles; [build instructions](docs/build.md) include `xcodegen generate`, `swift test` and three `xcodebuild` schemes.
2. Read [Spec.md](Spec.md) for evidence gates and [COPILOT_PROMPT.md](COPILOT_PROMPT.md) for the VS Code Autopilot execution prompt. The prompt expects verified results, not a claim of completion based on this prototype.
3. Keep the user-supplied TZX, candidate snapshots and Spectrum ROM outside the repository. Their hashes, format metadata and unresolved edition/rights status are listed in the [input manifest](reverse_engineering/input-manifest.json). See the [tape investigation](docs/tape-analysis.md) for repeatable metadata-only commands and the unresolved reference-loading problem.
4. Follow the [release QA plan](docs/qa-plan.md). Public CI uses only synthetic tape fixtures and original placeholder UI; no source game media is uploaded.

Do not distribute the original tape, snapshot, Spectrum ROM, extracted game art/audio, or disassembled program from this repository without confirming applicable rights. A faithful native port still needs a proven reference game state and source-backed behavioral comparisons.
