import Foundation

public enum CapturedEnemyExpiryError: Error, LocalizedError {
    case unsupportedState

    public var errorDescription: String? {
        "Enemy timer expiry is supported only for the observed slot-12 moving or stopped states in room 152."
    }
}

public struct CapturedEnemyExpiryState: Equatable, Sendable {
    public let kind: UInt8
    public let timer: UInt8
    public let velocityX: Int
    public let velocityY: Int
}

/// One source timer-expiry event; the caller supplies the RNG and clock bytes.
public enum CapturedEnemyExpiry {
    public static func resolve(
        kind: UInt8, timer: UInt8, room: RoomID,
        velocityX: Int, velocityY: Int, rngByte: UInt8, clockByte: UInt8
    ) throws -> CapturedEnemyExpiryState {
        guard (108...111).contains(Int(kind)), timer == 1,
              room == RoomID(8, 9) else {
            throw CapturedEnemyExpiryError.unsupportedState
        }
        if velocityX == 0 && velocityY == 0 {
            let next = try CapturedEnemyDirection.choose(
                kind: kind, rngByte: rngByte, clockByte: clockByte
            )
            return CapturedEnemyExpiryState(
                kind: next.kind, timer: 0,
                velocityX: next.velocityX, velocityY: next.velocityY
            )
        }
        guard [-80, -48, 48, 96].contains(velocityX), velocityY == 80 else {
            throw CapturedEnemyExpiryError.unsupportedState
        }
        return CapturedEnemyExpiryState(
            kind: kind, timer: (rngByte & 7) | 8,
            velocityX: 0, velocityY: 0
        )
    }
}
