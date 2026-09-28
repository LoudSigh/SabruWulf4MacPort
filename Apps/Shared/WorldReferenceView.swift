import GameCore
import SwiftUI
import UniformTypeIdentifiers

struct WorldReferenceView: View {
    @State private var world: WorldReference?
    @State private var selected = RoomID(0, 0)
    @State private var importing = false
    @State private var importError: String?

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
            Button("Import your private world data") { importing = true }
                .buttonStyle(.bordered)
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
                            Circle()
                                .fill(.yellow)
                                .frame(width: 7, height: 7)
                                .position(
                                    x: (CGFloat(placement.x) + 4) * area.size.width / 256,
                                    y: (CGFloat(placement.y) + 4) * area.size.height / 192
                                )
                        }
                    }
                }
                .frame(height: 180)
                .accessibilityLabel(
                    "Room template \(world.roomType(at: selected) ?? 0), "
                        + "\(placements.count) placement markers. No source artwork shown."
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
                selected = RoomID(0, 0)
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
        }
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
