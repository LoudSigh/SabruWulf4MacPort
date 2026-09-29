import Foundation
import XCTest
@testable import GameCore

final class CapturedRecordAwardTests: XCTestCase {
    private func emptyScores() throws -> CapturedScoreState {
        CapturedScoreState(
            first: try CapturedPackedScore(bytes: [0, 0, 0]),
            second: try CapturedPackedScore(bytes: [0, 0, 0])
        )
    }

    func testSourceSelectedHandlerRemovesRecordAndAdds7500() throws {
        let result = try CapturedRecordAward.applyOnObservedHandler(
            recordKind: 16, activePlayer: 0, scores: emptyScores()
        )
        XCTAssertEqual(result.kind, 0)
        XCTAssertEqual(result.scores.first.decimalValue, 7500)
        XCTAssertEqual(result.scores.second.decimalValue, 0)
    }

    func testRejectsUnknownHandlerInputs() throws {
        for (kind, player) in [
            (UInt8(0), UInt8(0)),
            (UInt8(16), UInt8(1)),
            (UInt8(196), UInt8(0)),
        ] {
            XCTAssertThrowsError(try CapturedRecordAward.applyOnObservedHandler(
                recordKind: kind, activePlayer: player, scores: emptyScores()
            ))
        }
    }

    func testRemovalCannotAwardTwiceAndScoreWraps() throws {
        let scores = CapturedScoreState(
            first: try CapturedPackedScore(bytes: [0x99, 0x50, 0]),
            second: try CapturedPackedScore(bytes: [0, 0, 0])
        )
        let result = try CapturedRecordAward.applyOnObservedHandler(
            recordKind: 16, activePlayer: 0, scores: scores
        )
        XCTAssertEqual(result.scores.first.bytes, [0, 0x25, 0])
        XCTAssertThrowsError(try CapturedRecordAward.applyOnObservedHandler(
            recordKind: result.kind, activePlayer: 0, scores: result.scores
        ))
    }

    func testPrivateCounterfactualResultWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_RECORD_AWARD"
        ] else { throw XCTSkip("Set the ignored edited-RAM award fixture") }
        struct Fixture: Decodable {
            let schemaVersion: Int
            let snapshotSHA256: String
            let sourceFrame: Int
            let handlerPC: Int
            let scorePC: Int
            let recordKindBefore: UInt8
            let recordKindAfter: UInt8
            let activePlayer: UInt8
            let pointsUpper: UInt8
            let pointsLower: UInt8
            let firstScoreBefore: [UInt8]
            let firstScoreAfter: [UInt8]
            let secondScoreBefore: [UInt8]
            let secondScoreAfter: [UInt8]
        }
        let sample = try JSONDecoder().decode(
            Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        XCTAssertEqual(sample.schemaVersion, 1)
        XCTAssertEqual(sample.snapshotSHA256, WorldReference.supportedSnapshotSHA256)
        XCTAssertEqual(sample.sourceFrame, 792)
        XCTAssertEqual(sample.handlerPC, 41449)
        XCTAssertEqual(sample.scorePC, 46505)
        XCTAssertEqual(sample.activePlayer, 0)
        XCTAssertEqual(sample.pointsUpper, 0x75)
        XCTAssertEqual(sample.pointsLower, 0)
        let before = CapturedScoreState(
            first: try CapturedPackedScore(bytes: sample.firstScoreBefore),
            second: try CapturedPackedScore(bytes: sample.secondScoreBefore)
        )
        let result = try CapturedRecordAward.applyOnObservedHandler(
            recordKind: sample.recordKindBefore,
            activePlayer: sample.activePlayer, scores: before
        )
        XCTAssertEqual(result.kind, sample.recordKindAfter)
        XCTAssertEqual(result.scores.first.bytes, sample.firstScoreAfter)
        XCTAssertEqual(result.scores.second.bytes, sample.secondScoreAfter)
    }
}
