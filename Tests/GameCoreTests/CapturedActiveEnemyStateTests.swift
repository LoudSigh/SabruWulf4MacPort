import Foundation
import XCTest
@testable import GameCore

final class CapturedActiveEnemyStateTests: XCTestCase {
    private func world() throws -> WorldReference {
        let rooms: [[String: Any]] = (0..<48).map { _ in
            ["placements": [[
                "graphicAddress": 0x70BC, "x": 40, "y": 136,
                "widthPixels": 120, "heightPixels": 8,
            ]]]
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 2,
            "snapshotSha256": WorldReference.supportedSnapshotSHA256,
            "width": 16, "height": 16,
            "layout": Array(repeating: 0, count: 256),
            "rooms": rooms,
        ])
        return try WorldReference.load(from: data, verifySource: false)
    }

    func testDirectionSpecificPositionKindAndTimer() throws {
        let world = try world()
        for (kind, velocity, count, finalX, finalTimer) in [
            (UInt8(110), 96, 2, 104, UInt8(7)),
            (UInt8(110), 48, 4, 104, UInt8(5)),
            (UInt8(108), -48, 8, 68, UInt8(1)),
        ] {
            var enemy = try CapturedActiveEnemyState(
                kind: kind, timer: 9, room: RoomID(8, 9),
                position: GridPoint(92, 130),
                velocityX: velocity, velocityY: 80
            )
            for _ in 0..<count {
                try enemy.advanceOnSourceUpdate(world: world)
            }
            XCTAssertEqual(enemy.kind, kind)
            XCTAssertEqual(enemy.timer, finalTimer)
            XCTAssertEqual(enemy.position, GridPoint(finalX, 135))
            if enemy.timer == 1 {
                XCTAssertThrowsError(try enemy.advanceOnSourceUpdate(world: world))
                XCTAssertEqual(enemy.position, GridPoint(finalX, 135))
            }
        }
    }

    func testRejectsUnmeasuredEntityStates() throws {
        for (kind, timer, room, velocity) in [
            (UInt8(8), UInt8(9), RoomID(8, 9), 96),
            (UInt8(108), UInt8(1), RoomID(8, 9), -48),
            (UInt8(108), UInt8(9), RoomID(8, 10), -48),
            (UInt8(108), UInt8(9), RoomID(8, 9), 32),
        ] {
            XCTAssertThrowsError(try CapturedActiveEnemyState(
                kind: kind, timer: timer, room: room,
                position: GridPoint(92, 130),
                velocityX: velocity, velocityY: 80
            ))
        }
    }

    func testCountdownCanPrecedeMotionAtDisplayBoundary() throws {
        var enemy = try CapturedActiveEnemyState(
            kind: 108, timer: 7, room: RoomID(8, 9),
            position: GridPoint(86, 135), velocityX: -48, velocityY: 80
        )
        try enemy.advanceCountdownOnSourceUpdate()
        XCTAssertEqual(enemy.kind, 108)
        XCTAssertEqual(enemy.timer, 6)
        XCTAssertEqual(enemy.position, GridPoint(86, 135))

        try enemy.advanceOnSourceUpdate(world: world(), countdownOccurred: false)
        XCTAssertEqual(enemy.kind, 109)
        XCTAssertEqual(enemy.timer, 6)
        XCTAssertEqual(enemy.position, GridPoint(83, 135))
    }

    func testPrivateEnemyStateParityWhenProvided() throws {
        guard let directory = ProcessInfo.processInfo.environment["SABRE_PRIVATE_ENTITY_TRACE_DIR"]
        else { throw XCTSkip("Set the private encounter-report directory") }
        struct Comparison: Decodable {
            let sourceUpdates: Int
            let matchingUpdates: Int
            let countdownOnlyUpdates: Int
            let updateFrames: [Int]
        }
        struct Report: Decodable {
            let framesCompared: Int
            let matchingRAMFrames: Int
            let activeEnemyComparison: Comparison
        }
        for (scenario, frames, countdownOnly) in [
            ("fire-before-contact", [160, 163, 167, 170, 173, 176, 179, 182], 1),
            ("no-fire-encounter", [159, 162], 0),
            ("unrelated-a-control", [159, 162, 166, 169], 2),
        ] {
            let file = URL(fileURLWithPath: directory)
                .appendingPathComponent("active-enemy-check-\(scenario)-190.json")
            let report = try JSONDecoder().decode(
                Report.self, from: Data(contentsOf: file)
            )
            XCTAssertEqual(report.framesCompared, 190)
            XCTAssertEqual(report.matchingRAMFrames, 190)
            XCTAssertEqual(report.activeEnemyComparison.sourceUpdates, frames.count)
            XCTAssertEqual(report.activeEnemyComparison.matchingUpdates, frames.count)
            XCTAssertEqual(report.activeEnemyComparison.updateFrames, frames)
            XCTAssertEqual(report.activeEnemyComparison.countdownOnlyUpdates, countdownOnly)
        }
    }
}
