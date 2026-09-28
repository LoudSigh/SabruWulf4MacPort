import Combine
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

struct WorldReferenceView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var world: WorldReference?
    @State private var selected = WorldReference.capturedGameplayRoom
    @State private var importing = false
    @State private var importingArtwork = false
    @State private var importError: String?
    @State private var art: [Int: WorldRaster] = [:]
    @State private var artStatus: String?
    @State private var importingSprites = false
    @State private var spriteSamples: [Int: WorldRaster] = [:]
    @State private var importingReplay = false
    @State private var replay: ReferenceReplay?
    @State private var replayFrameValue = 0.0
    @State private var importingEntityTrace = false
    @State private var entityTrace: ReferenceEntityTrace?
    @State private var movement: CapturedMovementState?
    @State private var heldKey = "none"
    @State private var playingMovement = false

    private let movementTimer = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect()

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 17), spacing: 2), count: 16
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1984 world structure")
                .font(.headline)
            Text(
                "Room structure and recorded replays are read-only. "
                    + "The separate movement preview implements only a measured subset of original rules."
            )
            .font(.caption)
            Text("Original keyboard reference: Q left · W right · E down · R up · T fire (not bound to this viewer)")
                .font(.caption)
            Button("Import your private world data") { importing = true }
                .buttonStyle(.bordered)
            if world != nil {
                if world?.schemaVersion == 2 {
                    if let movement {
                        Text(
                            "Measured movement · frame \(movement.frame) · room "
                                + "\(movement.room.y * 16 + movement.room.x) "
                                + "· X \(movement.player.x), Y \(movement.player.y)"
                                + (movement.transitioning ? " · switching rooms" : "")
                        )
                        .font(.caption.monospacedDigit())
                        Picker("Held original key", selection: $heldKey) {
                            Text("None").tag("none")
                            Text("Q · left").tag("q")
                            Text("W · right").tag("w")
                            Text("E · down").tag("e")
                            Text("R · up").tag("r")
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
                        Text("Partial movement: north/return match the independent reference; west/east passages are provisional because enemy paths differ. No native enemies, combat, items or other validated exits. Playback pauses on unsupported behavior.")
                            .font(.caption)
                    } else {
                        Button("Start measured movement (partial)") { resetMovement() }
                            .buttonStyle(.bordered)
                    }
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
                        "Recorded \(input.uppercased()) · frame \(frame.index) "
                            + "· room \(frame.playerRoomID) · X \(frame.playerX), Y \(frame.playerY)"
                    )
                    .font(.caption.monospacedDigit())
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
                    if let movement, (1...replay.frames.count).contains(movement.frame) {
                        let expected = replay.frames[movement.frame - 1]
                        let matches = expected.playerRoomID == movement.room.y * 16 + movement.room.x
                            && expected.playerX == movement.player.x
                            && expected.playerY == movement.player.y
                        Text(
                            "Measured frame \(movement.frame) vs imported replay: "
                                + (matches ? "actor position matches" : "actor position differs")
                        )
                        .font(.caption)
                        .foregroundStyle(matches ? Color.green : Color.orange)
                    }
                    Button("Import private enemy route comparison (optional)") {
                        importingEntityTrace = true
                    }
                    .buttonStyle(.bordered)
                    if let entityFrame = currentEntityFrame {
                        Text(entitySummary(entityFrame))
                            .font(.caption.monospacedDigit())
                    }
                }
                Button("Preview private background images (optional)") {
                    importingArtwork = true
                }
                .buttonStyle(.bordered)
                Text(
                    artStatus ?? "Markers and measured outlines (if available) show placements; no original art is bundled."
                )
                .font(.caption)
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
            }
            if let importError {
                Text(importError)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Import failed: \(importError)")
            }
            if let world {
                Text(
                    "Position \(selected.x + 1), \(selected.y + 1) of 16 × 16 "
                        + "· template \(world.roomType(at: selected) ?? 0)"
                )
                .font(.subheadline.monospacedDigit())

                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(0..<256, id: \.self) { index in
                        let position = RoomID(index % 16, index / 16)
                        let roomType = world.roomType(at: position) ?? 0
                        Button {
                            selected = position
                        } label: {
                            Rectangle()
                                .fill(
                                    position == selected
                                        ? Color.yellow : Color.teal.opacity(0.3 + Double(roomType % 4) * 0.12)
                                )
                                .aspectRatio(1, contentMode: .fit)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "Column \(position.x + 1), row \(position.y + 1), "
                                + "template \(roomType)"
                        )
                    }
                }
                .frame(maxWidth: 470)
                .accessibilityElement(children: .contain)

                HStack {
                    stepButton("North", .north)
                    stepButton("West", .west)
                    stepButton("East", .east)
                    stepButton("South", .south)
                }
                .buttonStyle(.bordered)
                let placements = world.rooms[world.roomType(at: selected) ?? 0].placements
                Text("\(placements.count) source background placements in this room template")
                    .font(.caption)
                GeometryReader { area in
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(.teal.opacity(0.12))
                        ForEach(placements.indices, id: \.self) { index in
                            let placement = placements[index]
                            if let graphic = art[placement.graphicAddress] {
                                image(for: graphic)
                                    .resizable()
                                    .interpolation(.none)
                                    .frame(
                                        width: graphic.size.width / 4 * area.size.width / 256,
                                        height: graphic.size.height / 4 * area.size.height / 192
                                    )
                                    .blendMode(.screen)
                                    .position(
                                        x: (CGFloat(placement.x) + graphic.size.width / 8)
                                            * area.size.width / 256,
                                        y: (CGFloat(placement.y) + graphic.size.height / 8)
                                            * area.size.height / 192
                                    )
                            } else {
                                Circle()
                                    .fill(.yellow)
                                    .frame(width: 7, height: 7)
                                    .position(
                                        x: (CGFloat(placement.x) + 4) * area.size.width / 256,
                                        y: (CGFloat(placement.y) + 4) * area.size.height / 192
                                    )
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
                                        y: (CGFloat(placement.y) + CGFloat(height) / 2)
                                            * area.size.height / 192
                                    )
                            }
                        }
                        if let position = markerPosition {
                            Circle()
                                .stroke(.cyan, lineWidth: 2)
                                .frame(width: 12, height: 12)
                                .position(
                                    x: CGFloat(position.x)
                                        * area.size.width / 256,
                                    y: CGFloat(position.y)
                                        * area.size.height / 192
                                )
                                .accessibilityLabel("Recorded player position")
                        }
                        if let position = movementMarkerPosition {
                            Circle()
                                .stroke(.pink, lineWidth: 2)
                                .frame(width: 16, height: 16)
                                .position(
                                    x: CGFloat(position.x) * area.size.width / 256,
                                    y: CGFloat(position.y) * area.size.height / 192
                                )
                                .accessibilityLabel("Measured movement position")
                        }
                        referenceEntityMarker(
                            currentEntityFrame?.manualEntity, in: selected,
                            size: area.size, color: .orange,
                            label: "Manual CPU moving entity"
                        )
                        referenceEntityMarker(
                            currentEntityFrame?.fullEmulatorEntity, in: selected,
                            size: area.size, color: .purple,
                            label: "Unmodified emulator moving entity"
                        )
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
                spriteSamples = [:]
                replay = nil
                entityTrace = nil
                replayFrameValue = 0
                movement = nil
                playingMovement = false
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
                replayFrameValue = 0
                let room = imported.frames[0].playerRoomID
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
            if scenePhase == .active && playingMovement {
                advanceMovement()
            }
        }
        .onDisappear { playingMovement = false }
    }

    private var movementMarkerPosition: GridPoint? {
        guard let movement, selected == movement.room else { return nil }
        return movement.player
    }

    private var currentEntityFrame: ReferenceEntityFrame? {
        guard let entityTrace else { return nil }
        return entityTrace.trace[min(Int(replayFrameValue), entityTrace.trace.count - 1)]
    }

    private func entitySummary(_ frame: ReferenceEntityFrame) -> String {
        let manual = frame.manualEntity
        let full = frame.fullEmulatorEntity
        return "Moving slot 12 · manual room \(manual.roomID), X \(manual.x), Y \(manual.y)"
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
                    y: CGFloat(marker.y) * size.height / 192
                )
                .accessibilityLabel(label)
        }
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
        if let frame = currentEntityFrame,
           frame.manualEntity.kind != 0 || frame.fullEmulatorEntity.kind != 0 {
            parts.append("Orange and purple rings mark private moving-entity comparisons.")
        }
        return parts.joined(separator: " ")
    }

    private func resetMovement() {
        guard let world else { return }
        do {
            movement = try CapturedMovementState(world: world)
            heldKey = "none"
            playingMovement = false
            selected = WorldReference.capturedGameplayRoom
            replayFrameValue = 0
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
                replayFrameValue = Double(min(max(next.frame - 1, 0), replay.frames.count - 1))
            }
            importError = nil
        } catch {
            importError = error.localizedDescription
            playingMovement = false
        }
    }

    private var markerPosition: GridPoint? {
        if let replay {
            let frame = replay.frames[min(Int(replayFrameValue), replay.frames.count - 1)]
            guard selected == RoomID(frame.playerRoomID % 16, frame.playerRoomID / 16) else {
                return nil
            }
            return GridPoint(frame.playerX, frame.playerY)
        }
        return selected == WorldReference.capturedGameplayRoom
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
