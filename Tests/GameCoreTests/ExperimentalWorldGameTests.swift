import Foundation
import XCTest
@testable import GameCore

final class ExperimentalWorldGameTests: XCTestCase {
    private func fixtures() throws -> (WorldReference, CapturedPlacementState) {
        let rooms: [[String: Any]] = (0..<48).map { _ in
            ["placements": [[
                "graphicAddress": 0x70BC, "x": 20, "y": 120,
                "widthPixels": 16, "heightPixels": 8,
            ]]]
        }
        let worldData = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 2,
            "snapshotSha256": WorldReference.supportedSnapshotSHA256,
            "width": 16, "height": 16,
            "layout": Array(repeating: 0, count: 256),
            "rooms": rooms,
        ])
        let world = try WorldReference.load(from: worldData, verifySource: false)
        let placementData = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "snapshotSHA256": WorldReference.supportedSnapshotSHA256,
            "sourceFrame": 656,
            "records": [
                ["id": 0, "spriteID": 144, "roomID": 168, "x": 126, "y": 112],
                ["id": 1, "spriteID": 145, "roomID": 152, "x": 126, "y": 112],
                ["id": 2, "spriteID": 146, "roomID": 151, "x": 126, "y": 112],
                ["id": 3, "spriteID": 147, "roomID": 136, "x": 126, "y": 112],
            ],
        ])
        return (world, try CapturedPlacementState.load(
            from: placementData, world: world
        ))
    }

    func testCollectsOneNearbyRecordOnceAndKeepsScore() throws {
        let (world, placements) = try fixtures()
        var game = try ExperimentalWorldGame(world: world, placements: placements)
        XCTAssertEqual(game.room, WorldReference.capturedGameplayRoom)
        XCTAssertEqual(game.player, GridPoint(120, 112))
        try game.advance(holding: [.right])
        XCTAssertEqual(game.progressBits, 1)
        XCTAssertEqual(game.collectedRecordIDs, [0])
        XCTAssertEqual(game.scores.first.decimalValue, 7500)
        for _ in 0..<12 { try game.advance(holding: [.right]) }
        XCTAssertEqual(game.collectedRecordIDs, [0])
        XCTAssertEqual(game.scores.first.decimalValue, 7500)
    }

    func testNorthExitPauseAndUnsupportedInput() throws {
        let (world, placements) = try fixtures()
        var game = try ExperimentalWorldGame(world: world, placements: placements)
        XCTAssertThrowsError(try game.advance(holding: [.fire]))
        XCTAssertThrowsError(try game.advance(holding: [.left, .up]))
        XCTAssertEqual(game.frame, 0)
        game.togglePause()
        try game.advance(holding: [.up])
        XCTAssertEqual(game.frame, 0)
        game.togglePause()
        for _ in 0..<40 { try game.advance(holding: [.up]) }
        XCTAssertEqual(game.room, RoomID(8, 9))
        XCTAssertGreaterThan(game.frame, 0)
    }

    func testPrivateHealthyEThenQMovementWhenProvided() throws {
        guard let directory = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_REFERENCE_DIR"
        ] else { throw XCTSkip("Set the ignored verified world/replay directory") }
        let bundle = try PrivateReferenceBundle.load(
            from: URL(fileURLWithPath: directory, isDirectory: true)
        )
        var game = try ExperimentalWorldGame(
            world: bundle.world, placements: bundle.placements
        )
        for step in 0..<131 {
            try game.advance(holding: [step < 40 ? .up : .left])
            let source = bundle.replay.frames[790 + step]
            XCTAssertEqual(
                game.room.y * 16 + game.room.x, source.playerRoomID,
                "source frame \(source.index)"
            )
            XCTAssertEqual(game.player.x, source.playerX, "source frame \(source.index)")
            XCTAssertEqual(game.player.y, source.playerY, "source frame \(source.index)")
        }
        XCTAssertEqual(game.room, RoomID(7, 9))
        XCTAssertEqual(game.progressBits, 0)
    }

    func testPrivateExtendedExplorationStaysInWorldWhenProvided() throws {
        guard let directory = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_REFERENCE_DIR"
        ] else { throw XCTSkip("Set the ignored verified world directory") }
        let bundle = try PrivateReferenceBundle.load(
            from: URL(fileURLWithPath: directory, isDirectory: true)
        )
        var game = try ExperimentalWorldGame(
            world: bundle.world, placements: bundle.placements
        )
        let directions: [OriginalAction] = [
            .up, .left, .down, .left, .up, .right, .up, .left,
        ]
        var visited: Set<RoomID> = [game.room]
        for step in 0..<2_000 {
            try game.advance(holding: [directions[(step / 125) % directions.count]])
            visited.insert(game.room)
            XCTAssertNotNil(bundle.world.roomType(at: game.room))
            XCTAssertTrue((0..<240).contains(game.player.x))
            XCTAssertTrue((39..<192).contains(game.player.y))
        }
        XCTAssertGreaterThanOrEqual(visited.count, 2)
        XCTAssertEqual(game.frame, 2_000)
    }
}
