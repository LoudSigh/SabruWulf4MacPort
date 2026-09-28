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
}
