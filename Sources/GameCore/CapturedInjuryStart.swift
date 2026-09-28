import Foundation

public enum CapturedInjuryStartError: Error, LocalizedError {
    case unsupportedState

    public var errorDescription: String? {
        "Injury entry is verified only for seven captured contact player states."
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
        let final = isFinalLifePlayer(
            kind: kind, lifeByte: lifeByte, room: room, velocityX: velocityX
        )
        guard supportsPlayer(kind: kind, lifeByte: lifeByte,
                             room: room, velocityX: velocityX),
              (final && timer == 2) || (!final && timer == 1) else {
            throw CapturedInjuryStartError.unsupportedState
        }
        return CapturedInjuryStartStep(
            kind: final ? 68 : 64, timer: 32, velocityX: final ? -3 : 3
        )
    }

    static func supportsPlayer(
        kind: UInt8, lifeByte: UInt8, room: RoomID, velocityX: Int
    ) -> Bool {
        let oneLifeEncounter = lifeByte == 1 && room == RoomID(8, 9)
            && (kind == 16 || kind == 27) && velocityX == 0
        let fourLifeRestart = lifeByte == 4 && room == RoomID(8, 10)
            && kind == 19 && velocityX == -29
        let middleLives = (lifeByte == 2 || lifeByte == 3)
            && room == RoomID(8, 10) && kind == 17 && velocityX == 0
        return oneLifeEncounter || fourLifeRestart || middleLives
            || isFinalLifePlayer(
                kind: kind, lifeByte: lifeByte, room: room, velocityX: velocityX
            )
    }

    static func isFinalLifePlayer(
        kind: UInt8, lifeByte: UInt8, room: RoomID, velocityX: Int
    ) -> Bool {
        lifeByte == 1 && room == RoomID(8, 10)
            && kind == 17 && velocityX == 0
    }
}
