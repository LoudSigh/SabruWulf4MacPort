import Foundation

public struct WorldPlacement: Decodable, Sendable, Equatable {
    public let graphicAddress: Int
    public let x: Int
    public let y: Int
    public let widthPixels: Int?
    public let heightPixels: Int?
}

public struct WorldRoom: Decodable, Sendable, Equatable {
    public let placements: [WorldPlacement]
}

public enum WorldReferenceError: Error, LocalizedError {
    case unsupportedFormat
    case invalidLayout
    case invalidRoom(index: Int)
    case invalidPlacement(room: Int)
    case missingBounds
    case invalidPosition
    case invalidActorSize
    case invalidActorCoordinates

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "The selected file is not a supported 48K Sabre Wulf world export."
        case .invalidLayout: "The world must have 256 positions referencing 48 room templates."
        case .invalidRoom(let index): "Room template \(index) has an invalid number of placements."
        case .invalidPlacement(let room): "Room template \(room) contains an invalid placement."
        case .missingBounds: "This world export has no measured background bounds; regenerate the private world data."
        case .invalidPosition: "The requested world position is outside the 16 by 16 layout."
        case .invalidActorSize: "The actor bounding box must have a positive width and height."
        case .invalidActorCoordinates: "The actor coordinates must fit in unsigned bytes."
        }
    }
}

/// A read-only reference, never a simulation of the original game rules.
public struct WorldReference: Decodable, Sendable {
    public static let supportedSnapshotSHA256 =
        "803e4197989c73408cfc5113f8f30c81ac0269958aa9e105b474b6f52437203c"
    public static let capturedGameplayRoom = RoomID(8, 10)
    public static let capturedPlayerPosition = GridPoint(57, 112)

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
        guard (1...2).contains(world.schemaVersion),
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
                    && (world.schemaVersion == 1
                        || ($0.widthPixels.map { (8...248).contains($0) && $0.isMultiple(of: 8) } == true
                            && $0.heightPixels.map { (1...192).contains($0) } == true))
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

    /// Tests the measured background rectangles, not dynamic actors or room-edge rules.
    public func overlapsBackgroundBounds(
        in position: RoomID, actorAt point: GridPoint, width: Int, height: Int
    ) throws -> Bool {
        guard schemaVersion == 2 else { throw WorldReferenceError.missingBounds }
        guard let room = roomType(at: position) else {
            throw WorldReferenceError.invalidPosition
        }
        guard (1...255).contains(width), (1...255).contains(height) else {
            throw WorldReferenceError.invalidActorSize
        }
        guard (0...255).contains(point.x), (0...255).contains(point.y) else {
            throw WorldReferenceError.invalidActorCoordinates
        }
        return try rooms[room].placements.contains { placement in
            guard let backgroundWidth = placement.widthPixels,
                  let backgroundHeight = placement.heightPixels else {
                throw WorldReferenceError.missingBounds
            }
            // The source compares unsigned 8-bit differences by their sign bit, including wraparound.
            let dx = UInt8(truncatingIfNeeded: point.x - placement.x)
            let dy = UInt8(truncatingIfNeeded: point.y - backgroundHeight - placement.y)
            let horizontal = dx & 0x80 == 0
                ? dx < UInt8(backgroundWidth) : ~dx < UInt8(width)
            let vertical = dy & 0x80 == 0
                ? dy < UInt8(height) : ~dy < UInt8(backgroundHeight)
            return horizontal && vertical
        }
    }

    /// Resolves measured static overlaps independently on each axis; not a full actor update.
    public func resolveBackgroundBounds(
        in position: RoomID, from old: GridPoint, to candidate: GridPoint,
        width: Int, height: Int
    ) throws -> GridPoint {
        guard (0...255).contains(old.x), (0...255).contains(old.y) else {
            throw WorldReferenceError.invalidActorCoordinates
        }
        guard try overlapsBackgroundBounds(
            in: position, actorAt: candidate, width: width, height: height
        ) else {
            return candidate
        }
        var x = candidate.x
        var y = candidate.y
        if try overlapsBackgroundBounds(
            in: position, actorAt: GridPoint(x, old.y), width: width, height: height
        ) {
            x = old.x
        }
        if try overlapsBackgroundBounds(
            in: position, actorAt: GridPoint(old.x, y), width: width, height: height
        ) {
            y = old.y
        }
        return GridPoint(x, y)
    }
}
