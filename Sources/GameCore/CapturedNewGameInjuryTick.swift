import Foundation

public enum CapturedNewGameInjuryError: Error, LocalizedError {
    case unsupportedState

    public var errorDescription: String? {
        "This injury tick covers only the observed four-life, kind-64 knockback in room 168."
    }
}

public struct CapturedNewGameInjuryStep: Equatable, Sendable {
    public let x: Int
    public let timer: UInt8
}

/// One externally scheduled source actor update, not a display-frame timer.
public enum CapturedNewGameInjuryTick {
    public static func advance(
        kind: UInt8, room: RoomID, x: Int, y: Int,
        timer: UInt8, lifeByte: UInt8, velocityX: Int
    ) throws -> CapturedNewGameInjuryStep {
        guard kind == 64, room == RoomID(8, 10),
              (56...137).contains(x), y == 112,
              (32...59).contains(Int(timer)), lifeByte == 4,
              x == 56 + 3 * (Int(timer) - 32),
              velocityX == 3 else {
            throw CapturedNewGameInjuryError.unsupportedState
        }
        return CapturedNewGameInjuryStep(x: x + 3, timer: timer + 1)
    }
}
