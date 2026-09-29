import Foundation

public enum CapturedSlot12KindSequenceError: Error, LocalizedError {
    case unsupportedState

    public var errorDescription: String? {
        "This actor-kind sequence is supported only for the captured slot-12 position and timer after the measured motion."
    }
}

/// Externally selected kind transitions after slot-12 motion; not a damage or death rule.
public enum CapturedSlot12KindSequence {
    public static func next(
        kind: UInt8, room: RoomID, position: GridPoint, timer: UInt8
    ) throws -> UInt8 {
        guard room == RoomID(8, 9), position == GridPoint(53, 135),
              timer == 254 else {
            throw CapturedSlot12KindSequenceError.unsupportedState
        }
        switch kind {
        case 109: return 8
        case 8...12: return kind + 1
        case 13: return 0
        default: throw CapturedSlot12KindSequenceError.unsupportedState
        }
    }
}
