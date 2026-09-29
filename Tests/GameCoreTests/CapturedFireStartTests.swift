import Foundation
import XCTest
@testable import GameCore

final class CapturedFireStartTests: XCTestCase {
    func testFiveBoundedSourceSelectedKinds() throws {
        for (before, after) in [
            (UInt8(21), UInt8(42)),
            (18, 36), (23, 46), (27, 38), (30, 44),
        ] {
            let result = try CapturedFireStart.begin(
                playerKind: before, playerByte5: 0x47
            )
            XCTAssertEqual(result.kind, after)
            XCTAssertEqual(result.sourceByte96AD, 24)
        }
    }

    func testRejectsUnsupportedActorAndUnreadyPlayer() throws {
        for (kind, byte5) in [
            (UInt8(0), UInt8(0x47)), (15, 0x47),
            (32, 0x47), (65, 0x47), (21, 0x46),
        ] {
            XCTAssertThrowsError(try CapturedFireStart.begin(
                playerKind: kind, playerByte5: byte5
            ))
        }
    }

    func testPrivateFiveExecutingFireEntriesWhenProvided() throws {
        guard let directory = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_FIRE_ENTRY_DIR"
        ] else { throw XCTSkip("Set the ignored fire-entry parity report directory") }
        struct Write: Decodable {
            let frame: Int
            let instructionAddress: Int
            let address: Int
            let previous: UInt8
            let value: UInt8
        }
        struct Report: Decodable {
            let framesCompared: Int
            let matchingRAMFrames: Int
            let playerStateWrites: [Write]
        }
        let base = URL(fileURLWithPath: directory)
        for (name, frame) in [
            ("t100", 21), ("q", 41), ("w", 41),
            ("e", 41), ("r", 41),
        ] {
            let report = try JSONDecoder().decode(Report.self, from: Data(
                contentsOf: base.appendingPathComponent(
                    "fire-from-\(name)-writes-100.json"
                )
            ))
            XCTAssertEqual(report.framesCompared, 100)
            XCTAssertEqual(report.matchingRAMFrames, 100)
            let writes = report.playerStateWrites.filter {
                $0.instructionAddress == 44487 && $0.address == 38658
            }
            XCTAssertEqual(writes.count, 1)
            let entry = try XCTUnwrap(writes.first)
            XCTAssertEqual(entry.frame, frame)
            XCTAssertEqual(
                try CapturedFireStart.begin(
                    playerKind: entry.previous, playerByte5: 0x47
                ).kind,
                entry.value
            )
        }
    }
}
