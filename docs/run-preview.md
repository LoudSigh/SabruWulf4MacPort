# Run and observe on this Mac

**Double-click [Run Sabre Wulf Preview.command](../Run%20Sabre%20Wulf%20Preview.command)** in Finder. Alternatively, in a terminal at the repository root:

```sh
./Run\ Sabre\ Wulf\ Preview.command
```

Allow the first build to finish. The launcher checks the hashes of your existing `SNAPSHOTS/Snapshot.z80`, `SNAPSHOTS/Snapshot_GamePlay.z80` and backup `ROMS/48.rom`, generates two PNGs under **ignored, private** `reverse_engineering/private/`, builds the native macOS app, and opens the images in Preview and the app. It does not move or modify the snapshots, copy original media into the app, or commit any disassembly. If a prerequisite is missing or a hash differs, it stops with an explicit error instead of opening a misleading result.

## What you will see

- **Preview:** two authentic but **static** 256×192 frames generated from your 48K snapshots: the menu and one jungle gameplay frame. Zoom the images to inspect them; they are not playable.
- **SabreWulfMac:** a **separately built, interactive prototype** with independently authored maze, movement, items and enemies. Use the on-screen arrows (or keyboard arrows/WASD), Pause and Reset. These mechanics and visuals are placeholders, **not** a finished recreation of the 1984 game.

Use **Command-Tab** to switch between the app and Preview. The images, compiled local snapshot exporter, logs and build products remain under `reverse_engineering/private/`, which Git ignores. Never stage or distribute those outputs or the supplied media.

Requires Xcode with macOS SDK, `xcodegen`, the existing Carbon Neural emulator backup at the path recorded in [Spec.md](../Spec.md), and the two workspace snapshots. The `SPECCY_BACKUP` environment variable can point to a different local copy of the same backup; its 48K ROM still must match the recorded hash. For iOS/visionOS simulator builds rather than this Mac preview, use [build.md](build.md). Neither mobile app bundles original images.
