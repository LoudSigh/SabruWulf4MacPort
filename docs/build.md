# Native prototype build

This is an independently authored **placeholder** maze/adventure, not a reconstruction of the historical game. The room layout, collision, patrol, items, health, and timing are illustrative and **unverified** against original mechanics. No original sprites, maps, audio, or game code are included. The historical name appears only as the app title.

Requirements: Xcode 27 with macOS, iOS, and visionOS SDKs; XcodeGen 2.46 or later. From the repository root:

```sh
swift test
xcodegen generate
xcodebuild -project SabreWulf.xcodeproj -scheme SabreWulfMac -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SabreWulf.xcodeproj -scheme SabreWulfiOS -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SabreWulf.xcodeproj -scheme SabreWulfVision -configuration Debug -destination 'generic/platform=visionOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Each scheme produces a separate native SwiftUI app backed by the deterministic, UI-independent `GameCore` Swift package. Use the on-screen direction buttons (accessible to VoiceOver and pointer input); on macOS the focused window also accepts arrow keys or WASD. Pause/resume and reset are available on every platform. Leaving the active scene automatically pauses play; resume explicitly on return. Walk through the teal border gates at the center of each side to cross between four rooms; outside the 2×2 area the border blocks travel. The status line and room/health counters describe progress. This prototype intentionally uses no sound.

The iOS target generates a launch screen so modern devices use the full screen rather than a legacy letterboxed viewport. The shared view scrolls when the board and controls do not fit vertically; it caps the board width to the available window. The Xcode project is generated from `project.yml`; rerun `xcodegen generate` after changing target settings. A public build includes only independently authored placeholders and is **not** a faithful Sabre Wulf release.

## Manual simulator smoke checks

- **Movement and collision:** Move into an interior gray wall and confirm position stays put; move through a teal center gate into a neighboring room. At the outer edge, movement must stop.
- **Items and patrol:** Reach a yellow marker and confirm the item count increments once. Touch the orange patrol and confirm health decreases, then the player respawns.
- **Pause and lifecycle:** Pause, try moving, then resume; background and reopen the app and confirm it remains paused. Reset and confirm room, health, and items return to their initial state.
- **Accessibility:** With VoiceOver on, navigate to the four labeled Move buttons, Pause/Resume, Reset, and the board summary; activate each control. On macOS also check arrow keys and WASD with the game view focused.
