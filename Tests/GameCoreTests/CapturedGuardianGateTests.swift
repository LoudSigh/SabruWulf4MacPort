import Foundation
import XCTest
@testable import GameCore

final class CapturedGuardianGateTests: XCTestCase {
    func testFourBitBranchIsNotAWinTransition() throws {
        for bits: UInt8 in [0, 1, 3, 7] {
            XCTAssertEqual(try CapturedGuardianGate.choose(
                guardianKind: 148, playerRoom: 168,
                guardianRoom: 168, progressBits: bits
            ), .insufficientProgress)
        }
        XCTAssertEqual(try CapturedGuardianGate.choose(
            guardianKind: 148, playerRoom: 168,
            guardianRoom: 168, progressBits: 15
        ), .fourBitsPresent)
        XCTAssertEqual(try CapturedGuardianGate.choose(
            guardianKind: 149, playerRoom: 168,
            guardianRoom: 168, progressBits: 15
        ), .fourBitsPresent)
        XCTAssertEqual(try CapturedGuardianGate.choose(
            guardianKind: 149, playerRoom: 168,
            guardianRoom: 168, progressBits: 0
        ), .insufficientProgress)
        XCTAssertThrowsError(try CapturedGuardianGate.choose(
            guardianKind: 150, playerRoom: 168,
            guardianRoom: 168, progressBits: 15
        ))
        XCTAssertThrowsError(try CapturedGuardianGate.choose(
            guardianKind: 148, playerRoom: 168,
            guardianRoom: 136, progressBits: 15
        ))
        XCTAssertThrowsError(try CapturedGuardianGate.choose(
            guardianKind: 148, playerRoom: 168,
            guardianRoom: 168, progressBits: 0x8F
        ))
    }

    func testFourExternallyAwardedBitsSelectTheAllBitsBranch() throws {
        var bits: UInt8 = 0
        let zero = try CapturedPackedScore(bytes: [0, 0, 0])
        var scores = CapturedScoreState(first: zero, second: zero)
        for kind: UInt8 in 144...147 {
            let result = try CapturedRecordAward.applyOnObservedHandler(
                recordKind: kind, activePlayer: 0,
                progressBits: bits, scores: scores
            )
            bits = result.progressBits
            scores = result.scores
        }
        XCTAssertEqual(bits, 15)
        XCTAssertEqual(try CapturedGuardianGate.choose(
            guardianKind: 148, playerRoom: 168,
            guardianRoom: 168, progressBits: bits
        ), .fourBitsPresent)
    }

    func testPrivateFiveGuardianBranchResultsWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_GUARD_GATE"
        ] else { throw XCTSkip("Set the ignored guarded-actor branch report") }
        struct Branch: Decodable {
            let progressBefore: UInt8
            let matchingManualFullRAMFrames: Int
            let matchingManualFullCPUFrames: Int
            let sourceGateVisits: Int
            let noPiecesPathVisits: Int
            let allPiecesPathVisits: Int
            let firstGateFrame: Int
            let firstInjuryFrame: Int?
            let finalPlayerKind: Int
            let finalGuardianX: Int
        }
        let results = try JSONDecoder().decode(
            [Branch].self, from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        XCTAssertEqual(results.map(\.progressBefore), [0, 1, 3, 7, 15])
        for report in results {
            let predicted = try CapturedGuardianGate.choose(
                guardianKind: 148, playerRoom: 168,
                guardianRoom: 168, progressBits: report.progressBefore
            )
            XCTAssertEqual(report.matchingManualFullRAMFrames, 30)
            XCTAssertEqual(report.matchingManualFullCPUFrames, 30)
            XCTAssertEqual(report.sourceGateVisits, 13)
            XCTAssertEqual(report.firstGateFrame, 1)
            if report.progressBefore == 15 {
                XCTAssertEqual(predicted, .fourBitsPresent)
                XCTAssertEqual(report.noPiecesPathVisits, 0)
                XCTAssertEqual(report.allPiecesPathVisits, 13)
                XCTAssertNil(report.firstInjuryFrame)
                XCTAssertEqual(report.finalPlayerKind, 21)
                XCTAssertEqual(report.finalGuardianX, 84)
            } else {
                XCTAssertEqual(predicted, .insufficientProgress)
                XCTAssertEqual(report.noPiecesPathVisits, 13)
                XCTAssertEqual(report.allPiecesPathVisits, 0)
                XCTAssertEqual(report.firstInjuryFrame, 2)
                XCTAssertEqual(report.finalPlayerKind, 65)
                XCTAssertEqual(report.finalGuardianX, 58)
            }
        }
    }

    func testPrivateKind149BranchesWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_GUARD_GATE_KIND149"
        ] else { throw XCTSkip("Set the ignored second guardian-kind branch report") }
        struct Branch: Decodable {
            let actorKindAtFork: UInt8
            let progressBefore: UInt8
            let matchingManualFullRAMFrames: Int
            let matchingManualFullCPUFrames: Int
            let sourceGateVisits: Int
            let noPiecesPathVisits: Int
            let allPiecesPathVisits: Int
            let firstInjuryFrame: Int?
            let finalGuardianX: Int
        }
        let results = try JSONDecoder().decode(
            [Branch].self, from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        XCTAssertEqual(results.map(\.progressBefore), [0, 15])
        for result in results {
            XCTAssertEqual(result.actorKindAtFork, 149)
            XCTAssertEqual(result.matchingManualFullRAMFrames, 30)
            XCTAssertEqual(result.matchingManualFullCPUFrames, 30)
            XCTAssertEqual(result.sourceGateVisits, 13)
            let predicted = try CapturedGuardianGate.choose(
                guardianKind: result.actorKindAtFork,
                playerRoom: 168, guardianRoom: 168,
                progressBits: result.progressBefore
            )
            if result.progressBefore == 15 {
                XCTAssertEqual(predicted, .fourBitsPresent)
                XCTAssertEqual(result.noPiecesPathVisits, 0)
                XCTAssertEqual(result.allPiecesPathVisits, 13)
                XCTAssertNil(result.firstInjuryFrame)
                XCTAssertEqual(result.finalGuardianX, 84)
            } else {
                XCTAssertEqual(predicted, .insufficientProgress)
                XCTAssertEqual(result.noPiecesPathVisits, 13)
                XCTAssertEqual(result.allPiecesPathVisits, 0)
                XCTAssertEqual(result.firstInjuryFrame, 2)
                XCTAssertEqual(result.finalGuardianX, 58)
            }
        }
    }
}
