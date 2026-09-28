import Foundation
import XCTest
@testable import GameCore

final class CapturedScoreStepTests: XCTestCase {
    func testPackedBCDAdditionAndPlayerSelection() throws {
        var state = CapturedScoreState(
            first: try CapturedPackedScore(bytes: [0, 0x14, 0]),
            second: try CapturedPackedScore(bytes: [0, 0, 0])
        )
        try state.add(activePlayer: 0, pointsUpper: 0x01, pointsLower: 0x95)
        XCTAssertEqual(state.first.bytes, [0, 0x15, 0x95])
        XCTAssertEqual(state.second.bytes, [0, 0, 0])
        try state.add(activePlayer: 1, pointsUpper: 0, pointsLower: 0x75)
        XCTAssertEqual(state.first.bytes, [0, 0x15, 0x95])
        XCTAssertEqual(state.second.bytes, [0, 0, 0x75])
    }

    func testSixDigitWrapAndInvalidBCD() throws {
        var state = CapturedScoreState(
            first: try CapturedPackedScore(bytes: [0x99, 0x99, 0x95]),
            second: try CapturedPackedScore(bytes: [0, 0, 0])
        )
        try state.add(activePlayer: 0, pointsUpper: 0, pointsLower: 0x10)
        XCTAssertEqual(state.first.bytes, [0, 0, 0x05])
        XCTAssertThrowsError(try CapturedPackedScore(bytes: [0, 0x1A, 0]))
        XCTAssertThrowsError(try CapturedPackedScore(bytes: [0, 0]))
        XCTAssertThrowsError(try state.add(
            activePlayer: 2, pointsUpper: 0, pointsLower: 0
        ))
        XCTAssertThrowsError(try state.add(
            activePlayer: 0, pointsUpper: 0, pointsLower: 0xFA
        ))
    }

    func testPrivateScoreWritesWhenProvided() throws {
        guard let directory = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_SCORE_REPORT_DIR"
        ] else { throw XCTSkip("Set ignored score-parity report directory") }
        struct Comparison: Decodable {
            let calls: Int
            let matchingCalls: Int
            let firstPlayerCalls: Int
            let secondPlayerCalls: Int
            let frames: [Int]
        }
        struct Report: Decodable {
            let framesCompared: Int
            let matchingRAMFrames: Int
            let scoreComparison: Comparison
        }
        for (name, frames, calls) in [
            ("score-parity-no-fire-encounter-190.json", 190, 2),
            ("score-parity-unrelated-a-control-190.json", 190, 2),
            ("score-parity-fire-before-contact-250.json", 250, 3),
            ("score-parity-w-q-1800.json", 1800, 18),
        ] {
            let report = try JSONDecoder().decode(
                Report.self,
                from: Data(contentsOf: URL(fileURLWithPath: directory)
                    .appendingPathComponent(name))
            )
            XCTAssertEqual(report.framesCompared, frames)
            XCTAssertEqual(report.matchingRAMFrames, frames)
            XCTAssertEqual(report.scoreComparison.calls, calls)
            XCTAssertEqual(report.scoreComparison.matchingCalls, calls)
            XCTAssertEqual(report.scoreComparison.firstPlayerCalls, calls)
            XCTAssertEqual(report.scoreComparison.secondPlayerCalls, 0)
            XCTAssertEqual(report.scoreComparison.frames.count, calls)
        }
    }
}
