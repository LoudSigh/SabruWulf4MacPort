import Foundation

public enum CapturedRecordAwardError: Error, LocalizedError {
    case unsupportedState

    public var errorDescription: String? {
        "The measured record-removal award requires one distinct four-record kind, first-player selector and valid four-bit progress state."
    }
}

public struct CapturedRecordAwardResult: Equatable, Sendable {
    public let kind: UInt8
    public let progressBits: UInt8
    public let scores: CapturedScoreState
}

/// Four counterfactual zero-progress results; accumulated bits are inferred, and collection timing is external.
public enum CapturedRecordAward {
    public static func applyOnObservedHandler(
        recordKind: UInt8, activePlayer: UInt8,
        progressBits: UInt8, scores: CapturedScoreState
    ) throws -> CapturedRecordAwardResult {
        guard (144...147).contains(Int(recordKind)),
              activePlayer == 0, progressBits & 0xF0 == 0 else {
            throw CapturedRecordAwardError.unsupportedState
        }
        let bit = UInt8(1) << (recordKind - 144)
        guard progressBits & bit == 0 else {
            throw CapturedRecordAwardError.unsupportedState
        }
        var nextScores = scores
        try nextScores.add(activePlayer: activePlayer,
                           pointsUpper: 0x75, pointsLower: 0)
        return CapturedRecordAwardResult(
            kind: 0, progressBits: progressBits | bit, scores: nextScores
        )
    }
}
