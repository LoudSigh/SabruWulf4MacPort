import Foundation

public enum CapturedRecordAwardError: Error, LocalizedError {
    case unsupportedState

    public var errorDescription: String? {
        "The measured record-removal award covers only one externally supplied first-player handler event."
    }
}

public struct CapturedRecordAwardResult: Equatable, Sendable {
    public let kind: UInt8
    public let scores: CapturedScoreState
}

/// One counterfactual source handler result; this does not decide when contact or collection occurs.
public enum CapturedRecordAward {
    public static func applyOnObservedHandler(
        recordKind: UInt8, activePlayer: UInt8, scores: CapturedScoreState
    ) throws -> CapturedRecordAwardResult {
        guard recordKind != 0, Int(recordKind) < SpriteAtlas.spriteCount,
              activePlayer == 0 else {
            throw CapturedRecordAwardError.unsupportedState
        }
        var nextScores = scores
        try nextScores.add(activePlayer: activePlayer,
                           pointsUpper: 0x75, pointsLower: 0)
        return CapturedRecordAwardResult(kind: 0, scores: nextScores)
    }
}
