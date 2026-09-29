import Foundation
import XCTest
@testable import GameCore

final class ReferenceEntityTraceTests: XCTestCase {
    private func replayFixture(x: Int, mode: String? = nil) throws -> Data {
        var value: [String: Any] = [
            "schemaVersion": 1,
            "snapshotSHA256": WorldReference.supportedSnapshotSHA256,
            "input": "q",
            "frames": [[
                "index": 1, "playerRoomID": 0, "playerX": x,
                "playerY": 11, "reportedLives": 1,
            ]],
        ]
        if let mode { value["frameBoundaryMode"] = mode }
        return try JSONSerialization.data(withJSONObject: value)
    }

    private func fixture(
        frameCount: Int = 1, manualX: Int = 3, mode: String? = nil
    ) throws -> Data {
        let frames: [[String: Any]] = (1...max(frameCount, 1)).map { index in
            [
                "index": index,
                "manualEntity": [
                    "kind": 7, "roomID": 0, "x": manualX, "y": 5,
                ],
                "fullEmulatorEntity": [
                    "kind": 7, "roomID": 0, "x": 8, "y": 5,
                ],
                "manualPlayer": ["roomID": 0, "x": 10, "y": 11],
                "fullEmulatorPlayer": ["roomID": 0, "x": 10, "y": 11],
            ]
        }
        var value: [String: Any] = [
            "schemaVersion": 1,
            "snapshotSHA256": WorldReference.supportedSnapshotSHA256,
            "framesCompared": frameCount,
            "trace": frames,
        ]
        if let mode { value["frameBoundaryMode"] = mode }
        return try JSONSerialization.data(withJSONObject: value)
    }

    func testImportsAndValidatesSyntheticEntityComparison() throws {
        let trace = try ReferenceEntityTrace.load(from: fixture())
        XCTAssertEqual(trace.observedSlot, 12)
        XCTAssertEqual(trace.trace[0].manualEntity.x, 3)
        XCTAssertEqual(trace.trace[0].fullEmulatorEntity.x, 8)
        let matching = try ReferenceReplay.load(from: replayFixture(x: 10))
        XCTAssertNoThrow(try trace.validate(replay: matching))
        let mismatched = try ReferenceReplay.load(from: replayFixture(x: 12))
        XCTAssertThrowsError(try trace.validate(replay: mismatched))
        let timed = try ReferenceEntityTrace.load(
            from: fixture(mode: "reference-relative")
        )
        XCTAssertThrowsError(try timed.validate(replay: matching))
        let matchingTiming = try ReferenceReplay.load(
            from: replayFixture(x: 10, mode: "reference-relative")
        )
        XCTAssertNoThrow(try timed.validate(replay: matchingTiming))
        XCTAssertThrowsError(try ReferenceEntityTrace.load(from: fixture(mode: "invalid")))
        XCTAssertThrowsError(try ReferenceReplay.load(from: replayFixture(x: 10, mode: "invalid")))
        XCTAssertThrowsError(try ReferenceEntityTrace.load(from: fixture(frameCount: 0)))
        XCTAssertThrowsError(try ReferenceEntityTrace.load(from: fixture(manualX: 256)))
        XCTAssertThrowsError(try ReferenceEntityTrace.load(
            from: Data(repeating: 0, count: 2_000_001)
        ))
    }

