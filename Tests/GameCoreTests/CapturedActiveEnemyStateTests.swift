import Foundation
import XCTest
@testable import GameCore

final class CapturedActiveEnemyStateTests: XCTestCase {
    private func world() throws -> WorldReference {
        let rooms: [[String: Any]] = (0..<48).map { _ in
            ["placements": [[
                "graphicAddress": 0x70BC, "x": 40, "y": 136,
                "widthPixels": 120, "heightPixels": 8,
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

    func testDirectionSpecificPositionKindAndTimer() throws {
        let world = try world()
        for (kind, velocity, count, finalX, finalTimer) in [
            (UInt8(110), 96, 2, 104, UInt8(7)),
            (UInt8(110), 48, 4, 104, UInt8(5)),
            (UInt8(108), -48, 8, 68, UInt8(1)),
        ] {
            var enemy = try CapturedActiveEnemyState(
                kind: kind, timer: 9, room: RoomID(8, 9),
                position: GridPoint(92, 130),
                velocityX: velocity, velocityY: 80
            )
            for _ in 0..<count {
                try enemy.advanceOnSourceUpdate(world: world)
            }
            XCTAssertEqual(enemy.kind, kind)
            XCTAssertEqual(enemy.timer, finalTimer)
            XCTAssertEqual(enemy.position, GridPoint(finalX, 135))
            if enemy.timer == 1 {
                XCTAssertThrowsError(try enemy.advanceOnSourceUpdate(world: world))
                XCTAssertEqual(enemy.position, GridPoint(finalX, 135))
            }
        }
    }

    func testRejectsUnmeasuredEntityStates() throws {
        for (kind, timer, room, velocity) in [
            (UInt8(8), UInt8(9), RoomID(8, 9), 96),
            (UInt8(108), UInt8(1), RoomID(8, 9), -48),
            (UInt8(108), UInt8(9), RoomID(8, 10), -48),
            (UInt8(108), UInt8(9), RoomID(8, 9), 32),
        ] {
            XCTAssertThrowsError(try CapturedActiveEnemyState(
                kind: kind, timer: timer, room: room,
                position: GridPoint(92, 130),
                velocityX: velocity, velocityY: 80
            ))
        }
    }

    func testCountdownCanPrecedeMotionAtDisplayBoundary() throws {
        var enemy = try CapturedActiveEnemyState(
            kind: 108, timer: 7, room: RoomID(8, 9),
            position: GridPoint(86, 135), velocityX: -48, velocityY: 80
        )
        try enemy.advanceCountdownOnSourceUpdate()
        XCTAssertEqual(enemy.kind, 108)
        XCTAssertEqual(enemy.timer, 6)
        XCTAssertEqual(enemy.position, GridPoint(86, 135))

        try enemy.advanceOnSourceUpdate(world: world(), countdownOccurred: false)
        XCTAssertEqual(enemy.kind, 109)
        XCTAssertEqual(enemy.timer, 6)
        XCTAssertEqual(enemy.position, GridPoint(83, 135))
    }

    func testTerminalCountdownMayPrecedeItsLastMotion() throws {
        var enemy = try CapturedActiveEnemyState(
            kind: 109, timer: 2, room: RoomID(8, 9),
            position: GridPoint(71, 135), velocityX: -48, velocityY: 80
        )
        try enemy.advanceCountdownOnSourceUpdate()
        XCTAssertEqual(enemy.timer, 1)
        try enemy.advanceOnSourceUpdate(world: world(), countdownOccurred: false)
        XCTAssertEqual(enemy.position, GridPoint(68, 135))
        XCTAssertEqual(enemy.kind, 108)
        XCTAssertThrowsError(try enemy.advanceOnSourceUpdate(
            world: world(), countdownOccurred: false
        ))
        try enemy.expireOnSourceUpdate(rngByte: 69, clockByte: 38)
        XCTAssertEqual(enemy.timer, 13)
    }

    func testPrivateEnemyStateParityWhenProvided() throws {
        guard let directory = ProcessInfo.processInfo.environment["SABRE_PRIVATE_ENTITY_TRACE_DIR"]
        else { throw XCTSkip("Set the private encounter-report directory") }
        struct Comparison: Decodable {
            let sourceUpdates: Int
            let matchingUpdates: Int
            let countdownOnlyUpdates: Int
            let updateFrames: [Int]
        }
        struct Report: Decodable {
            let framesCompared: Int
            let matchingRAMFrames: Int
            let activeEnemyComparison: Comparison
        }
        for (scenario, frames, countdownOnly) in [
            ("fire-before-contact", [160, 163, 167, 170, 173, 176, 179, 182], 1),
            ("no-fire-encounter", [159, 162], 0),
            ("unrelated-a-control", [159, 162, 166, 169], 2),
        ] {
            let file = URL(fileURLWithPath: directory)
                .appendingPathComponent("active-enemy-check-\(scenario)-190.json")
            let report = try JSONDecoder().decode(
                Report.self, from: Data(contentsOf: file)
            )
            XCTAssertEqual(report.framesCompared, 190)
            XCTAssertEqual(report.matchingRAMFrames, 190)
            XCTAssertEqual(report.activeEnemyComparison.sourceUpdates, frames.count)
            XCTAssertEqual(report.activeEnemyComparison.matchingUpdates, frames.count)
            XCTAssertEqual(report.activeEnemyComparison.updateFrames, frames)
            XCTAssertEqual(report.activeEnemyComparison.countdownOnlyUpdates, countdownOnly)
        }
    }

    func testPrivateEnemyWriteOrderingWhenProvided() throws {
        guard let directory = ProcessInfo.processInfo.environment["SABRE_PRIVATE_ENTITY_TRACE_DIR"]
        else { throw XCTSkip("Set the private encounter-report directory") }
        struct Write: Decodable {
            let frame: Int
            let instructionAddress: Int
            let cycle: Int
            let address: Int
            let previous: Int
            let value: Int
        }
        struct Report: Decodable {
            let matchingRAMFrames: Int
            let entityStateWrites: [Write]
        }
        for (scenario, expectedMoves, expectedCountdowns) in [
            ("fire-before-contact", 8, 11),
            ("no-fire-encounter", 2, 2),
            ("unrelated-a-control", 4, 4),
        ] {
            let file = URL(fileURLWithPath: directory)
                .appendingPathComponent("entity-writes-\(scenario)-190.json")
            let report = try JSONDecoder().decode(
                Report.self, from: Data(contentsOf: file)
            )
            XCTAssertEqual(report.matchingRAMFrames, 190)
            let writes = report.entityStateWrites
            let countdowns = writes.filter {
                $0.instructionAddress == 42346 && $0.address == 38804
                    && $0.previous == $0.value + 1
            }
            let kindToggles = writes.filter {
                $0.instructionAddress == 42388 && $0.address == 38802
            }
            XCTAssertEqual(countdowns.count, expectedCountdowns)
            XCTAssertEqual(kindToggles.count, expectedMoves)
            for toggle in kindToggles {
                let countdown = try XCTUnwrap(countdowns.last { $0.cycle < toggle.cycle })
                XCTAssertLessThan(toggle.cycle - countdown.cycle, 20_000)
                XCTAssertEqual(toggle.previous ^ toggle.value, 1)
                XCTAssertTrue(writes.contains {
                    $0.instructionAddress == 42391 && $0.frame == toggle.frame
                })
            }
        }
    }

    func testTwoDifferentSourceTimerExpiriesWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["SABRE_PRIVATE_FIRE_EXTENDED_WRITES"]
        else { throw XCTSkip("Set the private 250-frame fire write trace") }
        struct Write: Decodable {
            let frame: Int
            let instructionAddress: Int
            let address: Int
            let previous: Int
            let value: Int
        }
        struct Report: Decodable {
            let matchingRAMFrames: Int
            let entityStateWrites: [Write]
        }
        let report = try JSONDecoder().decode(
            Report.self, from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        XCTAssertEqual(report.matchingRAMFrames, 250)
        func has(_ frame: Int, _ pc: Int, _ address: Int, _ from: Int, _ to: Int) -> Bool {
            report.entityStateWrites.contains {
                $0.frame == frame && $0.instructionAddress == pc
                    && $0.address == address && $0.previous == from && $0.value == to
            }
        }
        XCTAssertTrue(has(184, 42346, 38804, 1, 0))
        XCTAssertTrue(has(184, 42506, 38808, 208, 0))
        XCTAssertTrue(has(184, 42509, 38809, 80, 0))
        XCTAssertTrue(has(184, 42519, 38804, 0, 13))
        XCTAssertTrue(has(220, 42346, 38804, 1, 0))
        XCTAssertTrue(has(220, 42466, 38808, 0, 176))
        XCTAssertTrue(has(220, 42487, 38809, 0, 80))
        XCTAssertTrue(has(224, 42346, 38804, 0, 255))
    }

    func testBoundedFirePathAcrossBothExpiries() throws {
        let world = try world()
        var enemy = try CapturedActiveEnemyState(
            kind: 108, timer: 9, room: RoomID(8, 9),
            position: GridPoint(92, 130),
            velocityX: -48, velocityY: 80
        )
        for _ in 0..<8 {
            try enemy.advanceOnSourceUpdate(world: world)
        }
        XCTAssertEqual(enemy.position, GridPoint(68, 135))
        XCTAssertEqual(enemy.kind, 108)
        XCTAssertEqual(enemy.timer, 1)

        try enemy.expireOnSourceUpdate(rngByte: 69, clockByte: 38)
        XCTAssertEqual(enemy.timer, 13)
        XCTAssertEqual(enemy.velocityX, 0)
        XCTAssertEqual(enemy.velocityY, 0)
        XCTAssertThrowsError(try enemy.advanceOnSourceUpdate(world: world))
        for _ in 0..<12 {
            try enemy.advanceCountdownOnSourceUpdate()
        }
        XCTAssertEqual(enemy.timer, 1)
        XCTAssertEqual(enemy.position, GridPoint(68, 135))

        try enemy.expireOnSourceUpdate(rngByte: 153, clockByte: 38)
        XCTAssertEqual(enemy.timer, 0)
        XCTAssertEqual(enemy.velocityX, -80)
        XCTAssertEqual(enemy.velocityY, 80)
        try enemy.advanceOnSourceUpdate(world: world, countdownOccurred: false)
        XCTAssertEqual(enemy.position, GridPoint(63, 135))
        XCTAssertEqual(enemy.kind, 109)
        try enemy.advanceCountdownOnSourceUpdate()
        XCTAssertEqual(enemy.timer, 255)
        try enemy.advanceOnSourceUpdate(world: world, countdownOccurred: false)
        XCTAssertEqual(enemy.position, GridPoint(58, 135))
        XCTAssertEqual(enemy.kind, 108)
        try enemy.advanceCountdownOnSourceUpdate()
        XCTAssertEqual(enemy.timer, 254)
        try enemy.advanceOnSourceUpdate(world: world, countdownOccurred: false)
        XCTAssertEqual(enemy.position, GridPoint(53, 135))
        XCTAssertEqual(enemy.kind, 109)
        XCTAssertThrowsError(try enemy.advanceCountdownOnSourceUpdate())
    }

    func testPrivateContinuousEnemyPathWhenProvided() throws {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["SABRE_PRIVATE_ENTITY_TRACE_DIR"],
              let worldPath = env["SABRE_PRIVATE_WORLD"] else {
            throw XCTSkip("Set the private world and 250-frame enemy traces")
        }
        struct Write: Decodable {
            let frame: Int
            let instructionAddress: Int
            let address: Int
            let previous: Int
            let value: Int
        }
        struct Report: Decodable {
            let matchingRAMFrames: Int
            let entityStateWrites: [Write]
        }
        let base = URL(fileURLWithPath: directory)
        let report = try JSONDecoder().decode(
            Report.self,
            from: Data(contentsOf: base.appendingPathComponent(
                "entity-writes-fire-before-contact-250.json"
            ))
        )
        let trace = try ReferenceEntityTrace.load(from: Data(contentsOf:
            base.appendingPathComponent("trace-fire-before-contact-250.json")
        ))
        let replay = try ReferenceReplay.load(from: Data(contentsOf:
            base.appendingPathComponent("replay-fire-before-contact-250.json")
        ))
        try trace.validate(replay: replay)
        XCTAssertEqual(report.matchingRAMFrames, 250)
        let world = try WorldReference.load(
            from: Data(contentsOf: URL(fileURLWithPath: worldPath))
        )
        var enemy = try CapturedActiveEnemyState(
            kind: 108, timer: 9, room: RoomID(8, 9),
            position: GridPoint(92, 130), velocityX: -48, velocityY: 80
        )
        var observedTimer = 9
        var observedVX = -48
        var observedVY = 80
        let writesByFrame = Dictionary(grouping: report.entityStateWrites, by: \.frame)
        for frame in 157...230 {
            for write in writesByFrame[frame] ?? [] {
                if write.address == 38804 && write.instructionAddress == 42346 {
                    XCTAssertEqual(Int(enemy.timer), write.previous, "frame \(frame)")
                    if write.previous == 1 {
                        let rng: UInt8 = frame == 184 ? 69 : 153
                        try enemy.expireOnSourceUpdate(rngByte: rng, clockByte: 38)
                    } else {
                        try enemy.advanceCountdownOnSourceUpdate()
                    }
                } else if write.address == 38802 && write.instructionAddress == 42388 {
                    do {
                        try enemy.advanceOnSourceUpdate(
                            world: world, countdownOccurred: false
                        )
                    } catch {
                        XCTFail("Enemy motion at frame \(frame): \(enemy), \(error)")
                        throw error
                    }
                }
                if write.address == 38804 { observedTimer = write.value }
                if write.address == 38808 {
                    observedVX = Int(Int8(bitPattern: UInt8(write.value)))
                }
                if write.address == 38809 {
                    observedVY = Int(Int8(bitPattern: UInt8(write.value)))
                }
            }
            let source = trace.trace[frame - 1].fullEmulatorEntity
            XCTAssertEqual(source.roomID, 152)
            XCTAssertEqual(Int(enemy.kind), source.kind, "frame \(frame)")
            XCTAssertEqual(enemy.position, GridPoint(source.x, source.y), "frame \(frame)")
            XCTAssertEqual(Int(enemy.timer), observedTimer, "frame \(frame)")
            XCTAssertEqual(enemy.velocityX, observedVX, "frame \(frame)")
            XCTAssertEqual(enemy.velocityY, observedVY, "frame \(frame)")
        }
    }

    func testPrivateEnemyDispatchCadenceWhenProvided() throws {
        guard let directory = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_ENEMY_DISPATCH_DIR"
        ] else { throw XCTSkip("Set the ignored RAM-checked enemy dispatch reports") }
        struct Dispatch: Decodable {
            let frame: Int
            let cycle: Int
            let kind: Int
            let timer: Int
            let rng: Int
            let refresh: Int
        }
        struct Report: Decodable {
            let snapshotSHA256: String
            let framesCompared: Int
            let matchingRAMFrames: Int
            let enemyDispatches: [Dispatch]
        }
        let base = URL(fileURLWithPath: directory)
        var fireFrames: [Int] = []
        for (scenario, count, expected) in [
            ("fire-before-contact", 190,
             [160, 163, 166, 170, 173, 176, 179, 182, 184, 187, 189]),
            ("no-fire-encounter", 190, [159, 162]),
            ("unrelated-a-control", 190, [159, 162, 165, 168]),
            ("fire-before-contact", 250,
             [160, 163, 166, 170, 173, 176, 179, 182, 184, 187, 189,
              191, 194, 196, 199, 202, 205, 208, 212, 215, 217, 220,
              224, 227, 234]),
        ] {
            let file = base.appendingPathComponent(
                "enemy-dispatch-verified-\(scenario)-\(count).json"
            )
            let report = try JSONDecoder().decode(
                Report.self, from: Data(contentsOf: file)
            )
            XCTAssertEqual(report.snapshotSHA256, WorldReference.supportedSnapshotSHA256)
            XCTAssertEqual(report.framesCompared, count)
            XCTAssertEqual(report.matchingRAMFrames, count)
            XCTAssertEqual(report.enemyDispatches.map(\.frame), expected)
            XCTAssertTrue(report.enemyDispatches.allSatisfy {
                (108...111).contains($0.kind)
                    && (0...255).contains($0.timer)
                    && (0...255).contains($0.rng)
                    && (0...255).contains($0.refresh)
            })
            XCTAssertTrue(zip(report.enemyDispatches, report.enemyDispatches.dropFirst())
                .allSatisfy { $0.0.cycle < $0.1.cycle })
            if scenario == "fire-before-contact" {
                if count == 190 {
                    fireFrames = report.enemyDispatches.map(\.frame)
                } else {
                    XCTAssertEqual(Array(report.enemyDispatches.prefix(11).map(\.frame)),
                                   fireFrames)
                    XCTAssertEqual(report.enemyDispatches.map(\.timer),
                                   [9, 8, 7, 6, 5, 4, 3, 2, 1, 13, 12, 11, 10,
                                    9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 255, 254])
                }
            }
        }
    }
}
