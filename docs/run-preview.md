# Run and observe on this Mac

**Double-click [Run Sabre Wulf Preview.command](../Run%20Sabre%20Wulf%20Preview.command)** in Finder. Alternatively, in a terminal at the repository root:

```sh
./Run\ Sabre\ Wulf\ Preview.command
```

Allow the first build to finish. The launcher checks the hashes of your existing `SNAPSHOTS/Snapshot.z80`, `SNAPSHOTS/Snapshot_GamePlay.z80` and backup `ROMS/48.rom`, generates two PNGs, a 16×16 room-type overview, measured room bounds, and seven recorded input replays under **ignored, private** `reverse_engineering/private/`. It builds the native macOS app and opens the images in Preview, the map in a browser, and the app. It does not move or modify the snapshots, copy original media into the app, or commit any disassembly. If a prerequisite is missing or a hash differs, it stops with an explicit error instead of opening a misleading result.

## What you will see

- **Preview:** two authentic but **static** 256×192 frames generated from your 48K snapshots: the menu and one jungle gameplay frame. Zoom the images to inspect them; they are not playable.
- **Browser:** a **private 16×16 world-type overview**, derived from the two matching snapshots. Repeated numbers/colors identify reusable room templates, not full original room art. It is structural and not playable.
- **SabreWulfMac:** an **interactive prototype** with independently authored maze, movement, items and enemies. Use the on-screen arrows (or keyboard arrows/WASD), Pause and Reset. This main game is a placeholder, **not** a finished recreation of the 1984 game.
- **Inside SabreWulfMac:** expand “Explore source-backed 16 × 16 world” below the prototype controls, click “Import your private world data”, and select `reverse_engineering/private/snapshot-803e4197989c-world-v2.json`. You can browse all 256 original room positions with placement markers and measured orange background outlines. Select **Start measured movement (partial)** to move the pink marker through imported room geometry at 50 frames per second (or step one frame); pick a held Q/W/E/R action, then Play/Pause/Reset. This starts from the in-game capture and includes static collision plus the measured north passage and return; unverified exits pause with an error. It is separate from the placeholder main game and lacks combat, enemies, quest and complete art.
- Import `reverse_engineering/private/replay-upper-exit-180.json` with “Import a private gameplay replay (optional)” to scrub the **recorded** W/E path (cyan marker) that crosses from room ID 168 to room ID 152 at frame 68; alternatively choose `reverse_engineering/private/replay-q-100.json` for a shorter leftward path. The measured preview and the recorded replay have distinct markers and a frame-indexed position comparison. To reproduce the W/E path, start the movement preview, advance 20 frames with None, hold W for 10 frames, then hold E through frame 180. This is only a bounded playable movement slice, not a full native game simulation.
- Select `reverse_engineering/private/replay-round-trip-200.json` to scrub a second path that returns to room ID 168 at frame 88 (X=121/Y=190), then rebases to X=120/Y=39 at frame 94. Reproduce it with None for 20 frames, W for 10, E through frame 75, and R through frame 200; it too is only a verified movement slice.
- Four further private replays named `hold-q-150.json`, `hold-w-150.json`, `hold-e-150.json` and `hold-r-150.json` compare 150 frames each. Starting from frame zero, leave None selected for 20 frames and hold the matching key for the remaining 130. The native movement subset matched room/X/Y for all 980 frames across these four holds and the two multi-key paths; other interactions are not validated.
- If you have already made a permitted local copy of the backgrounds, choose “Preview private background images” and select `SNAPSHOTS/backgrounds/`. The preview is **optional**, partial and approximately blended; the app never bundles those PNGs.

Use **Command-Tab** to switch between the app and Preview. The images, compiled local snapshot exporter, logs and build products remain under `reverse_engineering/private/`, which Git ignores. Never stage or distribute those outputs or the supplied media.

Requires Xcode with macOS SDK, `xcodegen`, the existing Carbon Neural emulator backup at the path recorded in [Spec.md](../Spec.md), and the two workspace snapshots. The `SPECCY_BACKUP` environment variable can point to a different local copy of the same backup; its 48K ROM still must match the recorded hash. For iOS/visionOS simulator builds rather than this Mac preview, use [build.md](build.md). Neither mobile app bundles original images.
