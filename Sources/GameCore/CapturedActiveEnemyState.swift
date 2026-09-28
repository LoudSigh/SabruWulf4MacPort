import Foundation

public enum CapturedActiveEnemyError: Error, LocalizedError {
    case unsupportedState

    public var errorDescription: String? {
        "This enemy state is verified only for a moving slot-12 entity in room 152 before its timer expires."
    }
}

/// One observed enemy update; frame scheduling and RNG selection are external.
public struct CapturedActiveEnemyState: Equatable, Sendable {
    public private(set) var kind: UInt8
    public private(set) var timer: UInt8
    public private(set) var position: GridPoint
    public let velocityX: Int
    public let velocityY: Int
    public let room: RoomID

    public init(
        kind: UInt8, timer: UInt8, room: RoomID, position: GridPoint,
        velocityX: Int, velocityY: Int
    ) throws {
        guard (108...111).contains(Int(kind)), (2...15).contains(Int(timer)),
              room == RoomID(8, 9),
              [-80, -48, 48, 96].contains(velocityX), velocityY == 80 else {
            throw CapturedActiveEnemyError.unsupportedState
        }
        self.kind = kind
        self.timer = timer
        self.position = position
        self.velocityX = velocityX
        self.velocityY = velocityY
        self.room = room
    }

    public mutating func advanceOnSourceUpdate(
        world: WorldReference, countdownOccurred: Bool = true
    ) throws {
        guard timer >= 2 else { throw CapturedActiveEnemyError.unsupportedState }
        let next = try CapturedEntityMotion.advanceOnSourceUpdate(
            kind: kind, room: room, from: position,
            velocityX: velocityX, velocityY: velocityY, world: world
        )
        position = next
        kind ^= 1
        if countdownOccurred { timer -= 1 }
    }

    public mutating func advanceCountdownOnSourceUpdate() throws {
        guard timer >= 2 else { throw CapturedActiveEnemyError.unsupportedState }
        timer -= 1
    }
}
