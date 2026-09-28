import Foundation

public enum CapturedEntityMotionError: Error, LocalizedError {
    case unsupportedState

    public var errorDescription: String? {
        "This entity movement is verified only for the measured room-152 encounter and observed velocities."
    }
}

/// One measured entity update; RNG, update cadence and player contact are separate.
public enum CapturedEntityMotion {
    public static func advanceOnSourceUpdate(
        kind: UInt8, room: RoomID, from position: GridPoint,
        velocityX: Int, velocityY: Int, world: WorldReference
    ) throws -> GridPoint {
        guard (108...111).contains(Int(kind)),
              room == RoomID(8, 9),
              [-80, -48, 48, 96].contains(velocityX),
              velocityY == 80 else {
            throw CapturedEntityMotionError.unsupportedState
        }
        let candidate = GridPoint(
            position.x + velocityX / 16, position.y + velocityY / 16
        )
        return try world.resolveBackgroundBounds(
            in: room, from: position, to: candidate, width: 16, height: 19
        )
    }
}
