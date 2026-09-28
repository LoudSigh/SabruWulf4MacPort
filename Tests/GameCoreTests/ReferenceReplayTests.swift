import Foundation
import XCTest
@testable import GameCore

final class ReferenceReplayTests: XCTestCase {
    private func fixture(
        index: Int = 1, room: Int = 168,
        sha: String = WorldReference.supportedSnapshotSHA256,
        kind: Int? = nil, lives: Int = 1
    ) throws -> Data {
        var frame: [String: Any] = [
            "index": index, "playerRoomID": room, "playerX": 57,
            "playerY": 112, "reportedLives": lives,
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
        XCTAssertEqual(try ReferenceReplay.load(from: fixture(lives: 0)).frames[0].reportedLives, 0)
    }

    func testRejectsUnverifiedOrMalformedFrames() throws {
        XCTAssertThrowsError(try ReferenceReplay.load(from: fixture(index: 2)))
        XCTAssertThrowsError(try ReferenceReplay.load(from: fixture(room: 256)))
        XCTAssertThrowsError(try ReferenceReplay.load(from: fixture(kind: -1)))
        XCTAssertThrowsError(try ReferenceReplay.load(from: fixture(kind: 256)))
        XCTAssertThrowsError(try ReferenceReplay.load(from: fixture(lives: -1)))
        XCTAssertThrowsError(try ReferenceReplay.load(from: fixture(lives: 10)))
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

    func testScheduledReplayAcceptsBoundedMenuReturnAndRejectsLargerRun() throws {
        let frames: [[String: Int]] = (1...801).map { index in
            [
                "index": index, "playerRoomID": 152,
                "playerX": 121, "playerY": 126,
                "reportedLives": index < 231 ? 1 : 0,
            ]
        }
        var payload: [String: Any] = [
            "schemaVersion": 2,
            "snapshotSHA256": WorldReference.supportedSnapshotSHA256,
            "frameBoundaryMode": "reference-relative",
            "input": "schedule",
            "schedule": [
                ["key": "w", "startFrame": 20, "endFrame": 30],
                ["key": "0", "startFrame": 530, "endFrame": 535],
            ],
            "frames": Array(frames.prefix(800)),
        ]
        let imported = try ReferenceReplay.load(
            from: JSONSerialization.data(withJSONObject: payload)
        )
        XCTAssertEqual(imported.frames.count, 800)
        XCTAssertEqual(imported.schedule?.map(\.key), ["w", "0"])
        XCTAssertEqual(imported.frames[230].reportedLives, 0)
        payload["frames"] = frames
        XCTAssertThrowsError(try ReferenceReplay.load(
            from: JSONSerialization.data(withJSONObject: payload)
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

    func testPrivateLongInjuryObservationWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["SABRE_PRIVATE_LONG_NO_FIRE_REPLAY"]
        else {
            throw XCTSkip("Set SABRE_PRIVATE_LONG_NO_FIRE_REPLAY for local life-byte observation")
        }
        let replay = try ReferenceReplay.load(
            from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        XCTAssertEqual(replay.frames.count, 600)
        XCTAssertEqual(replay.frameBoundaryMode, "reference-relative")
        XCTAssertEqual(replay.frames[163].playerKind, 64)
        XCTAssertEqual(replay.frames[164].playerKind, 65)
        XCTAssertEqual(replay.frames[229].playerKind, 65)
        XCTAssertEqual(replay.frames[229].reportedLives, 1)
        XCTAssertEqual(replay.frames[230].playerKind, 17)
        XCTAssertEqual(replay.frames[230].reportedLives, 0)
        XCTAssertEqual(replay.frames[317].playerKind, 70)
    }

    func testPrivateRestartAfterMenuWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["SABRE_PRIVATE_RESTART_REPLAY"]
        else {
            throw XCTSkip("Set SABRE_PRIVATE_RESTART_REPLAY for local new-start observation")
        }
        let replay = try ReferenceReplay.load(
            from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        XCTAssertEqual(replay.frameBoundaryMode, "reference-relative")
        XCTAssertEqual(replay.frames.count, 800)
        XCTAssertEqual(replay.schedule?.map(\.key), ["w", "e", "0"])
        let cleared = replay.frames[534]
        XCTAssertEqual(cleared.playerRoomID, 0)
        let restored = replay.frames[653]
        XCTAssertEqual(restored.playerRoomID, 168)
        for index in [659, 663, 699, 799] {
            let frame = replay.frames[index]
            XCTAssertEqual(frame.playerRoomID, 168)
            XCTAssertEqual(frame.playerX, 120)
            XCTAssertEqual(frame.playerY, 112)
            XCTAssertEqual(frame.playerKind, 16)
            XCTAssertEqual(frame.reportedLives, 4)
        }
    }
}
