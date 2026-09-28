import Foundation
import XCTest
@testable import GameCore

final class CapturedMovementTests: XCTestCase {
    private func world() throws -> WorldReference {
        let rooms: [[String: Any]] = (0..<48).map { _ in
            ["placements": [[
                "graphicAddress": 0x70BC, "x": 20, "y": 120,
                "widthPixels": 16, "heightPixels": 8,
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

    func testCapturedVelocityAndFrictionAreDeterministic() throws {
        var state = try CapturedMovementState(world: world())
        for _ in 0..<20 { try state.advance() }
        XCTAssertEqual(state.player, GridPoint(57, 112))
        for _ in 0..<20 { try state.advance(holding: [.right]) }
        XCTAssertEqual(state.player, GridPoint(103, 112))
        XCTAssertEqual(state.frame, 40)
        XCTAssertEqual(state.room, RoomID(8, 10))
    }

    func testNorthTransitionFreezesThenRebasesActor() throws {
        var state = try CapturedMovementState(world: world())
        for _ in 0..<100 where !state.transitioning {
            try state.advance(holding: [.up])
        }
        XCTAssertTrue(state.transitioning)
        XCTAssertEqual(state.room, RoomID(8, 9))
        let previous = state.player
        for _ in 0..<6 {
            try state.advance(holding: [.up])
            XCTAssertEqual(state.player, previous)
        }
        try state.advance(holding: [.up])
        XCTAssertFalse(state.transitioning)
        XCTAssertEqual(state.player, GridPoint(previous.x, 191))
    }

    func testVerifiedReturnFreezesThenRebasesActor() throws {
        var state = try CapturedMovementState(world: world())
        for _ in 0..<100 where state.room == RoomID(8, 10) {
            try state.advance(holding: [.up])
        }
        XCTAssertEqual(state.room, RoomID(8, 9))
        for _ in 0..<7 { try state.advance() }
        XCTAssertEqual(state.player.y, 191)
        for _ in 0..<100 where state.room == RoomID(8, 9) {
            try state.advance(holding: [.down])
        }
        XCTAssertEqual(state.room, RoomID(8, 10))
        let oldX = state.player.x
        let oldY = state.player.y
        for _ in 0..<5 {
            try state.advance(holding: [.down])
            XCTAssertEqual(state.player.y, oldY)
        }
        try state.advance(holding: [.down])
        XCTAssertEqual(state.player, GridPoint(oldX - 1, 39))
        try state.advance(holding: [.down])
        XCTAssertEqual(state.player.y, 39)
    }

    func testProvisionalWestExitAndEastReturnRebaseActor() throws {
        var state = try CapturedMovementState(world: world())
        for _ in 0..<100 where state.room == RoomID(8, 10) {
            try state.advance(holding: [.up])
        }
        for _ in 0..<7 { try state.advance() }
        for _ in 0..<100 where state.room == RoomID(8, 9) {
            try state.advance(holding: [.left])
        }
        XCTAssertEqual(state.room, RoomID(7, 9))
        let old = state.player
        for _ in 0..<6 {
            try state.advance(holding: [.left])
            XCTAssertEqual(state.player, old)
        }
        try state.advance(holding: [.left])
        XCTAssertEqual(state.player.x, 239)
        for _ in 0..<100 where state.room == RoomID(7, 9) {
            try state.advance(holding: [.right])
        }
        XCTAssertEqual(state.room, RoomID(8, 9))
        let eastEdge = state.player
        for _ in 0..<6 {
            try state.advance(holding: [.right])
            XCTAssertEqual(state.player, eastEdge)
        }
        try state.advance(holding: [.right])
        XCTAssertEqual(state.player.x, 0)
    }

    func testUnverifiedFireAndBoundariesFailWithoutAdvancing() throws {
        var state = try CapturedMovementState(world: world())
        XCTAssertThrowsError(try state.advance(holding: [.fire]))
        XCTAssertEqual(state.frame, 0)
        for _ in 0..<150 {
            let frame = state.frame
            do {
                try state.advance(holding: [.right])
            } catch CapturedMovementError.unsupportedBoundary {
                XCTAssertEqual(state.frame, frame)
                return
            }
        }
        XCTFail("Expected an unverified east exit to be rejected")
    }

    func testPrivateTransitionMatchesEverySourceFrameWhenProvided() throws {
        let environment = ProcessInfo.processInfo.environment
        let worldPath = environment["SABRE_PRIVATE_WORLD"]
        let replayPath = environment["SABRE_PRIVATE_REPLAY"]
        if worldPath == nil && replayPath == nil {
            throw XCTSkip("Set both SABRE_PRIVATE_WORLD and SABRE_PRIVATE_REPLAY for local parity")
        }
        guard let worldPath, let replayPath else {
            XCTFail("Both private parity input paths are required")
            return
        }
        let source = try WorldReference.load(
            from: Data(contentsOf: URL(fileURLWithPath: worldPath))
        )
        var paths: [(path: String, count: Int)] = [(replayPath, 180)]
        if let roundTrip = environment["SABRE_PRIVATE_ROUND_TRIP"] {
            paths.append((roundTrip, 200))
        }
        if let westExit = environment["SABRE_PRIVATE_WEST_EXIT"] {
            paths.append((westExit, 256))
        }
        if let eastReturn = environment["SABRE_PRIVATE_EAST_RETURN"] {
            paths.append((eastReturn, 279))
        }
        for (path, count) in paths {
            let replay = try ReferenceReplay.load(
                from: Data(contentsOf: URL(fileURLWithPath: path))
            )
            XCTAssertEqual(replay.frames.count, count)
            var state = try CapturedMovementState(world: source)
            for (offset, frame) in replay.frames.enumerated() {
                let key = replay.schedule?.first {
                    $0.startFrame <= offset && offset < $0.endFrame
                }?.key
                let actions: Set<OriginalAction>
                switch key {
                case "w": actions = [.right]
                case "e": actions = [.up]
                case "r": actions = [.down]
                case "q": actions = [.left]
                case nil: actions = []
                default:
                    XCTFail("Unsupported parity key \(key ?? "")")
                    return
                }
                try state.advance(holding: actions)
                XCTAssertEqual(state.frame, frame.index)
                XCTAssertEqual(state.room.y * 16 + state.room.x, frame.playerRoomID)
                XCTAssertEqual(state.player.x, frame.playerX)
                XCTAssertEqual(state.player.y, frame.playerY)
            }
        }
    }

    func testPrivateHeldDirectionsMatchEveryFrameWhenProvided() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["SABRE_PRIVATE_HELD_REPLAY_DIR"] else {
            throw XCTSkip("Set SABRE_PRIVATE_HELD_REPLAY_DIR for local four-direction parity")
        }
        guard let worldPath = environment["SABRE_PRIVATE_WORLD"] else {
            XCTFail("SABRE_PRIVATE_WORLD is required with held-direction replays")
            return
        }
        let source = try WorldReference.load(
            from: Data(contentsOf: URL(fileURLWithPath: worldPath))
        )
        for key in ["q", "w", "e", "r"] {
            let path = URL(fileURLWithPath: directory)
                .appendingPathComponent("hold-\(key)-150.json")
            let replay = try ReferenceReplay.load(from: Data(contentsOf: path))
            XCTAssertEqual(replay.frames.count, 150)
            XCTAssertEqual(replay.input, key)
            guard let action = OriginalAction.fromSpectrumKey(Character(key)) else {
                XCTFail("Unrecognized direction key")
                return
            }
            var state = try CapturedMovementState(world: source)
            for (offset, frame) in replay.frames.enumerated() {
                try state.advance(holding: offset >= 20 ? [action] : [])
                XCTAssertEqual(state.room.y * 16 + state.room.x, frame.playerRoomID)
                XCTAssertEqual(state.player.x, frame.playerX)
                XCTAssertEqual(state.player.y, frame.playerY)
            }
        }
    }
}
