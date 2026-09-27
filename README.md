# Sabre Wulf native-port workbench

**Current result: a rights-safe native prototype, not a completed port of the 1984 game.** The three SwiftUI targets build as separate macOS, iOS and visionOS apps and share a deterministic `GameCore`. The four-room maze, icons, interactions and timing are independently authored placeholders. The original game's loaded code, graphics, room data, audio, rules and winning conditions have **not** been recovered or reproduced.

## Get started

1. Open this repository in VS Code with the recommended [extensions](.vscode/extensions.json). Xcode and its SDKs are required to build Apple app bundles; [build instructions](docs/build.md) include `xcodegen generate`, `swift test` and three `xcodebuild` schemes.
2. Read [Spec.md](Spec.md) for evidence gates and [COPILOT_PROMPT.md](COPILOT_PROMPT.md) for the VS Code Autopilot execution prompt. The prompt expects verified results, not a claim of completion based on this prototype.
3. Keep the user-supplied TZX, snapshots, AY tune and Spectrum ROM outside the repository. Their hashes, format metadata and unresolved edition/rights status are listed in the [input manifest](reverse_engineering/input-manifest.json). The [menu baseline](reverse_engineering/analysis/menu-reference.json), [in-game baseline](reverse_engineering/analysis/gameplay-reference.json) and [initial RAM map](reverse_engineering/analysis/memory-map.md) enable static comparison. The [tape investigation](docs/tape-analysis.md) gives a repeatable, metadata-only snapshot comparison command and explains why continuous gameplay replay remains unverified.
4. Follow the [release QA plan](docs/qa-plan.md). Public CI uses only synthetic tape fixtures and original placeholder UI; no source game media is uploaded.

For local-only source recovery, use the [private snapshot analysis workflow](docs/local-reverse-engineering.md). It records bounded executable-address/write metadata and can generate RAM/disassembly **only in ignored private paths**; its exploratory trace is not a complete game implementation.

**Never commit or push disassembly, original instruction bytes, raw RAM dumps or extracted game assets.** The user expressly requires keeping disassembly out of GitHub; `.gitignore` excludes the private analysis directories and common listing formats. Do not distribute original tape, snapshot, Spectrum ROM or game art/audio without confirming applicable rights. A faithful native port still needs source-backed behavioral comparisons.
