import Foundation
import XCTest
@testable import GameCore

final class ReferenceReplayTests: XCTestCase {
    private func fixture(index: Int = 1, room: Int = 168, sha: String =
        WorldReference.supportedSnapshotSHA256) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "snapshotSHA256": sha,
            "input": "q",
            "frames": [
                ["index": index, "playerRoomID": room, "playerX": 57,
                 "playerY": 112, "reportedLives": 1]
            ],
        ])
    }

    func testAcceptsSourceBackedActorFrame() throws {
        let replay = try ReferenceReplay.load(from: fixture())
        XCTAssertEqual(replay.frames[0].index, 1)
        XCTAssertEqual(replay.frames[0].playerRoomID, 168)
    }

    func testRejectsUnverifiedOrMalformedFrames() throws {
        XCTAssertThrowsError(try ReferenceReplay.load(from: fixture(index: 2)))
        XCTAssertThrowsError(try ReferenceReplay.load(from: fixture(room: 256)))
        XCTAssertThrowsError(try ReferenceReplay.load(
            from: fixture(sha: String(repeating: "0", count: 64))
        ))
    }

    func testScheduledReplayAcceptsRoomTransitionAndRejectsInvalidIntervals() throws {
        var content: [String: Any] = [
            "schemaVersion": 2,
            "snapshotSHA256": WorldReference.supportedSnapshotSHA256,
            "input": "schedule",
            "schedule": [
                ["key": "w", "startFrame": 0, "endFrame": 1],
                ["key": "e", "startFrame": 1, "endFrame": 3],
            ],
            "frames": (1...3).map { index in
                [
                    "index": index, "playerRoomID": index == 3 ? 152 : 168,
                    "playerX": 121, "playerY": 42, "reportedLives": 1,
                ]
            },
        ]
        let replay = try ReferenceReplay.load(from: JSONSerialization.data(withJSONObject: content))
        XCTAssertEqual(replay.frames.last?.playerRoomID, 152)
        XCTAssertEqual(replay.schedule?.count, 2)
        content["schedule"] = [
            ["key": "w", "startFrame": 0, "endFrame": 2],
            ["key": "e", "startFrame": 1, "endFrame": 3],
        ]
        XCTAssertThrowsError(try ReferenceReplay.load(
            from: JSONSerialization.data(withJSONObject: content)
        ))
        content["schedule"] = []
        XCTAssertThrowsError(try ReferenceReplay.load(
            from: JSONSerialization.data(withJSONObject: content)
        ))
    }
}
