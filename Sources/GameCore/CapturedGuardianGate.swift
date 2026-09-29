import Foundation

public enum CapturedGuardianGateError: Error, LocalizedError {
    case unsupportedState

    public var errorDescription: String? {
        "The measured guardian branch requires its source-selected actor in the player's room and four bounded progress bits."
    }
}

public enum CapturedGuardianOutcome: Equatable, Sendable {
    case insufficientProgress
    case fourBitsPresent
}

/// One externally selected guardian branch; it does not schedule contact, injury or victory.
public enum CapturedGuardianGate {
    public static func choose(
        guardianKind: UInt8, playerRoom: UInt8,
        guardianRoom: UInt8, progressBits: UInt8
    ) throws -> CapturedGuardianOutcome {
        guard guardianKind == 148, playerRoom == guardianRoom,
              progressBits & 0xF0 == 0 else {
            throw CapturedGuardianGateError.unsupportedState
        }
        return progressBits == 0x0F
            ? .fourBitsPresent : .insufficientProgress
    }
}
