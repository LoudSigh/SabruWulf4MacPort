import Foundation

public enum CapturedContactArmingError: Error, LocalizedError {
    case unsupportedState

    public var errorDescription: String? {
        "Contact arming is supported only for four measured first-injury player states."
    }
}

/// One observed positive-contact update; it does not choose the following injury tick.
public enum CapturedContactArming {
    public static func timerAfterContact(
        contact: Bool, kind: UInt8, timer: UInt8,
        lifeByte: UInt8, room: RoomID, velocityX: Int
    ) throws -> UInt8 {
        guard contact, timer == 0,
              CapturedInjuryStart.supportsPlayer(
                  kind: kind, lifeByte: lifeByte,
                  room: room, velocityX: velocityX
              ) else {
            throw CapturedContactArmingError.unsupportedState
        }
        return 1
    }
}
