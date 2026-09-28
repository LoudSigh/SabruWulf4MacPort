import Foundation

public enum CapturedFinalInjuryError: Error, LocalizedError {
    case unsupportedState

    public var errorDescription: String? {
        "The final-life kind-69 countdown is verified only for the observed room-168 player."
    }
}

/// An externally supplied source actor update for the captured final-life path.
public enum CapturedFinalInjuryTick {
    public static func advance(
        kind: UInt8, timer: UInt8, lifeByte: UInt8,
        room: RoomID, x: Int, y: Int
    ) throws -> CapturedInjuryStep {
        guard kind == 69, (1...63).contains(Int(timer)),
              lifeByte == 1, room == RoomID(8, 10),
              x == 56, y == 112 else {
            throw CapturedFinalInjuryError.unsupportedState
        }
        return CapturedInjuryCountdownRule.advance(
            kind: kind, timer: timer, lifeByte: lifeByte, terminalKind: 21
        )
    }
}
