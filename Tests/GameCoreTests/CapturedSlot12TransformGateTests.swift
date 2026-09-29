import Foundation
import XCTest
@testable import GameCore

final class CapturedSlot12TransformGateTests: XCTestCase {
    func testPlayerKindBandAndUnsupportedActor() throws {
        for kind: UInt8 in [16, 31, 32, 47] {
            XCTAssertFalse(try CapturedSlot12TransformGate.selectsKindSequence(
                actorKind: 109, actorRoom: 152,
                playerKind: kind, playerRoom: 152
            ))
        }
        for kind: UInt8 in [0, 15, 48, 65, 255] {
            XCTAssertTrue(try CapturedSlot12TransformGate.selectsKindSequence(
                actorKind: 109, actorRoom: 152,
                playerKind: kind, playerRoom: 152
            ))
        }
        XCTAssertThrowsError(try CapturedSlot12TransformGate.selectsKindSequence(
            actorKind: 8, actorRoom: 152, playerKind: 65, playerRoom: 152
        ))
        XCTAssertThrowsError(try CapturedSlot12TransformGate.selectsKindSequence(
            actorKind: 109, actorRoom: 151, playerKind: 65, playerRoom: 152
        ))
    }

    func testPrivateFourSourceBranchesWhenProvided() throws {
        guard let directory = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_SLOT12_TRANSFORM_DIR"
        ] else { throw XCTSkip("Set the ignored RAM-checked slot-12 gate reports") }
        struct Comparison: Decodable {
            let sourceVisits: Int
            let matchingBranches: Int
            let selectedFrames: [Int]
            let unselectedFrames: [Int]
            let selectedPlayerKinds: [Int]
            let unselectedPlayerKinds: [Int]
        }
        struct Report: Decodable {
            let framesCompared: Int
            let matchingRAMFrames: Int
            let slot12TransformComparison: Comparison
        }
        let base = URL(fileURLWithPath: directory)
        var firePrefix: [Int] = []
        for (name, frames, expectedVisits) in [
            ("fire-190", 190, 11),
            ("no-fire-190", 190, 2),
            ("unrelated-190", 190, 4),
            ("fire-250", 250, 25),
        ] {
            let report = try JSONDecoder().decode(
                Report.self, from: Data(contentsOf:
                    base.appendingPathComponent("slot12-gate-verified-\(name).json")
                )
            )
            XCTAssertEqual(report.framesCompared, frames)
            XCTAssertEqual(report.matchingRAMFrames, frames)
            let gate = report.slot12TransformComparison
            XCTAssertEqual(gate.sourceVisits, expectedVisits)
            XCTAssertEqual(gate.matchingBranches, expectedVisits)
            XCTAssertEqual(gate.unselectedFrames.count + gate.selectedFrames.count,
                           expectedVisits)
            XCTAssertTrue(gate.unselectedPlayerKinds.allSatisfy {
                (16...47).contains($0)
            })
            XCTAssertEqual(gate.unselectedPlayerKinds.count, gate.unselectedFrames.count)
            if name == "fire-190" { firePrefix = gate.unselectedFrames }
            if name == "fire-250" {
                XCTAssertEqual(Array(gate.unselectedFrames.prefix(11)), firePrefix)
                XCTAssertEqual(gate.selectedFrames, [234])
                XCTAssertEqual(gate.selectedPlayerKinds, [65])
            } else {
                XCTAssertTrue(gate.selectedFrames.isEmpty)
                XCTAssertTrue(gate.selectedPlayerKinds.isEmpty)
            }
        }
    }

    func testPrivateEntryAndCoincidentScoreWhenProvided() throws {
        guard let directory = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_SLOT12_TRANSFORM_DIR"
        ] else { throw XCTSkip("Set the ignored 250-frame transform entry") }
        struct Entry: Decodable {
            let frame: Int
            let actorKind: Int
            let actorTimer: Int
            let actorRoom: Int
            let actorX: Int
            let actorY: Int
            let playerKind: Int
        }
        struct Score: Decodable {
            let calls: Int
            let matchingCalls: Int
            let frames: [Int]
        }
        struct Report: Decodable {
            let matchingRAMFrames: Int
            let slot12TransformEntries: [Entry]
            let scoreComparison: Score
        }
        let report = try JSONDecoder().decode(
            Report.self, from: Data(contentsOf:
                URL(fileURLWithPath: directory)
                    .appendingPathComponent("slot12-gate-entry-score-250.json")
            )
        )
        XCTAssertEqual(report.matchingRAMFrames, 250)
        XCTAssertEqual(report.slot12TransformEntries.count, 1)
        let entry = try XCTUnwrap(report.slot12TransformEntries.first)
        XCTAssertEqual(entry.frame, 234)
        XCTAssertEqual(entry.actorKind, 109)
        XCTAssertEqual(entry.actorTimer, 254)
        XCTAssertEqual(entry.actorRoom, 152)
        XCTAssertEqual(entry.actorX, 53)
        XCTAssertEqual(entry.actorY, 135)
        XCTAssertEqual(entry.playerKind, 65)
        XCTAssertEqual(report.scoreComparison.calls, 3)
        XCTAssertEqual(report.scoreComparison.matchingCalls, 3)
        XCTAssertEqual(report.scoreComparison.frames, [229, 230, 235])
    }
}
