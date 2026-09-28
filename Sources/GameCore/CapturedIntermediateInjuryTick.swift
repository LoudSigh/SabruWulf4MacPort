import Foundation

public enum CapturedIntermediateInjuryError: Error, LocalizedError {
    case unsupportedState

    public var errorDescription: String? {
        "This stationary kind-64 transition covers only the observed two- and three-life player in room 168."
    }
}

/// The externally scheduled kind-64 exit between first and final lives.
public enum CapturedIntermediateInjuryTick {
    public static func advance(
        kind: UInt8, timer: UInt8, lifeByte: UInt8,
        room: RoomID, x: Int, y: Int
    ) throws -> CapturedNewGameInjuryPhase {
        guard kind == 64, timer == 32,
              lifeByte == 2 || lifeByte == 3,
              room == RoomID(8, 10), x == 191, y == 112 else {
            throw CapturedIntermediateInjuryError.unsupportedState
        }
        return CapturedNewGameInjuryPhase(kind: 65, timer: 63)
    }
}