    private func overlapTrace(
        slot: Int = 18, manualX: Int = 124, sourceX: Int = 124
    ) throws -> Data {
        let frames: [[String: Any]] = (1...100).map { index in
            [
                "index": index,
                "manualEntity": ["kind": 7, "roomID": 168, "x": manualX, "y": 112],
                "fullEmulatorEntity": [
                    "kind": 7, "roomID": 168, "x": sourceX, "y": 112,
                ],
                "manualPlayer": ["roomID": 168, "x": 120, "y": 112],
                "fullEmulatorPlayer": ["roomID": 168, "x": 120, "y": 112],
            ]
        }
        return try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "snapshotSHA256": WorldReference.supportedSnapshotSHA256,
            "frameBoundaryMode": "reference-relative",
            "framesCompared": 100,
            "entitySlot": slot,
            "trace": frames,
        ])
    }

    func testOverlapTraceRejectsUnverifiedSyntheticState() throws {
        XCTAssertThrowsError(try ReferenceEntityTrace.load(from: overlapTrace())) {
            XCTAssertTrue($0.localizedDescription.contains("actor states differ"))
        }
        XCTAssertThrowsError(try ReferenceEntityTrace.load(from: overlapTrace(slot: 19)))
        XCTAssertThrowsError(try ReferenceEntityTrace.load(from: overlapTrace(sourceX: 125)))
    }

    func testPrivateWOverlapImportWhenProvided() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let tracePath = environment["SABRE_PRIVATE_OVERLAP_TRACE"],
              let replayPath = environment["SABRE_PRIVATE_OVERLAP_REPLAY"],
              let atlasPath = environment["SABRE_PRIVATE_SPRITE_ATLAS"] else {
            throw XCTSkip("Set the ignored W overlap trace, replay and sprite atlas paths")
        }
        let trace = try ReferenceEntityTrace.load(
            from: Data(contentsOf: URL(fileURLWithPath: tracePath))
        )
        let replay = try ReferenceReplay.load(
            from: Data(contentsOf: URL(fileURLWithPath: replayPath))
        )
        XCTAssertEqual(trace.observedSlot, 18)
        XCTAssertEqual(trace.trace.count, 100)
        XCTAssertNoThrow(try trace.validate(replay: replay))
        XCTAssertEqual(trace.trace[42...52].filter {
            $0.manualEntity.kind > 0
                && $0.manualEntity.roomID == $0.manualPlayer.roomID
        }.count, 11)
        let reformattedTrace = try JSONSerialization.data(
            withJSONObject: JSONSerialization.jsonObject(
                with: Data(contentsOf: URL(fileURLWithPath: tracePath))
            ), options: [.sortedKeys]
        )
        XCTAssertNoThrow(try ReferenceEntityTrace.load(from: reformattedTrace)
            .validate(replay: replay))
        var wrongSchedule = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: URL(
                fileURLWithPath: replayPath
            ))) as? [String: Any]
        )
        wrongSchedule["schedule"] = [[
            "key": "q", "startFrame": 20, "endFrame": 40,
        ]]
        XCTAssertThrowsError(try trace.validate(
            replay: ReferenceReplay.load(from:
                JSONSerialization.data(withJSONObject: wrongSchedule)
            )
        )) {
            XCTAssertTrue($0.localizedDescription.contains("matching gameplay replay"))
        }
        var missingID = wrongSchedule
        missingID["schedule"] = [[
            "key": "w", "startFrame": 20, "endFrame": 40,
        ]]
        var alteredFrames = try XCTUnwrap(missingID["frames"] as? [[String: Any]])
        alteredFrames[42].removeValue(forKey: "playerKind")
        missingID["frames"] = alteredFrames
        XCTAssertThrowsError(try trace.validate(
            replay: ReferenceReplay.load(from:
                JSONSerialization.data(withJSONObject: missingID)
            )
        ))
        alteredFrames = try XCTUnwrap(wrongSchedule["frames"] as? [[String: Any]])
        let originalID = try XCTUnwrap(alteredFrames[42]["playerKind"] as? Int)
        alteredFrames[42]["playerKind"] = (originalID + 1) % SpriteAtlas.spriteCount
        wrongSchedule["schedule"] = [[
            "key": "w", "startFrame": 20, "endFrame": 40,
        ]]
        wrongSchedule["frames"] = alteredFrames
        XCTAssertThrowsError(try trace.validate(
            replay: ReferenceReplay.load(from:
                JSONSerialization.data(withJSONObject: wrongSchedule)
            )
        )) {
            XCTAssertTrue($0.localizedDescription.contains("bitmap IDs differ"))
        }
        var alteredTrace = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: tracePath))
        ) as? [String: Any])
        var traceFrames = try XCTUnwrap(alteredTrace["trace"] as? [[String: Any]])
        var actor = try XCTUnwrap(traceFrames[42]["manualEntity"] as? [String: Int])
        actor["x"] = (try XCTUnwrap(actor["x"]) + 1) % 256
        traceFrames[42]["manualEntity"] = actor
        traceFrames[42]["fullEmulatorEntity"] = actor
        alteredTrace["trace"] = traceFrames
        XCTAssertThrowsError(try ReferenceEntityTrace.load(from:
            JSONSerialization.data(withJSONObject: alteredTrace)
        )) {
            XCTAssertTrue($0.localizedDescription.contains("actor states differ"))
        }
        let atlas = try SpriteAtlas.load(
            from: Data(contentsOf: URL(fileURLWithPath: atlasPath))
        )
        var pixelChecks = 0
        var changedBits = 0
        for offset in 42...52 {
            let source = trace.trace[offset]
            let playerKind = try XCTUnwrap(replay.frames[offset].playerKind)
            let playerMask = try XCTUnwrap(atlas.mask(at: playerKind))
            let otherMask = try XCTUnwrap(atlas.mask(at: source.manualEntity.kind))
            let player = CapturedActorSprite(
                mask: playerMask,
                actorAt: GridPoint(
                    replay.frames[offset].playerX, replay.frames[offset].playerY
                )
            )
            let other = CapturedActorSprite(
                mask: otherMask,
                actorAt: GridPoint(source.manualEntity.x, source.manualEntity.y)
            )
            let projected = CapturedOverlapBitmap.xorPlayerRectangle(
                player: player, overlapping: other
            )
            pixelChecks += projected.count
            changedBits += zip(projected, player.screenPixels())
                .filter { $0.0 != $0.1 }.count
        }
        XCTAssertEqual(pixelChecks, 3776)
        XCTAssertEqual(changedBits, 64)
    }

    func testPrivateEntityCollisionFrameWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["SABRE_PRIVATE_ENTITY_TRACE"] else {
            throw XCTSkip("Set SABRE_PRIVATE_ENTITY_TRACE for local entity-route comparison")
        }
        let trace = try ReferenceEntityTrace.load(
            from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        XCTAssertEqual(trace.framesCompared, 256)
        let encounter = trace.trace[162]
        XCTAssertEqual(encounter.index, 163)
        XCTAssertEqual(encounter.fullEmulatorEntity.roomID, 152)
        XCTAssertEqual(encounter.fullEmulatorEntity.x, 104)
        XCTAssertEqual(encounter.manualEntity.x, 161)
        if let replayPath = ProcessInfo.processInfo.environment["SABRE_PRIVATE_WEST_EXIT"] {
            let replay = try ReferenceReplay.load(
                from: Data(contentsOf: URL(fileURLWithPath: replayPath))
            )
            XCTAssertNoThrow(try trace.validate(replay: replay))
        }
        let environment = ProcessInfo.processInfo.environment
        if let relativeTrace = environment["SABRE_PRIVATE_ENTITY_TRACE_REFERENCE"],
           let relativeReplay = environment["SABRE_PRIVATE_WEST_REFERENCE"] {
            let restored = try ReferenceEntityTrace.load(
                from: Data(contentsOf: URL(fileURLWithPath: relativeTrace))
            )
            let replay = try ReferenceReplay.load(
                from: Data(contentsOf: URL(fileURLWithPath: relativeReplay))
            )
            XCTAssertEqual(restored.frameBoundaryMode, "reference-relative")
            XCTAssertNoThrow(try restored.validate(replay: replay))
            XCTAssertThrowsError(try trace.validate(replay: replay))
        }
    }
}
