import Foundation
import XCTest
@testable import GameCore

final class CapturedItemContactTests: XCTestCase {
    func testSeparatelySelectedItemGeometryIgnoresEnemyArmingByte() {
        XCTAssertTrue(CapturedItemContact.overlaps(
            playerKind: 20, playerRoom: 168, playerX: 120, playerY: 112,
            suppressionFlag: 0, recordRoom: 168, recordX: 121, recordY: 112
        ))
        XCTAssertFalse(CapturedActorContact.overlaps(
            playerKind: 20, playerRoom: 168, playerX: 120, playerY: 112,
            playerByte5: 0, suppressionFlag: 0,
            otherRoom: 168, otherX: 121, otherY: 112,
            playerRightReach: 12, playerAboveReach: 12
        ))
    }

    func testDirectionalStrictBoundsAndStateGates() {
        func touches(kind: UInt8 = 20, room: UInt8 = 168, x: UInt8 = 120,
                     y: UInt8 = 112, suppressed: UInt8 = 0,
                     recordRoom: UInt8 = 168, recordX: UInt8 = 120,
                     recordY: UInt8 = 112) -> Bool {
            CapturedItemContact.overlaps(
                playerKind: kind, playerRoom: room, playerX: x, playerY: y,
                suppressionFlag: suppressed, recordRoom: recordRoom,
                recordX: recordX, recordY: recordY
            )
        }
        XCTAssertTrue(touches(x: 131))
        XCTAssertFalse(touches(x: 132))
        XCTAssertTrue(touches(recordX: 131))
        XCTAssertFalse(touches(recordX: 132))
        XCTAssertTrue(touches(kind: 40, recordX: 147))
        XCTAssertFalse(touches(kind: 40, recordX: 148))
        XCTAssertTrue(touches(y: 126))
        XCTAssertFalse(touches(y: 127))
        XCTAssertTrue(touches(recordY: 123))
        XCTAssertFalse(touches(recordY: 124))
        XCTAssertFalse(touches(suppressed: 1))
        XCTAssertFalse(touches(recordRoom: 152))
        XCTAssertFalse(touches(kind: 64))
    }

    func testPrivateFourPositiveAndSeventyTwoNegativeReturnsWhenProvided() throws {
        guard let directory = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_ITEM_CONTACT_DIR"
        ] else { throw XCTSkip("Set the ignored four-record item-contact report directory") }
        struct Branch: Decodable {
            let validatedManualFullRAMFrames: Int
            let itemContactCalls: Int
            let matchingItemContactReturns: Int
            let positiveItemContactReturns: Int
            let scoreRoutineEntries: Int
            let recordRemovedAtEnd: Bool
        }
        struct Probe: Decodable {
            let status: String
            let selectedRecordKind: UInt8
            let inventoryBefore: UInt8
            let relocatedInventoryAfter: UInt8
            let control: Branch
            let relocated: Branch
        }
        let base = URL(fileURLWithPath: directory)
        var positiveMatches = 0
        var negativeMatches = 0
        for id in 0..<4 {
            let positive = try JSONDecoder().decode(Probe.self, from: Data(
                contentsOf: base.appendingPathComponent(
                    "quest-item-contact-id-\(id).json"
                )
            ))
            let negative = try JSONDecoder().decode(Probe.self, from: Data(
                contentsOf: base.appendingPathComponent(
                    "quest-item-contact-negative-id-\(id).json"
                )
            ))
            XCTAssertEqual(positive.selectedRecordKind, UInt8(147 - id))
            XCTAssertEqual(negative.selectedRecordKind, positive.selectedRecordKind)
            XCTAssertEqual(positive.inventoryBefore, 0)
            XCTAssertEqual(negative.inventoryBefore, 0)
            XCTAssertEqual(positive.relocatedInventoryAfter, UInt8(1 << (3 - id)))
            XCTAssertEqual(negative.relocatedInventoryAfter, 0)
            for report in [positive, negative] {
                XCTAssertEqual(report.control.validatedManualFullRAMFrames, 30)
                XCTAssertEqual(report.relocated.validatedManualFullRAMFrames, 30)
                XCTAssertEqual(report.control.itemContactCalls, 0)
                XCTAssertFalse(report.control.recordRemovedAtEnd)
                XCTAssertEqual(report.relocated.itemContactCalls,
                               report.relocated.matchingItemContactReturns)
            }
            XCTAssertEqual(positive.relocated.itemContactCalls, 1)
            XCTAssertEqual(positive.relocated.positiveItemContactReturns, 1)
            XCTAssertEqual(positive.relocated.scoreRoutineEntries, 1)
            XCTAssertTrue(positive.relocated.recordRemovedAtEnd)
            XCTAssertEqual(negative.status, "negative-item-contact-no-award")
            XCTAssertEqual(negative.relocated.itemContactCalls, 18)
            XCTAssertEqual(negative.relocated.positiveItemContactReturns, 0)
            XCTAssertEqual(negative.relocated.scoreRoutineEntries, 0)
            XCTAssertFalse(negative.relocated.recordRemovedAtEnd)
            positiveMatches += positive.relocated.matchingItemContactReturns
            negativeMatches += negative.relocated.matchingItemContactReturns
        }
        XCTAssertEqual(positiveMatches, 4)
        XCTAssertEqual(negativeMatches, 72)
    }
}
