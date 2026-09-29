import Foundation

public enum CapturedSlot12TransformGateError: Error, LocalizedError {
    case unsupportedState

    public var errorDescription: String? {
        "This actor gate is supported only for measured slot-12 kinds in the player's room."
    }
}

/// Source-selected branch for a measured slot-12 handler visit, not a combat trigger.
public enum CapturedSlot12TransformGate {
    public static func selectsKindSequence(
        actorKind: UInt8, actorRoom: UInt8,
        playerKind: UInt8, playerRoom: UInt8
    ) throws -> Bool {
        guard (108...111).contains(Int(actorKind)),
              actorRoom == playerRoom else {
            throw CapturedSlot12TransformGateError.unsupportedState
        }
        return !(16...47).contains(Int(playerKind))
    }
}
