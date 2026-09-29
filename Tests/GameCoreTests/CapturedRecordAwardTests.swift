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

    func testFourSourceSelectedResultsRemoveRecordSetDistinctBitAndAdd7500() throws {
        for (kind, bit) in [
            (UInt8(144), UInt8(1)), (145, 2), (146, 4), (147, 8),
        ] {
            let result = try CapturedRecordAward.applyOnObservedHandler(
                recordKind: kind, activePlayer: 0,
                progressBits: 0, scores: emptyScores()
            )
            XCTAssertEqual(result.kind, 0)
            XCTAssertEqual(result.progressBits, bit)
            XCTAssertEqual(result.scores.first.decimalValue, 7500)
            XCTAssertEqual(result.scores.second.decimalValue, 0)
        }
    }

    func testSyntheticFourStepAccumulation() throws {
        var scores = try emptyScores()
        var bits: UInt8 = 0
        for kind: UInt8 in 144...147 {
            let result = try CapturedRecordAward.applyOnObservedHandler(
                recordKind: kind, activePlayer: 0,
                progressBits: bits, scores: scores
            )
            bits = result.progressBits
            scores = result.scores
        }
        XCTAssertEqual(bits, 0x0F)
        XCTAssertEqual(scores.first.decimalValue, 30_000)
    }

    func testRejectsUnknownHandlerInputs() throws {
        for (kind, player, bits) in [
            (UInt8(0), UInt8(0), UInt8(0)),
            (16, 0, 0),
            (196, 0, 0),
            (144, 1, 0),
            (144, 0, 0x80),
            (144, 0, 1),
        ] {
            XCTAssertThrowsError(try CapturedRecordAward.applyOnObservedHandler(
                recordKind: kind, activePlayer: player,
                progressBits: bits, scores: emptyScores()
            ))
        }
    }

    func testRemovalCannotAwardTwiceAndScoreWraps() throws {
        let scores = CapturedScoreState(
            first: try CapturedPackedScore(bytes: [0x99, 0x50, 0]),
            second: try CapturedPackedScore(bytes: [0, 0, 0])
        )
        let result = try CapturedRecordAward.applyOnObservedHandler(
            recordKind: 144, activePlayer: 0,
            progressBits: 0, scores: scores
        )
        XCTAssertEqual(result.scores.first.bytes, [0, 0x25, 0])
        XCTAssertThrowsError(try CapturedRecordAward.applyOnObservedHandler(
            recordKind: 144, activePlayer: 0,
            progressBits: result.progressBits, scores: result.scores
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
            activePlayer: sample.activePlayer,
            progressBits: 0, scores: before
        )
        XCTAssertEqual(result.kind, sample.recordKindAfter)
        XCTAssertEqual(result.progressBits, 8)
        XCTAssertEqual(result.scores.first.bytes, sample.firstScoreAfter)
        XCTAssertEqual(result.scores.second.bytes, sample.secondScoreAfter)
    }

    func testPrivateFourCounterfactualBitAndScoreResultsWhenProvided() throws {
        guard let directory = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_RECORD_AWARD_DIR"
        ] else { throw XCTSkip("Set the ignored four-record branch report directory") }
        struct Branch: Decodable {
            let validatedManualFullRAMFrames: Int
            let scoreRoutineEntries: Int
            let pureScoreStepMatches: Int
            let inventoryChangedWrites: Int
            let lifeChangedWrites: Int
            let positiveOtherContacts: Int
        }
        struct Probe: Decodable {
            let recordRemovalFrame: Int
            let selectedRecordKind: UInt8
            let inventoryBefore: UInt8
            let controlInventoryAfter: UInt8
            let relocatedInventoryAfter: UInt8
            let addedInventoryBits: UInt8
            let control: Branch
            let relocated: Branch
        }
        struct Score: Decodable {
            let pointsUpper: UInt8
            let pointsLower: UInt8
            let activePlayer: UInt8
            let firstBefore: [UInt8]
            let secondBefore: [UInt8]
            let firstAfter: [UInt8]
            let secondAfter: [UInt8]
            let resultMatchesPureHelper: Bool
        }
        struct Captured: Decodable {
            let relocated: [Score]
        }
        let base = URL(fileURLWithPath: directory)
        for id in 0..<4 {
            let sample = try JSONDecoder().decode(Probe.self, from: Data(
                contentsOf: base.appendingPathComponent(
                    "quest-inventory-id-\(id).json"
                )
            ))
            let capture = try JSONDecoder().decode(Captured.self, from: Data(
                contentsOf: base.appendingPathComponent(
                    "quest-relocation-score-operands-id-\(id)-private.json"
                )
            ))
            let expectedBit = UInt8(1 << (3 - id))
            XCTAssertEqual(sample.selectedRecordKind, UInt8(147 - id))
            XCTAssertEqual(sample.recordRemovalFrame, 792)
            XCTAssertEqual(sample.inventoryBefore, 0)
            XCTAssertEqual(sample.controlInventoryAfter, 0)
            XCTAssertEqual(sample.relocatedInventoryAfter, expectedBit)
            XCTAssertEqual(sample.addedInventoryBits, expectedBit)
            XCTAssertEqual(sample.control.validatedManualFullRAMFrames, 30)
            XCTAssertEqual(sample.relocated.validatedManualFullRAMFrames, 30)
            XCTAssertEqual(sample.control.scoreRoutineEntries, 0)
            XCTAssertEqual(sample.control.inventoryChangedWrites, 0)
            XCTAssertEqual(sample.relocated.scoreRoutineEntries, 1)
            XCTAssertEqual(sample.relocated.pureScoreStepMatches, 1)
            XCTAssertEqual(sample.relocated.inventoryChangedWrites, 2)
            XCTAssertEqual(sample.relocated.lifeChangedWrites, 0)
            XCTAssertEqual(sample.relocated.positiveOtherContacts, 0)
            XCTAssertEqual(capture.relocated.count, 1)
            let score = try XCTUnwrap(capture.relocated.first)
            XCTAssertEqual(score.pointsUpper, 0x75)
            XCTAssertEqual(score.pointsLower, 0)
            XCTAssertEqual(score.activePlayer, 0)
            XCTAssertTrue(score.resultMatchesPureHelper)
            let before = CapturedScoreState(
                first: try CapturedPackedScore(bytes: score.firstBefore),
                second: try CapturedPackedScore(bytes: score.secondBefore)
            )
            let result = try CapturedRecordAward.applyOnObservedHandler(
                recordKind: sample.selectedRecordKind,
                activePlayer: score.activePlayer,
                progressBits: sample.inventoryBefore, scores: before
            )
            XCTAssertEqual(result.kind, 0)
            XCTAssertEqual(result.progressBits, sample.relocatedInventoryAfter)
            XCTAssertEqual(result.scores.first.bytes, score.firstAfter)
            XCTAssertEqual(result.scores.second.bytes, score.secondAfter)
        }
    }

    func testPrivateNonzeroProgressBranchesWhenProvided() throws {
        guard let directory = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_RECORD_ACCUMULATION_DIR"
        ] else { throw XCTSkip("Set the ignored nonzero-progress branch reports") }
        struct Branch: Decodable {
            let validatedManualFullRAMFrames: Int
            let validatedManualFullCPUFrames: Int
            let scoreRoutineEntries: Int
            let pureScoreStepMatches: Int
            let recordRemovedAtEnd: Bool
            let lifeChangedWrites: Int
        }
        struct Probe: Decodable {
            let comparisonFrames: Int
            let recordRemovalFrame: Int
            let selectedRecordKind: UInt8
            let inventoryBefore: UInt8
            let controlInventoryAfter: UInt8
            let relocatedInventoryAfter: UInt8
            let addedInventoryBits: UInt8
            let originalPlayerAndOtherGlobalBytesUntouched: Bool
            let control: Branch
            let relocated: Branch
        }
        struct Score: Decodable {
            let activePlayer: UInt8
            let pointsUpper: UInt8
            let pointsLower: UInt8
            let firstBefore: [UInt8]
            let secondBefore: [UInt8]
            let firstAfter: [UInt8]
            let secondAfter: [UInt8]
            let resultMatchesPureHelper: Bool
        }
        struct Capture: Decodable {
            let control: [Score]
            let relocated: [Score]
        }
        let base = URL(fileURLWithPath: directory)
        for (id, progress, bit) in [
            (2, UInt8(1), UInt8(2)),
            (1, 3, 4),
            (0, 7, 8),
            (3, 14, 1),
        ] {
            let suffix = "id-\(id)-progress-\(progress)"
            let probe = try JSONDecoder().decode(
                Probe.self, from: Data(contentsOf:
                    base.appendingPathComponent("quest-accumulation-\(suffix).json")
                )
            )
            let capture = try JSONDecoder().decode(
                Capture.self, from: Data(contentsOf:
                    base.appendingPathComponent(
                        "quest-relocation-score-operands-\(suffix)-private.json"
                    )
                )
            )
            XCTAssertEqual(probe.comparisonFrames, 30)
            XCTAssertEqual(probe.recordRemovalFrame, 792)
            XCTAssertEqual(probe.selectedRecordKind, UInt8(147 - id))
            XCTAssertEqual(probe.inventoryBefore, progress)
            XCTAssertEqual(probe.controlInventoryAfter, progress)
            XCTAssertEqual(probe.relocatedInventoryAfter, progress | bit)
            XCTAssertEqual(probe.addedInventoryBits, bit)
            XCTAssertFalse(probe.originalPlayerAndOtherGlobalBytesUntouched)
            for branch in [probe.control, probe.relocated] {
                XCTAssertEqual(branch.validatedManualFullRAMFrames, 30)
                XCTAssertEqual(branch.validatedManualFullCPUFrames, 30)
                XCTAssertEqual(branch.lifeChangedWrites, 0)
            }
            XCTAssertEqual(probe.control.scoreRoutineEntries, 0)
            XCTAssertEqual(probe.relocated.scoreRoutineEntries, 1)
            XCTAssertEqual(probe.relocated.pureScoreStepMatches, 1)
            XCTAssertTrue(probe.relocated.recordRemovedAtEnd)
            XCTAssertTrue(capture.control.isEmpty)
            XCTAssertEqual(capture.relocated.count, 1)
            let score = try XCTUnwrap(capture.relocated.first)
            XCTAssertEqual(score.activePlayer, 0)
            XCTAssertEqual(score.pointsUpper, 0x75)
            XCTAssertEqual(score.pointsLower, 0)
            XCTAssertTrue(score.resultMatchesPureHelper)
            let before = CapturedScoreState(
                first: try CapturedPackedScore(bytes: score.firstBefore),
                second: try CapturedPackedScore(bytes: score.secondBefore)
            )
            let result = try CapturedRecordAward.applyOnObservedHandler(
                recordKind: probe.selectedRecordKind, activePlayer: score.activePlayer,
                progressBits: progress, scores: before
            )
            XCTAssertEqual(result.progressBits, probe.relocatedInventoryAfter)
            XCTAssertEqual(result.scores.first.bytes, score.firstAfter)
            XCTAssertEqual(result.scores.second.bytes, score.secondAfter)
        }
    }
}
