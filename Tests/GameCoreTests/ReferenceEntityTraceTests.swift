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
