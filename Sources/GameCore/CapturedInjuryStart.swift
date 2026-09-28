import Foundation

public enum CapturedInjuryStartError: Error, LocalizedError {
    case unsupportedState

    public var errorDescription: String? {
        "Injury entry is verified only for four captured first-contact player states."
    }
}

public struct CapturedInjuryStartStep: Equatable, Sendable {
    public let kind: UInt8
    public let timer: UInt8
    public let velocityX: Int
}

/// A source-supplied player update with timer 1; it does not schedule damage from contact.
public enum CapturedInjuryStart {
    public static func advance(
        kind: UInt8, timer: UInt8, lifeByte: UInt8,
        room: RoomID, velocityX: Int
    ) throws -> CapturedInjuryStartStep {
        let oneLifeEncounter = lifeByte == 1 && room == RoomID(8, 9)
            && (kind == 16 || kind == 27) && velocityX == 0
        let fourLifeRestart = lifeByte == 4 && room == RoomID(8, 10)
            && kind == 19 && velocityX == -29
        guard timer == 1, oneLifeEncounter || fourLifeRestart else {
            throw CapturedInjuryStartError.unsupportedState
        }
        return CapturedInjuryStartStep(kind: 64, timer: 32, velocityX: 3)
    }
}
