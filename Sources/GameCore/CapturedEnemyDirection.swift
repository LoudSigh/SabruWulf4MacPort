import Foundation

public enum CapturedEnemyDirectionError: Error, LocalizedError {
    case unsupportedKind

    public var errorDescription: String? {
        "The measured enemy direction choice is supported only for actor kinds 108 through 111."
    }
}

public struct CapturedEnemyDirectionChoice: Equatable, Sendable {
    public let kind: UInt8
    public let velocityX: Int
    public let velocityY: Int
}

/// Selects a direction from supplied source randomness; it does not create RNG.
public enum CapturedEnemyDirection {
    public static func choose(
        kind: UInt8, rngByte: UInt8, clockByte: UInt8
    ) throws -> CapturedEnemyDirectionChoice {
        guard (108...111).contains(Int(kind)) else {
            throw CapturedEnemyDirectionError.unsupportedKind
        }
        let x = velocity(index: rngByte & 7)
        let y = velocity(index: clockByte & 7)
        let facing: UInt8 = x > 0 ? 2 : 0
        return CapturedEnemyDirectionChoice(
            kind: (kind & ~UInt8(2)) | facing,
            velocityX: x, velocityY: y
        )
    }

    static func velocity(index: UInt8) -> Int {
        index < 4 ? -96 + 16 * Int(index) : 48 + 16 * Int(index - 4)
    }
}
