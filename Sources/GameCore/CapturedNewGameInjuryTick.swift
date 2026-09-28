import Foundation

public enum CapturedNewGameInjuryError: Error, LocalizedError {
    case unsupportedState

    public var errorDescription: String? {
        "This injury tick covers only the observed four-life and final-life knockback paths in room 168."
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
        let initial = kind == 64 && lifeByte == 4 && velocityX == 3
            && x == 56 + 3 * (Int(timer) - 32)
        let final = kind == 68 && lifeByte == 1 && velocityX == -3
            && x == 191 - 3 * (Int(timer) - 32)
        guard room == RoomID(8, 10), y == 112,
              (32...76).contains(Int(timer)), initial || final else {
            throw CapturedNewGameInjuryError.unsupportedState
        }
        return CapturedNewGameInjuryStep(
            x: x + velocityX, timer: timer + 1
        )
    }

    public static func finishKnockback(
        kind: UInt8, room: RoomID, x: Int, y: Int,
        timer: UInt8, lifeByte: UInt8
    ) throws -> CapturedNewGameInjuryPhase {
        let initial = kind == 64 && x == 191 && lifeByte == 4
        let final = kind == 68 && x == 56 && lifeByte == 1
        guard room == RoomID(8, 10), y == 112, timer == 77,
              initial || final else {
            throw CapturedNewGameInjuryError.unsupportedState
        }
        return CapturedNewGameInjuryPhase(
            kind: kind + 1, timer: 63
        )
    }
}
