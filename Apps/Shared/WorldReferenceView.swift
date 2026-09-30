import Combine
import CoreGraphics
import GameCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
private typealias WorldRaster = NSImage
#else
import UIKit
private typealias WorldRaster = UIImage
#endif

private enum SpriteImportError: Error, LocalizedError {
    case noUsableSamples

    var errorDescription: String? {
        "No correctly sized silhouette samples (10.png or 15.png) were found in the selected folder."
    }
}

private enum BackgroundPreviewError: Error, LocalizedError {
    case imageCreation

    var errorDescription: String? {
        "Could not prepare a private source background preview image."
    }
}

private enum LocalReferenceLaunchError: Error, LocalizedError {
    case missingDirectory

    var errorDescription: String? {
        "Pass a directory after --local-reference-dir, or use the local folder import button."
    }
}

struct WorldReferenceView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var world: WorldReference?
    @State private var selected = WorldReference.capturedGameplayRoom
    @State private var importing = false
    @State private var importingBundle = false
    @State private var importingArtwork = false
    @State private var importError: String?
    @State private var art: [Int: WorldRaster] = [:]
    @State private var artStatus: String?
    @State private var importingBackgroundAtlas = false
    @State private var backgroundAtlas: BackgroundAtlas?
    @State private var sourceRoomImages: [Int: CGImage] = [:]
    @State private var sourceAttributeColors = false
    @State private var importingSprites = false
    @State private var spriteSamples: [Int: WorldRaster] = [:]
    @State private var importingAtlas = false
    @State private var spriteAtlas: SpriteAtlas?
    @State private var importingPlacement = false
    @State private var placementState: CapturedPlacementState?
    @State private var showActorSprite = true
    @State private var spriteID = 16.0
    @State private var importingReplay = false
    @State private var replay: ReferenceReplay?
    @State private var replayFrameValue = 0.0
    @State private var importingEntityTrace = false
    @State private var entityTrace: ReferenceEntityTrace?
    @State private var movement: CapturedMovementState?
    @State private var movementOrigin: CapturedMovementOrigin = .gameplayCapture
    @State private var heldKey = "none"
    @State private var playingMovement = false
    @State private var exploration: ExperimentalWorldGame?
    @State private var explorationHeldKey = "none"
    @State private var playingExploration = false
    @State private var explorationError: String?
    @State private var showExplorationMap = false
    #if os(macOS)
    @State private var checkedLaunchArguments = false
    @FocusState private var explorationKeyboardFocused: Bool
    #endif

    private let movementTimer = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect()

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 17), spacing: 2), count: 16
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1984 world structure")
                .font(.headline)
            Text(
                "Play an opt-in experimental world mode with local artwork and record pickups, "
                    + "or inspect the read-only reference replays and strictly measured movement preview."
            )
            .font(.caption)
            Text("Original keyboard reference: Q left · W right · E up · R down · T fire (not bound to this viewer)")
                .font(.caption)
            Button("Import local reference folder (world, art and replay)") {
                importingBundle = true
            }
            .buttonStyle(.borderedProminent)
            Button("Import your private world data") { importing = true }
                .buttonStyle(.bordered)
            if let importError {
                Text(importError)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Import failed: \(importError)")
            }
            if let world, let placementState, world.schemaVersion == 2 {
                if let exploration {
                    Text(
                        "World play · room \(exploration.room.y * 16 + exploration.room.x)"
                            + " · X \(exploration.player.x), Y \(exploration.player.y)"
                            + " · 1UP \(exploration.scores.first.decimalValue)"
                            + " · records \(exploration.collectedRecordIDs.count)/4"
                    )
                    .font(.subheadline.monospacedDigit())
                    .accessibilityAddTraits(.updatesFrequently)
                    Text(
                        "Experimental gameplay: the world geometry and checked movement slice "
                            + "are source-backed; other exits and automatic pickup timing are inferred. "
                            + "Enemies, sword combat and the earned ending are not implemented."
                    )
                    .font(.caption)
                    Picker("Travel direction", selection: $explorationHeldKey) {
                        Text("None").tag("none")
                        Text("Q · left").tag("q")
                        Text("W · right").tag("w")
                        Text("E · up").tag("e")
                        Text("R · down").tag("r")
                    }
                    HStack {
                        Button(playingExploration ? "Stop travel" : "Travel at 50 Hz") {
                            playingExploration.toggle()
                        }
                        .disabled(exploration.paused)
                        Button(exploration.paused ? "Resume" : "Pause") {
                            self.exploration?.togglePause()
                            playingExploration = false
                        }
                        Button("Restart world") {
                            startExploration(world: world, placements: placementState)
                        }
                        Button("Exit world") {
                            playingExploration = false
                            self.exploration = nil
                        }
                    }
                    .buttonStyle(.bordered)
                    VStack(spacing: 4) {
                        explorationButton("Up", symbol: "arrow.up", action: .up)
                        HStack {
                            explorationButton("Left", symbol: "arrow.left", action: .left)
                            explorationButton("Down", symbol: "arrow.down", action: .down)
                            explorationButton("Right", symbol: "arrow.right", action: .right)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(exploration.paused)
                    Text("Tap a direction to move; choose a direction and Travel for continuous play. On Mac, focus the explorer and use arrows or Q/W/E/R.")
                        .font(.caption)
                } else {
                    Button("Play the experimental 16 × 16 world") {
                        startExploration(world: world, placements: placementState)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            if let explorationError {
                Text(explorationError)
                    .foregroundStyle(.red)
                    .accessibilityLabel("World play error: \(explorationError)")
            }
            if world != nil {
                if world?.schemaVersion == 2 {
                    if let movement {
                        Text(movementSummary(movement))
                        .font(.caption.monospacedDigit())
                        Picker("Held original key", selection: $heldKey) {
                            Text("None").tag("none")
                            Text("Q · left").tag("q")
                            Text("W · right").tag("w")
                            Text("E · up").tag("e")
                            Text("R · down").tag("r")
                        }
                        HStack {
                            Button("Step frame") { advanceMovement() }
                                .accessibilityLabel("Step one measured frame")
                            Button(playingMovement ? "Pause" : "Play") {
                                playingMovement.toggle()
                            }
                            .accessibilityLabel(
                                playingMovement ? "Pause measured movement" : "Play measured movement"
                            )
                            Button("Reset") { resetMovement() }
                                .accessibilityLabel("Reset measured movement")
                        }
                        .buttonStyle(.bordered)
                        if movementOrigin == .observedNewGameReady {
                            Text("Post-setup slice only: begins after source frame 790. Keep one Q/W/E direction for 60 frames, then None for 50 (frames 791–900). R/down is checked only through frame 866 and pauses before the unexplained next step. With a private sprite atlas, pink shapes show checked bitmap IDs in approximate color. Menu polling, enemies and most exits are not simulated.")
                                .font(.caption)
                            Text("One measured direction change is also supported: W for 18 frames, E for 42, then None for 50. Position matches through frame 900; the pink bitmap ID is hidden after frame 866 because its later phase is unverified.")
                                .font(.caption)
                            Text("A bounded reversal is supported: W for 18 frames, Q for 42, then None for 20. Position matches through frame 870; the sprite ID is hidden after frame 850. Playback stops before unmodeled injury-state motion after source contact.")
                                .font(.caption)
                            Text("A separate source-safe route is E for 40 frames, then Q for 91: room transitions at frames 819 and 895, and room/position/sprite ID match through frame 921. Playback stops before injury after the source contact at frame 921. Import the matching 1,050-frame E/Q private replay to compare.")
                                .font(.caption)
                            if let replay, replay.frames.count < 900 {
                                Text("This shorter replay cannot compare the full post-setup slice; import the private 900-frame late-W replay.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text("Partial movement: north/return match the independent reference; west/east passages are provisional because enemy paths differ. No native enemies, combat, items or other validated exits. Playback pauses on unsupported behavior.")
                            .font(.caption)
                        HStack {
                            Button("Use gameplay capture start") {
                                resetMovement(origin: .gameplayCapture)
                            }
                            Button("Use observed new-game ready start") {
                                resetMovement(origin: .observedNewGameReady)
                            }
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Start measured movement (partial)") {
                            resetMovement(origin: .gameplayCapture)
                        }
                        Button("Start after observed new-game setup (partial)") {
                            resetMovement(origin: .observedNewGameReady)
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text("Legacy world export: topology only, without source integrity or measured bounds. Regenerate from the verified snapshots for movement and artwork.")
                        .font(.caption)
                }
                Button("Import a private gameplay replay (optional)") {
                    importingReplay = true
                }
                .buttonStyle(.bordered)
                if let replay {
                    let frame = replay.frames[min(Int(replayFrameValue), replay.frames.count - 1)]
                    let input = replay.schedule?.first {
                        $0.startFrame <= frame.index - 1 && frame.index - 1 < $0.endFrame
                    }.map(\.key) ?? (replay.schedule == nil ? replay.input : "none")
                    Text(replay.frameBoundaryMode == "reference-relative"
                        ? "Reference-relative frame timing (verify source provenance separately)"
                        : "Legacy absolute-frame timing (dynamic actors may diverge)")
                        .font(.caption)
                    Text(
                        "Recorded actor RAM · \(input.uppercased()) · frame \(frame.index) "
                            + "· room \(frame.playerRoomID) · X \(frame.playerX), Y \(frame.playerY)"
                            + " · source life byte \(frame.reportedLives)"
                            + (frame.playerKind.map { " · actor state \($0)" } ?? "")
                    )
                    .font(.caption.monospacedDigit())
                    if let score = frame.recordedScoreSummary {
                        Text(score).font(.caption.monospacedDigit())
                    }
                    Text("After a return to the menu, these retained RAM bytes are not an active player or a rendered replay screen.")
                        .font(.caption)
                    Slider(
                        value: $replayFrameValue,
                        in: 0...Double(replay.frames.count - 1),
                        step: 1
                    )
                    .accessibilityLabel("Reference replay frame")
                    .onChange(of: replayFrameValue) { _, value in
                        let id = replay.frames[Int(value)].playerRoomID
                        selected = RoomID(id % 16, id / 16)
                    }
                    if let spriteAtlas, let kind = frame.playerKind {
                        switch Result(catching: { try spriteAtlas.mask(at: kind) }) {
                        case .success(let mask?):
                            Text("Recorded actor-state \(kind) · decoded silhouette only")
                                .font(.caption)
                            NativeSpritePreview(mask: mask)
                        case .success(nil):
                            Text("Recorded actor-state \(kind) has no bitmap.")
                                .font(.caption)
                        case .failure(let error):
                            Text(error.localizedDescription)
                                .foregroundStyle(.red)
                        }
                    }
                    if let movement,
                       (1...replay.frames.count).contains(
                           movement.frame + movement.referenceFrameOffset
                       ) {
                        let sourceFrame = movement.frame + movement.referenceFrameOffset
                        let expected = replay.frames[sourceFrame - 1]
                        let matches = expected.playerRoomID == movement.room.y * 16 + movement.room.x
                            && expected.playerX == movement.player.x
                            && expected.playerY == movement.player.y
                        Text(
                            "Measured source frame \(sourceFrame) vs imported replay: "
                                + (matches ? "actor position matches" : "actor position differs")
                        )
                        .font(.caption)
                        .foregroundStyle(matches ? Color.green : Color.orange)
                    }
                    Button("Import private actor route comparison (optional)") {
                        importingEntityTrace = true
                    }
                    .buttonStyle(.bordered)
                    if let entityFrame = currentEntityFrame {
                        Text(entitySummary(entityFrame))
                            .font(.caption.monospacedDigit())
                        if entityTrace?.observedSlot == 18 {
                            Text(spriteAtlas == nil
                                ? "Import the matching private sprite atlas to see the recorded W-frame actor overlap."
                                : "In W frames 43–53, the recorded player bitmap uses a source-checked two-actor XOR silhouette. Color and general sprite layering remain unverified; this is not native actor AI.")
                                .font(.caption)
                        }
                    }
                }
                Button("Preview private background images (optional)") {
                    importingArtwork = true
                }
                .buttonStyle(.bordered)
                Text(
                    backgroundAtlas != nil
                        ? "Private source shapes take precedence over imported PNG overlays."
                        : (artStatus ?? "Markers and measured outlines (if available) show placements; no original art is bundled.")
                )
                .font(.caption)
                Button("Import private snapshot backgrounds (optional)") {
                    importingBackgroundAtlas = true
                }
                .buttonStyle(.bordered)
                if backgroundAtlas != nil {
                    Toggle(
                        "Preview 48K attribute colors (approximate)",
                        isOn: $sourceAttributeColors
                    )
                    Text(sourceAttributeColors
                        ? "Source ink/paper colors; background order, transparency and FLASH timing remain unverified."
                        : "41 private source bitmaps displayed as monochrome geometry.")
                        .font(.caption)
                }
                Button("Preview private sprite silhouettes (optional)") {
                    importingSprites = true
                }
                .buttonStyle(.bordered)
                if !spriteSamples.isEmpty {
                    HStack(alignment: .bottom) {
                        ForEach([16, 21], id: \.self) { index in
                            if let sample = spriteSamples[index] {
                                VStack {
                                    image(for: sample)
                                        .resizable()
                                        .interpolation(.none)
                                        .frame(width: 64, height: sample.size.height)
                                        .accessibilityLabel("Private sprite sample \(index)")
                                    Text("Sample \(index)")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    Text("Local shape samples only; palette, animation and room placement are not validated.")
                        .font(.caption)
                }
                Button("Import your private snapshot sprite atlas (optional)") {
                    importingAtlas = true
                }
                .buttonStyle(.bordered)
                if let spriteAtlas {
                    Toggle("Show private player silhouettes in room", isOn: $showActorSprite)
                    Text("White is recorded source RAM; pink is measured post-setup movement with checked bitmap IDs. Both use bottom Y; other actors and color attributes remain approximate.")
                        .font(.caption)
                    Slider(value: $spriteID, in: 0...195, step: 1)
                        .accessibilityLabel("Original sprite pointer ID")
                    let id = Int(spriteID)
                    switch Result(catching: { try spriteAtlas.mask(at: id) }) {
                    case .success(let mask?):
                        Text("Snapshot silhouette \(id) · \(mask.width) × \(mask.height) pixels")
                            .font(.caption.monospacedDigit())
                        NativeSpritePreview(mask: mask)
                    case .success(nil):
                        Text("Sprite ID \(id) uses the empty source sentinel.")
                            .font(.caption)
                    case .failure(let error):
                        Text(error.localizedDescription)
                            .foregroundStyle(.red)
                    }
                    Text("Private monochrome bitmap only; palette and animation order are unverified.")
                        .font(.caption)
                    Button("Import four private actor records (optional)") {
                        importingPlacement = true
                    }
                    .buttonStyle(.bordered)
                    if let placementState {
                        Text("Four source records captured at frame \(placementState.sourceFrame). Separate edited-RAM tests found distinct progress bits and 7,500 points for each, but these purple markers are read-only placements, not natural pickups or a proven amulet/ending rule.")
                            .font(.caption)
                        ForEach(placementState.records, id: \.id) { record in
                            Button("Inspect private record \(record.id + 1) · room \(record.roomID)") {
                                selected = RoomID(record.roomID % 16, record.roomID / 16)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            if let world {
                Text(
                    "Position \(selected.x + 1), \(selected.y + 1) of 16 × 16 "
                        + "· template \(world.roomType(at: selected) ?? 0)"
                )
                .font(.subheadline.monospacedDigit())

                if exploration != nil {
                    Button(showExplorationMap ? "Hide world map" : "Show world map") {
                        showExplorationMap.toggle()
                    }
                    .buttonStyle(.bordered)
                }
                if exploration == nil || showExplorationMap {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(0..<256, id: \.self) { index in
                            let position = RoomID(index % 16, index / 16)
                            let roomType = world.roomType(at: position) ?? 0
                            Button {
                                selected = position
                            } label: {
                                ZStack {
                                    Rectangle()
                                        .fill(
                                            position == selected
                                                ? Color.yellow : Color.teal.opacity(0.3 + Double(roomType % 4) * 0.12)
                                        )
                                    if hasPrivateRecord(in: position) {
                                        Circle()
                                            .fill(.purple)
                                            .padding(4)
                                    }
                                }
                                .aspectRatio(1, contentMode: .fit)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                "Column \(position.x + 1), row \(position.y + 1), "
                                    + "template \(roomType)"
                                    + (hasPrivateRecord(in: position)
                                        ? ", source record at imported frame" : "")
                            )
                        }
                    }
                    .frame(maxWidth: 470)
                    .accessibilityElement(children: .contain)
                }
                if exploration == nil {
                    HStack {
                        stepButton("North", .north)
                        stepButton("West", .west)
                        stepButton("East", .east)
                        stepButton("South", .south)
                    }
                    .buttonStyle(.bordered)
                }
                let placements = world.rooms[world.roomType(at: selected) ?? 0].placements
                Text("\(placements.count) source background placements in this room template")
                    .font(.caption)
                GeometryReader { area in
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(.teal.opacity(0.12))
                        if sourceAttributeColors,
                           let sourceImage = sourceRoomImages[world.roomType(at: selected) ?? 0] {
                            Image(decorative: sourceImage, scale: 1)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: area.size.width, height: area.size.height)
                        }
                        ForEach(placements.indices, id: \.self) { index in
                            let placement = placements[index]
                            if !sourceAttributeColors || sourceRoomImages.isEmpty {
                                backgroundGraphic(placement, size: area.size)
                            }
                            if let width = placement.widthPixels,
                               let height = placement.heightPixels {
                                Rectangle()
                                    .stroke(.orange.opacity(0.8), lineWidth: 1)
                                    .frame(
                                        width: CGFloat(width) * area.size.width / 256,
                                        height: CGFloat(height) * area.size.height / 192
                                    )
                                    .position(
                                        x: (CGFloat(placement.x) + CGFloat(width) / 2)
                                            * area.size.width / 256,
                                        y: (screenY(placement.y) + CGFloat(height) / 2)
                                            * area.size.height / 192
                                    )
                            }
                        }
                        if exploration == nil {
                            recordedPlayerSprite(in: area.size)
                            measuredPlayerSprite(in: area.size)
                        } else {
                            exploratoryPlayerSprite(in: area.size)
                        }
                        ForEach(selectedPrivateRecords, id: \.id) { record in
                            Circle()
                                .stroke(.purple, lineWidth: 2)
                                .frame(width: 12, height: 12)
                                .position(
                                    x: CGFloat(record.x) * area.size.width / 256,
                                    y: screenY(record.y) * area.size.height / 192
                                )
                                .accessibilityLabel(
                                    "Source record \(record.id + 1) at X \(record.x), Y \(record.y), from imported frame; natural collection unverified"
                                )
                        }
                        if exploration == nil, let position = markerPosition {
                            Circle()
                                .stroke(.cyan, lineWidth: 2)
                                .frame(width: 12, height: 12)
                                .position(
                                    x: CGFloat(position.x)
                                        * area.size.width / 256,
                                    y: screenY(position.y)
                                        * area.size.height / 192
                                )
                                .accessibilityLabel("Recorded actor position bytes; may be stale after returning to the menu")
                        }
                        if exploration == nil, let position = movementMarkerPosition {
                            Circle()
                                .stroke(.pink, lineWidth: 2)
                                .frame(width: 16, height: 16)
                                .position(
                                    x: CGFloat(position.x) * area.size.width / 256,
                                    y: screenY(position.y) * area.size.height / 192
                                )
                                .accessibilityLabel("Measured movement position")
                        }
                        if exploration == nil {
                            referenceEntityMarker(
                                currentEntityFrame?.manualEntity, in: selected,
                                size: area.size, color: .orange,
                                label: "Manual CPU recorded actor"
                            )
                            referenceEntityMarker(
                                currentEntityFrame?.fullEmulatorEntity, in: selected,
                                size: area.size, color: .purple,
                                label: "Unmodified emulator recorded actor"
                            )
                        }
                    }
                }
                .aspectRatio(256.0 / 192.0, contentMode: .fit)
                .frame(maxWidth: 470)
                .accessibilityLabel(
                    roomSummary(
                        template: world.roomType(at: selected) ?? 0,
                        placements: placements.count
                    )
                )
            }
        }
        .fileImporter(
            isPresented: $importingBundle,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                try loadReferenceBundle(from: url)
            } catch {
                importError = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   size > 2_000_000 {
                    throw WorldReferenceError.unsupportedFormat
                }
                let imported = try WorldReference.load(from: Data(contentsOf: url))
                world = imported
                selected = WorldReference.capturedGameplayRoom
                art = [:]
                artStatus = nil
                backgroundAtlas = nil
                sourceRoomImages = [:]
                sourceAttributeColors = false
                spriteSamples = [:]
                spriteAtlas = nil
                placementState = nil
                spriteID = 16
                replay = nil
                entityTrace = nil
                replayFrameValue = 0
                movement = nil
                movementOrigin = .gameplayCapture
                playingMovement = false
                exploration = nil
                playingExploration = false
                explorationError = nil
                heldKey = "none"
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $importingArtwork,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first, let world else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let addresses = Set(world.rooms.flatMap(\.placements).map(\.graphicAddress))
                var imported: [Int: WorldRaster] = [:]
                for address in addresses {
                    let file = url.appendingPathComponent("background-\(address).png")
                    guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                          size <= 2_000_000,
                          let data = try? Data(contentsOf: file),
                          let raster = WorldRaster(data: data),
                          raster.size.width > 0, raster.size.height > 0,
                          raster.size.width <= 4096, raster.size.height <= 4096
                    else {
                        continue
                    }
                    imported[address] = raster
                }
                guard !imported.isEmpty else {
                    throw WorldReferenceError.unsupportedFormat
                }
                art = imported
                artStatus =
                    "Loaded \(imported.count) of \(addresses.count) locally supplied images. "
                    + "Overlaps are approximated; original composition is not yet verified."
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $importingBackgroundAtlas,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first, let world else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   size > 100_000 {
                    throw BackgroundAtlasError.unsupportedFormat
                }
                let imported = try BackgroundAtlas.load(from: Data(contentsOf: url))
                try imported.validate(world: world)
                let images = try makeSourceRoomImages(world: world, atlas: imported)
                backgroundAtlas = imported
                sourceRoomImages = images
                sourceAttributeColors = false
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $importingSprites,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first, world != nil else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                var samples: [Int: WorldRaster] = [:]
                for (index, filename, width, height) in [
                    (16, "10.png", 64, 84), (21, "15.png", 64, 88)
                ] {
                    let file = url.appendingPathComponent(filename)
                    guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                          size <= 200_000,
                          let data = try? Data(contentsOf: file),
                          let image = WorldRaster(data: data),
                          image.size.width == CGFloat(width),
                          image.size.height == CGFloat(height) else {
                        continue
                    }
                    samples[index] = image
                }
                guard !samples.isEmpty else {
                    throw SpriteImportError.noUsableSamples
                }
                spriteSamples = samples
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $importingAtlas,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first, world != nil else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   size > 100_000 {
                    throw SpriteAtlasError.unsupportedFormat
                }
                spriteAtlas = try SpriteAtlas.load(from: Data(contentsOf: url))
                placementState = nil
                exploration = nil
                playingExploration = false
                spriteID = 16
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $importingPlacement,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first, let world else {
                    throw CocoaError(.fileNoSuchFile)
                }
                guard let spriteAtlas else {
                    throw CapturedPlacementError.missingSprite
                }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   size > 32_000 {
                    throw CapturedPlacementError.unsupportedFormat
                }
                let imported = try CapturedPlacementState.load(
                    from: Data(contentsOf: url), world: world
                )
                try imported.validate(spriteAtlas: spriteAtlas)
                placementState = imported
                exploration = nil
                playingExploration = false
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $importingReplay,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first, world != nil else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   size > 2_000_000 {
                    throw ReferenceReplayError.unsupportedFormat
                }
                let imported = try ReferenceReplay.load(from: Data(contentsOf: url))
                replay = imported
                entityTrace = nil
                let desiredIndex = movement.map {
                    $0.frame + $0.referenceFrameOffset - 1
                } ?? 0
                let replayIndex = min(max(desiredIndex, 0), imported.frames.count - 1)
                replayFrameValue = Double(replayIndex)
                let room = imported.frames[replayIndex].playerRoomID
                selected = RoomID(room % 16, room / 16)
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
        }

        .fileImporter(
            isPresented: $importingEntityTrace,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first, let replay else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   size > 2_000_000 {
                    throw ReferenceEntityTraceError.unsupportedFormat
                }
                let imported = try ReferenceEntityTrace.load(from: Data(contentsOf: url))
                try imported.validate(replay: replay)
                entityTrace = imported
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
        }

        .onReceive(movementTimer) { _ in
            if scenePhase == .active {
                if playingExploration {
                    advanceExploration(held: explorationHeldKey)
                } else if playingMovement {
                    advanceMovement()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                playingExploration = false
                playingMovement = false
            }
        }
        .onDisappear {
            playingMovement = false
            playingExploration = false
        }
        .onAppear {
            #if os(macOS)
            importLaunchReferenceIfNeeded()
            #endif
        }
        #if os(macOS)
        .focusable()
        .focused($explorationKeyboardFocused)
        .onKeyPress { press in
            guard exploration != nil else { return .ignored }
            let action: OriginalAction?
            switch press.key {
            case .leftArrow: action = .left
            case .rightArrow: action = .right
            case .upArrow: action = .up
            case .downArrow: action = .down
            default:
                action = press.characters.first.flatMap {
                    OriginalAction.fromSpectrumKey($0)
                }
            }
            guard let action, action != .fire else { return .ignored }
            stepExploration(action)
            return .handled
        }
        #endif
    }

    private func makeSourceRoomImages(
        world: WorldReference, atlas: BackgroundAtlas
    ) throws -> [Int: CGImage] {
        var images: [Int: CGImage] = [:]
        for template in world.rooms.indices {
            let scene = try BackgroundScene(world: world, atlas: atlas, template: template)
            guard let provider = CGDataProvider(data: Data(scene.rgba) as CFData),
                  let image = CGImage(
                      width: BackgroundScene.width, height: BackgroundScene.height,
                      bitsPerComponent: 8, bitsPerPixel: 32,
                      bytesPerRow: BackgroundScene.width * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGBitmapInfo(
                          rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                      ),
                      provider: provider, decode: nil,
                      shouldInterpolate: false, intent: .defaultIntent
                  ) else {
                throw BackgroundPreviewError.imageCreation
            }
            images[template] = image
        }
        return images
    }

    private func loadReferenceBundle(from url: URL) throws {
        let bundle = try PrivateReferenceBundle.load(from: url)
        let images = try makeSourceRoomImages(
            world: bundle.world, atlas: bundle.backgrounds
        )
        world = bundle.world
        selected = WorldReference.capturedGameplayRoom
        art = [:]
        artStatus = nil
        backgroundAtlas = bundle.backgrounds
        sourceRoomImages = images
        sourceAttributeColors = false
        spriteSamples = [:]
        spriteAtlas = bundle.sprites
        placementState = bundle.placements
        spriteID = 16
        replay = bundle.replay
        replayFrameValue = 0
        entityTrace = nil
        movement = nil
        movementOrigin = .gameplayCapture
        playingMovement = false
        exploration = nil
        playingExploration = false
        explorationError = nil
        heldKey = "none"
        importError = nil
    }

    #if os(macOS)
    private func importLaunchReferenceIfNeeded() {
        guard !checkedLaunchArguments else { return }
        checkedLaunchArguments = true
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--local-reference-dir") else {
            if arguments.contains("--play-experimental-world") {
                importError = LocalReferenceLaunchError.missingDirectory.localizedDescription
            }
            return
        }
        do {
            guard arguments.indices.contains(index + 1),
                  !arguments[index + 1].hasPrefix("--") else {
                throw LocalReferenceLaunchError.missingDirectory
            }
            let directory = URL(
                fileURLWithPath: arguments[index + 1], isDirectory: true
            )
            try loadReferenceBundle(from: directory)
            if arguments.contains("--play-experimental-world"),
               let world, let placementState {
                startExploration(world: world, placements: placementState)
            }
        } catch {
            importError = error.localizedDescription
        }
    }
    #endif

    private var movementMarkerPosition: GridPoint? {
        guard let movement, selected == movement.room else { return nil }
        return movement.player
    }

    @ViewBuilder
    private func backgroundGraphic(
        _ placement: WorldPlacement, size: CGSize
    ) -> some View {
        if let backgroundAtlas {
            switch Result(catching: { try backgroundAtlas.mask(at: placement.graphicAddress) }) {
            case .success(let mask):
                NativeBackgroundPreview(
                    mask: mask, useAttributes: sourceAttributeColors
                )
                    .frame(
                        width: CGFloat(mask.width) * size.width / 256,
                        height: CGFloat(mask.height) * size.height / 192
                    )
                    .position(
                        x: (CGFloat(placement.x) + CGFloat(mask.width) / 2) * size.width / 256,
                        y: (screenY(placement.y) + CGFloat(mask.height) / 2)
                            * size.height / 192
                    )
            case .failure(let error):
                Text(error.localizedDescription)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        } else if let graphic = art[placement.graphicAddress] {
            image(for: graphic)
                .resizable()
                .interpolation(.none)
                .frame(
                    width: graphic.size.width / 4 * size.width / 256,
                    height: graphic.size.height / 4 * size.height / 192
                )
                .blendMode(.screen)
                .position(
                    x: (CGFloat(placement.x) + graphic.size.width / 8) * size.width / 256,
                    y: (screenY(placement.y) + graphic.size.height / 8)
                        * size.height / 192
                )
        } else {
            Circle()
                .fill(.yellow)
                .frame(width: 7, height: 7)
                .position(
                    x: (CGFloat(placement.x) + 4) * size.width / 256,
                    y: (screenY(placement.y) + 4) * size.height / 192
                )
        }
    }

    private var currentEntityFrame: ReferenceEntityFrame? {
        guard let entityTrace else { return nil }
        return entityTrace.trace[min(Int(replayFrameValue), entityTrace.trace.count - 1)]
    }

    private func hasPrivateRecord(in room: RoomID) -> Bool {
        placementState?.records.contains {
            $0.roomID == room.y * 16 + room.x
                && exploration?.collectedRecordIDs.contains($0.id) != true
        } ?? false
    }

    private var selectedPrivateRecords: [CapturedPlacementRecord] {
        placementState?.records.filter {
            $0.roomID == selected.y * 16 + selected.x
                && exploration?.collectedRecordIDs.contains($0.id) != true
        } ?? []
    }

    @ViewBuilder
    private func exploratoryPlayerSprite(in size: CGSize) -> some View {
        if let exploration, selected == exploration.room {
            let spriteBase: Int = switch exploration.facing {
            case .left: 16
            case .right: 20
            case .up: 24
            case .down: 28
            case .fire: 16
            }
            if let spriteAtlas {
                switch Result(catching: {
                    try spriteAtlas.mask(at: spriteBase + (exploration.frame / 2) % 4)
                }) {
                case .success(let mask?):
                    placedPlayerSprite(
                        mask: mask, at: exploration.player, in: size, color: .cyan,
                        label: "Experimental player at X \(exploration.player.x), Y \(exploration.player.y); animation approximate"
                    )
                case .success(nil):
                    explorationMarker(exploration.player, in: size)
                case .failure(let error):
                    Text(error.localizedDescription).foregroundStyle(.red)
                }
            } else {
                explorationMarker(exploration.player, in: size)
            }
        }
    }

    private func explorationMarker(_ point: GridPoint, in size: CGSize) -> some View {
        Circle()
            .fill(.cyan)
            .frame(width: 14, height: 14)
            .position(
                x: CGFloat(point.x) * size.width / 256,
                y: screenY(point.y) * size.height / 192
            )
            .accessibilityLabel("Experimental player at X \(point.x), Y \(point.y)")
    }

    @ViewBuilder
    private func recordedPlayerSprite(in size: CGSize) -> some View {
        if showActorSprite, let spriteAtlas, let point = markerPosition {
            let kind = replay.map {
                $0.frames[min(Int(replayFrameValue), $0.frames.count - 1)].playerKind
            } ?? 21
            if let kind {
                switch Result(catching: { try spriteAtlas.mask(at: kind) }) {
                case .success(let mask?):
                    if entityTrace?.observedSlot == 18, let replay,
                       let entityFrame = currentEntityFrame,
                       (43...53).contains(replay.frames[
                           min(Int(replayFrameValue), replay.frames.count - 1)
                       ].index) {
                        switch Result(catching: {
                            guard let otherMask = try spriteAtlas.mask(
                                at: entityFrame.manualEntity.kind
                            ) else {
                                throw ReferenceEntityTraceError.invalidFrames
                            }
                            return CapturedOverlapBitmap.xorPlayerRectangle(
                                player: CapturedActorSprite(mask: mask, actorAt: point),
                                overlapping: CapturedActorSprite(
                                    mask: otherMask,
                                    actorAt: GridPoint(
                                        entityFrame.manualEntity.x, entityFrame.manualEntity.y
                                    )
                                )
                            )
                        }) {
                        case .success(let pixels):
                            placedPlayerPixels(
                                pixels: pixels, width: mask.width, height: mask.height,
                                at: point, in: size, color: .white,
                                label: "Recorded two-actor XOR bitmap at X \(point.x), Y \(point.y); color approximate"
                            )
                        case .failure(let error):
                            Text(error.localizedDescription).foregroundStyle(.red)
                        }
                    } else {
                        placedPlayerSprite(
                            mask: mask, at: point, in: size, color: .white,
                            label: "Recorded player bitmap at X \(point.x), Y \(point.y)"
                        )
                    }
                case .success(nil):
                    EmptyView()
                case .failure(let error):
                    Text(error.localizedDescription).foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private func measuredPlayerSprite(in size: CGSize) -> some View {
        if showActorSprite, let movement, selected == movement.room,
           let kind = movement.playerSpriteID, let spriteAtlas {
            switch Result(catching: { try spriteAtlas.mask(at: kind) }) {
            case .success(let mask?):
                placedPlayerSprite(
                    mask: mask, at: movement.player, in: size, color: .pink,
                    label: "Measured bitmap ID \(kind) at X \(movement.player.x), Y \(movement.player.y)"
                )
            case .success(nil):
                EmptyView()
            case .failure(let error):
                Text(error.localizedDescription).foregroundStyle(.red)
            }
        }
    }

    private func placedPlayerSprite(
        mask: SpriteMask, at point: GridPoint, in size: CGSize,
        color: Color, label: String
    ) -> some View {
        placedPlayerPixels(
            pixels: CapturedActorSprite(mask: mask, actorAt: point).screenPixels(),
            width: mask.width, height: mask.height, at: point, in: size,
            color: color, label: label
        )
    }

    private func placedPlayerPixels(
        pixels: [Bool], width: Int, height: Int, at point: GridPoint,
        in size: CGSize, color: Color, label: String
    ) -> some View {
        NativeSpritePixels(pixels: pixels, width: width, height: height, color: color)
            .frame(
                width: CGFloat(width) * size.width / 256,
                height: CGFloat(height) * size.height / 192
            )
            .position(
                x: (CGFloat(point.x) + CGFloat(width) / 2) * size.width / 256,
                y: (CGFloat(point.y - height + 1) + CGFloat(height) / 2)
                    * size.height / 192
            )
            .accessibilityLabel(label)
    }

    private func entitySummary(_ frame: ReferenceEntityFrame) -> String {
        let manual = frame.manualEntity
        let full = frame.fullEmulatorEntity
        return "Actor slot \(entityTrace?.observedSlot ?? 12) · manual room \(manual.roomID), X \(manual.x), Y \(manual.y)"
            + " · unmodified room \(full.roomID), X \(full.x), Y \(full.y)"
            + " (orange/purple rings when active; read-only)"
    }

    @ViewBuilder
    private func referenceEntityMarker(
        _ marker: ReferenceEntityMarker?, in room: RoomID, size: CGSize,
        color: Color, label: String
    ) -> some View {
        if let marker, marker.kind != 0, marker.roomID == room.y * 16 + room.x {
            Circle()
                .stroke(color, lineWidth: 2)
                .frame(width: 10, height: 10)
                .position(
                    x: CGFloat(marker.x) * size.width / 256,
                    y: screenY(marker.y) * size.height / 192
                )
                .accessibilityLabel(label)
        }
    }

    private func screenY(_ sourceY: Int) -> CGFloat {
        CGFloat(SpectrumCoordinates.screenY(forSourceY: sourceY))
    }

    private func roomSummary(template: Int, placements: Int) -> String {
        var parts = ["Room template \(template), \(placements) placements."]
        parts.append(art.isEmpty
            ? "Generic markers only; orange outlines show measured background bounds when available."
            : "Optional local image overlay, not verified original composition.")
        if markerPosition != nil {
            parts.append("Cyan ring marks the recorded player position.")
        }
        if movementMarkerPosition != nil {
            parts.append("Pink ring marks the measured movement position.")
        }
        if backgroundAtlas != nil {
            parts.append(sourceAttributeColors
                ? "Approximate 48K attribute colors show private source backgrounds."
                : "Private bitmap silhouettes show the room backgrounds in monochrome.")
        }
        if let frame = currentEntityFrame,
           frame.manualEntity.kind != 0 || frame.fullEmulatorEntity.kind != 0 {
            parts.append("Orange and purple rings mark private moving-entity comparisons.")
        }
        return parts.joined(separator: " ")
    }

    private func movementSummary(_ state: CapturedMovementState) -> String {
        let frame = state.referenceFrameOffset + state.frame
        let room = state.room.y * 16 + state.room.x
        return "Measured movement · source frame \(frame) · room \(room) "
            + "· X \(state.player.x), Y \(state.player.y)"
            + (state.transitioning ? " · switching rooms" : "")
    }

    private func startExploration(
        world: WorldReference, placements: CapturedPlacementState
    ) {
        do {
            let next = try ExperimentalWorldGame(
                world: world, placements: placements
            )
            exploration = next
            selected = next.room
            showExplorationMap = false
            sourceAttributeColors = !sourceRoomImages.isEmpty
            playingMovement = false
            playingExploration = false
            explorationHeldKey = "none"
            explorationError = nil
            #if os(macOS)
            explorationKeyboardFocused = true
            #endif
        } catch {
            explorationError = error.localizedDescription
        }
    }

    private func explorationButton(
        _ name: String, symbol: String, action: OriginalAction
    ) -> some View {
        Button {
            stepExploration(action)
        } label: {
            Image(systemName: symbol)
                .frame(width: 45, height: 36)
        }
        .accessibilityLabel("Travel \(name) in the experimental world")
    }

    private func stepExploration(_ action: OriginalAction) {
        explorationHeldKey = switch action {
        case .left: "q"
        case .right: "w"
        case .up: "e"
        case .down: "r"
        case .fire: "none"
        }
        advanceExploration(actions: [action], ticks: 6)
    }

    private func advanceExploration(held key: String) {
        if key == "none" {
            advanceExploration(actions: [], ticks: 1)
        } else if key.count == 1, let letter = key.first,
                  let action = OriginalAction.fromSpectrumKey(letter) {
            advanceExploration(actions: [action], ticks: 1)
        } else {
            playingExploration = false
            explorationError = "Choose Q, W, E, R or None for experimental travel."
        }
    }

    private func advanceExploration(
        actions: Set<OriginalAction>, ticks: Int
    ) {
        guard var next = exploration else { return }
        do {
            for _ in 0..<ticks {
                try next.advance(holding: actions)
            }
            exploration = next
            selected = next.room
            explorationError = nil
        } catch {
            playingExploration = false
            explorationError = error.localizedDescription
        }
    }

    private func resetMovement(origin: CapturedMovementOrigin? = nil) {
        guard let world else { return }
        do {
            let selectedOrigin = origin ?? movementOrigin
            let next = try CapturedMovementState(world: world, origin: selectedOrigin)
            movement = next
            movementOrigin = selectedOrigin
            heldKey = selectedOrigin == .observedNewGameReady ? "w" : "none"
            playingMovement = false
            selected = WorldReference.capturedGameplayRoom
            if let replay {
                replayFrameValue = Double(min(
                    max(next.referenceFrameOffset - 1, 0),
                    replay.frames.count - 1
                ))
            } else {
                replayFrameValue = 0
            }
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    private func advanceMovement() {
        guard var next = movement else { return }
        let actions: Set<OriginalAction>
        if heldKey == "none" {
            actions = []
        } else if heldKey.count == 1, let character = heldKey.first,
                  let action = OriginalAction.fromSpectrumKey(character) {
            actions = [action]
        } else {
            importError = "Unrecognized original key: \(heldKey)"
            playingMovement = false
            return
        }
        do {
            try next.advance(holding: actions)
            movement = next
            selected = next.room
            if let replay {
                let sourceIndex = next.frame + next.referenceFrameOffset - 1
                if replay.frames.indices.contains(sourceIndex) {
                    replayFrameValue = Double(sourceIndex)
                }
            }
            importError = nil
        } catch {
            importError = error.localizedDescription
            playingMovement = false
        }
    }

    private var markerPosition: GridPoint? {
        if let replay {
            if let movement, movement.referenceFrameOffset > 0,
               replay.frames.count < movement.frame + movement.referenceFrameOffset {
                return nil
            }
            let frame = replay.frames[min(Int(replayFrameValue), replay.frames.count - 1)]
            guard selected == RoomID(frame.playerRoomID % 16, frame.playerRoomID / 16) else {
                return nil
            }
            return GridPoint(frame.playerX, frame.playerY)
        }
        return movementOrigin != .observedNewGameReady
            && selected == WorldReference.capturedGameplayRoom
            ? WorldReference.capturedPlayerPosition : nil
    }

    private func image(for raster: WorldRaster) -> Image {
        #if os(macOS)
        Image(nsImage: raster)
        #else
        Image(uiImage: raster)
        #endif
    }

    private func stepButton(_ title: String, _ direction: Direction) -> some View {
        Button(title) {
            if let next = world?.adjacent(to: selected, direction: direction) {
                selected = next
            }
        }
        .disabled(world?.adjacent(to: selected, direction: direction) == nil)
    }
}

private struct NativeSpritePreview: View {
    let mask: SpriteMask

    var body: some View {
        NativeSpritePixels(mask: mask, color: .cyan)
            .frame(width: CGFloat(mask.width * 4), height: CGFloat(mask.height * 4))
            .accessibilityLabel("Private source silhouette, \(mask.width) by \(mask.height) pixels")
    }
}

private struct NativeSpritePixels: View {
    let pixels: [Bool]
    let width: Int
    let height: Int
    let color: Color

    init(mask: SpriteMask, color: Color) {
        self.pixels = CapturedActorSprite(
            mask: mask, actorAt: GridPoint(0, mask.height - 1)
        ).screenPixels()
        self.width = mask.width
        self.height = mask.height
        self.color = color
    }

    init(pixels: [Bool], width: Int, height: Int, color: Color) {
        self.pixels = pixels
        self.width = width
        self.height = height
        self.color = color
    }

    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / CGFloat(width)
            let scaleY = size.height / CGFloat(height)
            for index in pixels.indices where pixels[index] {
                let x = CGFloat(index % width) * scaleX
                let y = CGFloat(index / width) * scaleY
                context.fill(
                    Path(CGRect(x: x, y: y, width: scaleX, height: scaleY)),
                    with: .color(color)
                )
            }
        }
    }
}

private struct NativeBackgroundPreview: View {
    let mask: BackgroundMask
    let useAttributes: Bool

    var body: some View {
        let pixels = mask.pixels()
        let indices = useAttributes ? mask.paletteIndices(invertBitmap: true) : []
        let palette = SpectrumPalette.colors.map { rgb in
            Color(
                red: Double(rgb.red) / 255,
                green: Double(rgb.green) / 255,
                blue: Double(rgb.blue) / 255
            )
        }
        Canvas { context, size in
            let scaleX = size.width / CGFloat(mask.width)
            let scaleY = size.height / CGFloat(mask.height)
            for index in pixels.indices where useAttributes || pixels[index] {
                context.fill(
                    Path(CGRect(
                        x: CGFloat(index % mask.width) * scaleX,
                        y: CGFloat(index / mask.width) * scaleY,
                        width: scaleX, height: scaleY
                    )),
                    with: .color(useAttributes
                        ? palette[Int(indices[index])] : .mint.opacity(0.8))
                )
            }
        }
        .accessibilityHidden(true)
    }
}
