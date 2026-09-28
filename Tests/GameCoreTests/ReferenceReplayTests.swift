import Foundation
import XCTest
@testable import GameCore

final class ReferenceReplayTests: XCTestCase {
    private func fixture(
        index: Int = 1, room: Int = 168,
        sha: String = WorldReference.supportedSnapshotSHA256,
        kind: Int? = nil
    ) throws -> Data {
        var frame: [String: Any] = [
            "index": index, "playerRoomID": room, "playerX": 57,
            "playerY": 112, "reportedLives": 1,
        ]
        if let kind { frame["playerKind"] = kind }
        return try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "snapshotSHA256": sha,
            "input": "q",
            "frames": [frame],
        ])
    }

    func testAcceptsSourceBackedActorFrame() throws {
        let replay = try ReferenceReplay.load(from: fixture())
        XCTAssertEqual(replay.frames[0].index, 1)
        XCTAssertEqual(replay.frames[0].playerRoomID, 168)
        XCTAssertNil(replay.frames[0].playerKind)
        XCTAssertEqual(try ReferenceReplay.load(from: fixture(kind: 42)).frames[0].playerKind, 42)
    }

    func testRejectsUnverifiedOrMalformedFrames() throws {
        XCTAssertThrowsError(try ReferenceReplay.load(from: fixture(index: 2)))
        XCTAssertThrowsError(try ReferenceReplay.load(from: fixture(room: 256)))
        XCTAssertThrowsError(try ReferenceReplay.load(from: fixture(kind: -1)))
        XCTAssertThrowsError(try ReferenceReplay.load(from: fixture(kind: 256)))
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

    func testPrivateFireObservationWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["SABRE_PRIVATE_FIRE_REPLAY"] else {
            throw XCTSkip("Set SABRE_PRIVATE_FIRE_REPLAY for local attack-state observation")
        }
        let replay = try ReferenceReplay.load(
            from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        XCTAssertEqual(replay.frameBoundaryMode, "reference-relative")
        XCTAssertEqual(replay.frames.count, 100)
        XCTAssertEqual(replay.schedule?.map(\.key), ["t"])
        for (index, kind) in [
            (20, 21), (21, 42), (23, 45), (27, 40),
            (31, 41), (35, 47), (40, 41), (41, 20),
        ] {
            XCTAssertEqual(replay.frames[index - 1].playerKind, kind)
        }
        XCTAssertTrue(replay.frames.allSatisfy {
            $0.playerRoomID == 168 && $0.playerX == 57 && $0.playerY == 112
        })
    }

    func testPrivateFireVsNoFireEncounterWhenProvided() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let firePath = environment["SABRE_PRIVATE_FIRE_ENCOUNTER"],
              let noFirePath = environment["SABRE_PRIVATE_NO_FIRE_ENCOUNTER"],
              let fireTracePath = environment["SABRE_PRIVATE_FIRE_ENTITY_TRACE"],
              let noFireTracePath = environment["SABRE_PRIVATE_NO_FIRE_ENTITY_TRACE"] else {
            throw XCTSkip("Set both private attack replays and entity traces")
        }
        let fire = try ReferenceReplay.load(
            from: Data(contentsOf: URL(fileURLWithPath: firePath))
        )
        let noFire = try ReferenceReplay.load(
            from: Data(contentsOf: URL(fileURLWithPath: noFirePath))
        )
        let fireTrace = try ReferenceEntityTrace.load(
            from: Data(contentsOf: URL(fileURLWithPath: fireTracePath))
        )
        let noFireTrace = try ReferenceEntityTrace.load(
            from: Data(contentsOf: URL(fileURLWithPath: noFireTracePath))
        )
        try fireTrace.validate(replay: fire)
        try noFireTrace.validate(replay: noFire)
        XCTAssertEqual(fire.frames.count, 190)
        XCTAssertEqual(noFire.frames.count, 190)
        let firstPlayerState = fire.frames.indices.first {
            fire.frames[$0].playerKind != noFire.frames[$0].playerKind
        }
        XCTAssertEqual(firstPlayerState.map { $0 + 1 }, 146)
        let firstEnemyState = fireTrace.trace.indices.first {
            fireTrace.trace[$0].fullEmulatorEntity.kind
                != noFireTrace.trace[$0].fullEmulatorEntity.kind
        }
        XCTAssertEqual(firstEnemyState.map { $0 + 1 }, 156)
        let firstEnemyPosition = fireTrace.trace.indices.first {
            let a = fireTrace.trace[$0].fullEmulatorEntity
            let b = noFireTrace.trace[$0].fullEmulatorEntity
            return a.x != b.x || a.y != b.y
        }
        XCTAssertEqual(firstEnemyPosition.map { $0 + 1 }, 159)
        XCTAssertEqual(fire.frames[163].playerKind, 36)
        XCTAssertEqual(noFire.frames[163].playerKind, 64)
        if let controlPath = environment["SABRE_PRIVATE_UNRELATED_REPLAY"],
           let controlTracePath = environment["SABRE_PRIVATE_UNRELATED_TRACE"] {
            let control = try ReferenceReplay.load(
                from: Data(contentsOf: URL(fileURLWithPath: controlPath))
            )
            let controlTrace = try ReferenceEntityTrace.load(
                from: Data(contentsOf: URL(fileURLWithPath: controlTracePath))
            )
            try controlTrace.validate(replay: control)
            XCTAssertEqual(control.frames.count, 190)
            XCTAssertEqual(control.frames[163].playerKind, 27)
            XCTAssertEqual(control.frames[169].playerKind, 64)
            XCTAssertEqual(controlTrace.trace[162].fullEmulatorEntity.x, 98)
            XCTAssertEqual(fireTrace.trace[162].fullEmulatorEntity.x, 86)
            XCTAssertFalse(fire.frames.contains {
                guard let kind = $0.playerKind else { return false }
                return (64...69).contains(kind)
            })
        }
    }
}
