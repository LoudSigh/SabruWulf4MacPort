import Foundation

public struct WorldPlacement: Decodable, Sendable, Equatable {
    public let graphicAddress: Int
    public let x: Int
    public let y: Int
}

public struct WorldRoom: Decodable, Sendable, Equatable {
    public let placements: [WorldPlacement]
}

public enum WorldReferenceError: Error, LocalizedError {
    case unsupportedFormat
    case invalidLayout
    case invalidRoom(index: Int)
    case invalidPlacement(room: Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "The selected file is not a supported 48K Sabre Wulf world export."
        case .invalidLayout: "The world must have 256 positions referencing 48 room templates."
        case .invalidRoom(let index): "Room template \(index) has an invalid number of placements."
        case .invalidPlacement(let room): "Room template \(room) contains an invalid placement."
        }
    }
}

/// A read-only topology reference, never a simulation of the original game rules.
public struct WorldReference: Decodable, Sendable {
    public static let supportedSnapshotSHA256 =
        "803e4197989c73408cfc5113f8f30c81ac0269958aa9e105b474b6f52437203c"

    public let schemaVersion: Int
    public let snapshotSha256: String
    public let width: Int
    public let height: Int
    public let layout: [UInt8]
    public let rooms: [WorldRoom]

    public static func load(from data: Data) throws -> WorldReference {
        guard data.count <= 2_000_000 else {
            throw WorldReferenceError.unsupportedFormat
        }
        let world = try JSONDecoder().decode(Self.self, from: data)
        guard world.schemaVersion == 1,
              world.snapshotSha256 == supportedSnapshotSHA256
        else {
            throw WorldReferenceError.unsupportedFormat
        }
        guard world.width == 16, world.height == 16,
              world.layout.count == 256,
              world.rooms.count == 48,
              world.layout.allSatisfy({ $0 < 48 })
        else {
            throw WorldReferenceError.invalidLayout
        }
        for (index, room) in world.rooms.enumerated() {
            guard (1...64).contains(room.placements.count) else {
                throw WorldReferenceError.invalidRoom(index: index)
            }
            guard room.placements.allSatisfy({
                (0x70BC...0x9673).contains($0.graphicAddress)
                    && (0..<256).contains($0.x)
                    && (0..<192).contains($0.y)
            }) else {
                throw WorldReferenceError.invalidPlacement(room: index)
            }
        }
        return world
    }

    public func roomType(at position: RoomID) -> Int? {
        guard (0..<width).contains(position.x), (0..<height).contains(position.y) else {
            return nil
        }
        return Int(layout[position.y * width + position.x])
    }

    public func adjacent(to position: RoomID, direction: Direction) -> RoomID? {
        let offset = direction.offset
        let next = RoomID(position.x + offset.x, position.y + offset.y)
        return roomType(at: next) == nil ? nil : next
    }
}
