# Native prototype build

This is an independently authored **placeholder** maze/adventure, not a reconstruction of the historical game. The room layout, collision, patrol, items, health, and timing are illustrative and **unverified** against original mechanics. No original sprites, maps, audio, or game code are included. The historical name appears only as the app title.

For the easiest macOS experience, use [Run Sabre Wulf Preview.command](../Run%20Sabre%20Wulf%20Preview.command) instead of the manual commands below. It opens this prototype alongside your two original **static** snapshot screens, without bundling them in the app.

Requirements: Xcode 27 with macOS, iOS, and visionOS SDKs; XcodeGen 2.46 or later. From the repository root:

```sh
swift test
xcodegen generate
xcodebuild -project SabreWulf.xcodeproj -scheme SabreWulfMac -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SabreWulf.xcodeproj -scheme SabreWulfiOS -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SabreWulf.xcodeproj -scheme SabreWulfVision -configuration Debug -destination 'generic/platform=visionOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Each scheme produces a separate native SwiftUI app backed by the deterministic, UI-independent `GameCore` Swift package. Use the on-screen direction buttons (accessible to VoiceOver and pointer input); on macOS the focused window also accepts arrow keys or WASD. Pause/resume and reset are available on every platform. Leaving the active scene automatically pauses play; resume explicitly on return. Walk through the teal border gates at the center of each side to cross between four rooms; outside the 2×2 area the border blocks travel. The status line and room/health counters describe progress. This prototype intentionally uses no sound.

The **source-backed world explorer and partial movement preview** are in a separate disclosure below the placeholder game. On this Mac, the [preview launcher](../Run%20Sabre%20Wulf%20Preview.command) generates `reverse_engineering/private/snapshot-803e4197989c-world-v2.json`. Expand “Explore source-backed 16 × 16 world”, select “Import your private world data”, and choose that JSON file. The macOS/iOS/visionOS apps all use the same import control; move the private JSON to a device through your own authorized file workflow. It is **never bundled or committed**. Selecting cells or North/West/East/South navigates the structural reference; “Start measured movement (partial)” separately runs a measured subset of the captured player's original movement and static collision, including a validated north passage and return. It does not change the prototype's 2×2 game or implement enemies/combat/other exits. A missing/foreign/corrupt file shows an error rather than invented rooms.
It starts at world position (9,11) in **one-based** UI coordinates—the room in the captured gameplay snapshot, not necessarily the original new-game spawn.
Without a replay, the cyan ring marks the **captured** player coordinate (57,112); importing a replay moves the cyan ring along recorded positions. Starting measured movement adds a separate pink ring driven by the bounded native movement slice; it does not attack or implement a complete original player.
The preview launcher also prepares eight private replays, including `reverse_engineering/private/replay-q-100.json`, `reverse_engineering/private/replay-upper-exit-180.json`, `reverse_engineering/private/replay-round-trip-200.json` and the provisional `reverse_engineering/private/replay-west-exit-256.json`. After importing world data, use “Import a private gameplay replay (optional)” to scrub the recorded player's room/X/Y. These observations are **read-only** and run alongside the measured movement preview and placeholder game. The west exit has not passed independent late-input emulator parity.
For the west replay only, the launcher also prepares the private `reverse_engineering/private/west-entity-trace.json`. Import it after the matching replay to compare one moving entity's manual and unmodified-emulator positions as orange/purple markers. Replay/trace actor frames are checked for equality on import; markers do not provide native enemy simulation.

If you have permission for the locally downloaded artwork, the explorer offers an **optional** “Preview private background images” folder picker. Select `SNAPSHOTS/backgrounds/` (or its authorized device-local copy). It overlays available images on their source placement coordinates. Backgrounds are **not bundled**; blending and room rendering are approximate, with a visible count for missing images. The current local set covers 40 of 41 background references. Do not interpret this overlay as the complete 1984 collision or sprite renderer.

The iOS target generates a launch screen so modern devices use the full screen rather than a legacy letterboxed viewport. The shared view scrolls when the board and controls do not fit vertically; it caps the board width to the available window. The Xcode project is generated from `project.yml`; rerun `xcodegen generate` after changing target settings. A public build includes only independently authored placeholders and is **not** a faithful Sabre Wulf release.

## Manual simulator smoke checks

- **Movement and collision:** Move into an interior gray wall and confirm position stays put; move through a teal center gate into a neighboring room. At the outer edge, movement must stop.
- **Items and patrol:** Reach a yellow marker and confirm the item count increments once. Touch the orange patrol and confirm health decreases, then the player respawns.
- **Pause and lifecycle:** Pause, try moving, then resume; background and reopen the app and confirm it remains paused. Reset and confirm room, health, and items return to their initial state.
- **Accessibility:** With VoiceOver on, navigate to the four labeled Move buttons, Pause/Resume, Reset, and the board summary; activate each control. On macOS also check arrow keys and WASD with the game view focused.
