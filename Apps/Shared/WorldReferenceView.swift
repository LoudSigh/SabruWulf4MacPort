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

struct WorldReferenceView: View {
    @State private var world: WorldReference?
    @State private var selected = WorldReference.capturedGameplayRoom
    @State private var importing = false
    @State private var importingArtwork = false
    @State private var importError: String?
    @State private var art: [Int: WorldRaster] = [:]
    @State private var artStatus: String?
    @State private var importingReplay = false
    @State private var replay: ReferenceReplay?
    @State private var replayFrameValue = 0.0

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 17), spacing: 2), count: 16
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1984 world structure")
                .font(.headline)
            Text(
                "Read-only reference: authentic room types and placement coordinates. "
                    + "No original art, collision or game rules are in this viewer."
            )
            .font(.caption)
            Text("Original keyboard reference: Q left · W right · E down · R up · T fire (not bound to this viewer)")
                .font(.caption)
            Button("Import your private world data") { importing = true }
                .buttonStyle(.bordered)
            if world != nil {
                Button("Import a private gameplay replay (optional)") {
                    importingReplay = true
                }
                .buttonStyle(.bordered)
                if let replay {
                    let frame = replay.frames[min(Int(replayFrameValue), replay.frames.count - 1)]
                    Text(
                        "Recorded \(replay.input.uppercased()) · frame \(frame.index) "
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
                }
                Button("Preview private background images (optional)") {
                    importingArtwork = true
                }
                .buttonStyle(.bordered)
                Text(
                    artStatus ?? "Markers show placement coordinates; no original art is bundled."
                )
                .font(.caption)
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
                    }
                }
                .frame(height: 180)
                .accessibilityLabel(
                    "Room template \(world.roomType(at: selected) ?? 0), "
                        + "\(placements.count) placements. "
                        + (art.isEmpty
                            ? "Generic markers only."
                            : "Optional local image overlay, not verified original composition.")
                        + (markerPosition != nil
                            ? " Cyan ring marks the recorded player position." : "")
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
                replay = nil
                replayFrameValue = 0
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
                replayFrameValue = 0
                let room = imported.frames[0].playerRoomID
                selected = RoomID(room % 16, room / 16)
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
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
