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

public struct CapturedNewGameInjuryPhase: Equatable, Sendable {
    public let kind: UInt8
    public let timer: UInt8
}

/// One externally scheduled source actor update, not a display-frame timer.
public enum CapturedNewGameInjuryTick {
    public static func advance(
        kind: UInt8, room: RoomID, x: Int, y: Int,
        timer: UInt8, lifeByte: UInt8, velocityX: Int
    ) throws -> CapturedNewGameInjuryStep {
        guard kind == 64, room == RoomID(8, 10),
              (56...188).contains(x), y == 112,
              (32...76).contains(Int(timer)), lifeByte == 4,
              x == 56 + 3 * (Int(timer) - 32),
              velocityX == 3 else {
            throw CapturedNewGameInjuryError.unsupportedState
        }
        return CapturedNewGameInjuryStep(x: x + 3, timer: timer + 1)
    }

    public static func finishKnockback(
        kind: UInt8, room: RoomID, x: Int, y: Int,
        timer: UInt8, lifeByte: UInt8
    ) throws -> CapturedNewGameInjuryPhase {
        guard kind == 64, room == RoomID(8, 10),
              x == 191, y == 112, timer == 77, lifeByte == 4 else {
            throw CapturedNewGameInjuryError.unsupportedState
        }
        return CapturedNewGameInjuryPhase(kind: 65, timer: 63)
    }
}
