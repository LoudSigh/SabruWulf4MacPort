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

    func testObservedNewGameOriginDoesNotAlterCaptureOrigin() throws {
        let source = try world()
        let observed = try CapturedMovementState(
            world: source, origin: .observedNewGameReady
        )
        XCTAssertEqual(observed.room, RoomID(8, 10))
        XCTAssertEqual(observed.player, GridPoint(120, 112))
        XCTAssertEqual(observed.referenceFrameOffset, 790)
        XCTAssertEqual(observed.playerSpriteID, 16)
        XCTAssertEqual(try CapturedMovementState(world: source).player, GridPoint(57, 112))
        XCTAssertNil(try CapturedMovementState(world: source).playerSpriteID)
        var moved = observed
        for _ in 0..<10 { try moved.advance(holding: [.right]) }
        XCTAssertEqual(moved.player, GridPoint(136, 112))
        XCTAssertEqual(moved.frame + moved.referenceFrameOffset, 800)
        XCTAssertEqual(moved.playerSpriteID, 20)
        XCTAssertThrowsError(try moved.advance(holding: [.up]))
        XCTAssertThrowsError(try moved.advance())
        XCTAssertEqual(moved.frame, 10)
    }

    func testMixedNewGameInputOnlySwitchesAtMeasuredFrame18() throws {
        var state = try CapturedMovementState(
            world: world(), origin: .observedNewGameReady
        )
        for _ in 0..<17 { try state.advance(holding: [.right]) }
        XCTAssertThrowsError(try state.advance(holding: [.up]))
        XCTAssertEqual(state.frame, 17)
        try state.advance(holding: [.right])
        try state.advance(holding: [.up])
        XCTAssertThrowsError(try state.advance(holding: [.right]))
        XCTAssertEqual(state.frame, 19)
    }

    func testReversalOnlySwitchesAtMeasuredFrame18() throws {
        var state = try CapturedMovementState(
            world: world(), origin: .observedNewGameReady
        )
        for _ in 0..<17 { try state.advance(holding: [.right]) }
        XCTAssertThrowsError(try state.advance(holding: [.left]))
        try state.advance(holding: [.right])
        try state.advance(holding: [.left])
        XCTAssertThrowsError(try state.advance(holding: [.right]))
        XCTAssertEqual(state.frame, 19)
    }

    func testNorthThenLeftOnlySwitchesAtMeasuredFrame40() throws {
        var state = try CapturedMovementState(
            world: world(), origin: .observedNewGameReady
        )
        for _ in 0..<39 { try state.advance(holding: [.up]) }
        XCTAssertThrowsError(try state.advance(holding: [.left]))
        XCTAssertEqual(state.frame, 39)
        try state.advance(holding: [.up])
        try state.advance(holding: [.left])
        XCTAssertThrowsError(try state.advance(holding: [.up]))
        XCTAssertEqual(state.frame, 41)
    }

    func testPrivateMixedNewGamePathWhenProvided() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let worldPath = environment["SABRE_PRIVATE_WORLD"],
              let replayPath = environment["SABRE_PRIVATE_NEW_GAME_MIXED_REPLAY"] else {
            throw XCTSkip("Set private world and W/E post-setup replay for mixed parity")
        }

        let source = try WorldReference.load(
            from: Data(contentsOf: URL(fileURLWithPath: worldPath))
        )
        let replay = try ReferenceReplay.load(
            from: Data(contentsOf: URL(fileURLWithPath: replayPath))
        )
        XCTAssertEqual(replay.frames.count, 900)
        var state = try CapturedMovementState(
            world: source, origin: .observedNewGameReady
        )
        for sourceIndex in 790..<900 {
            let input: Set<OriginalAction> = sourceIndex < 808 ? [.right]
                : sourceIndex < 850 ? [.up] : []
            try state.advance(holding: input)
            let expected = replay.frames[sourceIndex]
            XCTAssertEqual(state.room.y * 16 + state.room.x, expected.playerRoomID)
            XCTAssertEqual(
                state.player, GridPoint(expected.playerX, expected.playerY),
                "W/E position at frame \(expected.index)"
            )
            if expected.index <= 866 {
                XCTAssertEqual(state.playerSpriteID, expected.playerKind)
            } else {
                XCTAssertNil(state.playerSpriteID)
            }
        }
    }

    func testPrivateEThenQWestArrivalWhenProvided() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let worldPath = environment["SABRE_PRIVATE_WORLD"],
              let replayPath = environment["SABRE_PRIVATE_E_Q_WEST_REPLAY"] else {
            throw XCTSkip("Set ignored world and source E/Q west-arrival replay")
        }
        let source = try WorldReference.load(
            from: Data(contentsOf: URL(fileURLWithPath: worldPath))
        )
        let replay = try ReferenceReplay.load(
            from: Data(contentsOf: URL(fileURLWithPath: replayPath))
        )
        XCTAssertEqual(replay.frames.count, 1050)
        XCTAssertEqual(replay.frameBoundaryMode, "reference-relative")
        var state = try CapturedMovementState(
            world: source, origin: .observedNewGameReady
        )
        for sourceIndex in 790..<921 {
            try state.advance(holding: sourceIndex < 830 ? [.up] : [.left])
            let expected = replay.frames[sourceIndex]
            guard state.room.y * 16 + state.room.x == expected.playerRoomID,
                  state.player == GridPoint(expected.playerX, expected.playerY) else {
                return XCTFail("E/Q movement first differs at source frame \(expected.index)")
            }
            guard state.playerSpriteID == expected.playerKind else {
                return XCTFail(
                    "E/Q sprite first differs at source frame \(expected.index): "
                        + "native \(String(describing: state.playerSpriteID)), "
                        + "source \(String(describing: expected.playerKind))"
                )
            }
        }
        XCTAssertEqual(state.frame, 131)
        XCTAssertEqual(state.room, RoomID(7, 9))
        XCTAssertThrowsError(try state.advance(holding: [.left])) { error in
            guard case CapturedMovementError.unsupportedRuntimeDivergence = error else {
                return XCTFail("Expected pre-injury bound, got \(error)")
            }
        }
    }

    func testPrivateReversedNewGamePathWhenProvided() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let worldPath = environment["SABRE_PRIVATE_WORLD"],
              let replayPath = environment["SABRE_PRIVATE_NEW_GAME_REVERSE_REPLAY"] else {
            throw XCTSkip("Set private world and W/Q post-setup replay")
        }
        let source = try WorldReference.load(
            from: Data(contentsOf: URL(fileURLWithPath: worldPath))
        )
        let replay = try ReferenceReplay.load(
            from: Data(contentsOf: URL(fileURLWithPath: replayPath))
        )
        XCTAssertEqual(replay.frames.count, 900)
        var state = try CapturedMovementState(
            world: source, origin: .observedNewGameReady
        )
        for sourceIndex in 790..<870 {
            let input: Set<OriginalAction> = sourceIndex < 808 ? [.right]
                : sourceIndex < 850 ? [.left] : []
            try state.advance(holding: input)
            let expected = replay.frames[sourceIndex]
            guard state.room.y * 16 + state.room.x == expected.playerRoomID,
                  state.player == GridPoint(expected.playerX, expected.playerY) else {
                return XCTFail("W/Q position first diverges at frame \(expected.index)")
            }
            if expected.index <= 850 {
                XCTAssertEqual(
                    state.playerSpriteID, expected.playerKind,
                    "W/Q sprite at frame \(expected.index)"
                )
            } else {
                XCTAssertNil(state.playerSpriteID)
            }
        }
        XCTAssertThrowsError(try state.advance()) { error in
            guard case CapturedMovementError.unsupportedRuntimeDivergence = error else {
                return XCTFail("Expected bounded W/Q divergence, got \(error)")
            }
        }
        XCTAssertEqual(state.frame, 80)
    }

    func testPrivateReverseContactBoundaryWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_NEW_GAME_REVERSE_CONTACT"
        ] else { throw XCTSkip("Set ignored W/Q contact report") }
        struct Contact: Decodable {
            let calls: Int
            let matchingCalls: Int
            let positiveFrames: [Int]
        }
        struct Write: Decodable {
            let frame: Int
            let actorAddress: Int
            let previous: Int
            let value: Int
        }
        struct Report: Decodable {
            let matchingRAMFrames: Int
            let contactComparison: Contact
            let actorStateWrites: [Write]
        }
        let report = try JSONDecoder().decode(
            Report.self, from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        XCTAssertEqual(report.matchingRAMFrames, 900)
        XCTAssertEqual(report.contactComparison.calls, 2651)
        XCTAssertEqual(report.contactComparison.matchingCalls, 2651)
        XCTAssertEqual(report.contactComparison.positiveFrames, [162, 298, 868])
        XCTAssertTrue(report.actorStateWrites.contains {
            $0.frame == 870 && $0.actorAddress == 38658
                && $0.previous == 19 && $0.value == 64
        })
    }

    func testPrivateObservedNewGameMovementWhenProvided() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let worldPath = environment["SABRE_PRIVATE_WORLD"],
              let replayPath = environment["SABRE_PRIVATE_NEW_GAME_REPLAY"] else {
            throw XCTSkip("Set private world and late W source replay for new-game parity")
        }
        let source = try WorldReference.load(
            from: Data(contentsOf: URL(fileURLWithPath: worldPath))
        )
        var paths: [(String, OriginalAction, String)] = [(replayPath, .right, "w")]
        if let directory = environment["SABRE_PRIVATE_NEW_GAME_REPLAY_DIR"] {
            for (key, direction) in [("q", OriginalAction.left), ("e", .up), ("r", .down)] {
                let path = URL(fileURLWithPath: directory)
                    .appendingPathComponent("replay-restart-ready-\(key)-900.json")
                paths.append((path.path, direction, key))
            }
        }
        for (path, direction, key) in paths {
            let replay = try ReferenceReplay.load(
                from: Data(contentsOf: URL(fileURLWithPath: path))
            )
            XCTAssertEqual(replay.frames.count, 900)
            var state = try CapturedMovementState(
                world: source, origin: .observedNewGameReady
            )
            let lastIndex = direction == .down ? 866 : 900
            for sourceIndex in 790..<lastIndex {
                try state.advance(holding: sourceIndex < 850 ? [direction] : [])
                let expected = replay.frames[sourceIndex]
                XCTAssertEqual(state.frame + state.referenceFrameOffset, expected.index)
                XCTAssertEqual(
                    state.room.y * 16 + state.room.x, expected.playerRoomID,
                    "\(key) frame \(expected.index)"
                )
                XCTAssertEqual(
                    state.player, GridPoint(expected.playerX, expected.playerY),
                    "\(key) frame \(expected.index)"
                )
                XCTAssertEqual(
                    state.playerSpriteID, expected.playerKind,
                    "\(key) sprite at frame \(expected.index)"
                )
            }
            XCTAssertThrowsError(try state.advance()) { error in
                switch error {
                case CapturedMovementError.unsupportedRuntimeDivergence where direction == .down:
                    break
                case CapturedMovementError.unsupportedTimeRange where direction != .down:
                    break
                default:
                    XCTFail("Expected bounded new-game slice, got \(error)")
                }
            }
            XCTAssertEqual(state.frame, lastIndex - 790)
        }
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
