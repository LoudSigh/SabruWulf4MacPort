import XCTest
@testable import GameCore

final class GameStateTests: XCTestCase {
    func testWallsAndBoundsBlockMovement() {
        var game = GameState()
        game.move(.north)
        XCTAssertEqual(game.player, GridPoint(1, 0))
        game.move(.north)
        XCTAssertEqual(game.player, GridPoint(1, 0))
        game.move(.east)
        game.move(.south)
        game.move(.south)
        XCTAssertEqual(game.player, GridPoint(2, 1))
    }

    func testRoomTransitionAndReturn() {
        var game = GameState()
        for _ in 0..<3 { game.move(.east) }
        game.move(.north)
        game.move(.north)
        XCTAssertEqual(game.player, GridPoint(4, 0))
        game.move(.north)
        XCTAssertEqual(game.roomID, RoomID(0, 0))
        for _ in 0..<6 { game.move(.south) }
        game.move(.south)
        XCTAssertEqual(game.roomID, RoomID(0, 1))
        XCTAssertEqual(game.player, GridPoint(4, 0))
        game.move(.north)
        XCTAssertEqual(game.roomID, RoomID(0, 0))
        XCTAssertEqual(game.player, GridPoint(4, 6))
    }

    func testEastGateOnlyLeadsToAdjacentRoomAndWestEdgeBlocks() {
        var game = GameState()
        game.move(.west)
        XCTAssertEqual(game.player, GridPoint(0, 1))
        game.move(.west)
        XCTAssertEqual(game.player, GridPoint(0, 1))
        game.move(.south)
        game.move(.south)
        game.move(.west)
        XCTAssertEqual(game.roomID, RoomID(0, 0))

        game.move(.east)
        game.move(.north)
        game.move(.north)
        for _ in 0..<7 { game.move(.east) }
        XCTAssertEqual(game.player, GridPoint(8, 1))
        game.move(.south)
        game.move(.south)
        game.move(.east)
        XCTAssertEqual(game.roomID, RoomID(1, 0))
        XCTAssertEqual(game.player, GridPoint(0, 3))
        game.move(.west)
        XCTAssertEqual(game.roomID, RoomID(0, 0))
        XCTAssertEqual(game.player, GridPoint(8, 3))
    }

    func testCollectingItemIsPersistentAcrossRooms() {
        var game = GameState()
        for _ in 0..<5 { game.move(.east) }
        game.move(.south)
        XCTAssertEqual(game.player, GridPoint(6, 2))
        XCTAssertEqual(game.collected, [RoomID(0, 0)])
        game.reset()
        XCTAssertTrue(game.collected.isEmpty)
    }

    func testPauseFreezesInputAndSimulationAndResetRestoresState() {
        var game = GameState()
        game.togglePause()
        game.move(.east)
        game.tick()
        XCTAssertEqual(game.player, GridPoint(1, 1))
        XCTAssertEqual(game.tickCount, 0)
        game.togglePause()
        game.tick()
        XCTAssertEqual(game.tickCount, 1)
        game.reset()
        XCTAssertEqual(game.tickCount, 0)
        XCTAssertFalse(game.isPaused)
    }

    func testEnemyContactLosesHealthAndGrantsTemporaryProtection() {
        var game = GameState()
        for _ in 0..<4 { game.move(.south) }
        for _ in 0..<6 { game.move(.east) }
        XCTAssertEqual(game.health, 2)
        XCTAssertEqual(game.player, GridPoint(1, 1))
        XCTAssertEqual(game.invulnerability, 2)
    }

    func testEnemyPatrolIsDeterministicAndPauseFreezesIt() {
        var game = GameState()
        game.tick()
        XCTAssertEqual(game.enemy, GridPoint(6, 5))
        game.togglePause()
        game.tick()
        XCTAssertEqual(game.enemy, GridPoint(6, 5))
        game.togglePause()
        game.tick()
        XCTAssertEqual(game.enemy, GridPoint(7, 5))
    }
}
