import Foundation
import XCTest
@testable import GameCore

private struct InjuryEntryWrite: Decodable {
    let frame: Int
    let instructionAddress: Int
    let cycle: Int
    let address: Int
    let previous: Int
    let value: Int
}

private struct InjuryEntryReport: Decodable {
    let matchingRAMFrames: Int
    let playerStateWrites: [InjuryEntryWrite]
}

final class CapturedInjuryStartTests: XCTestCase {
    func testSevenObservedInjuryEntries() throws {
        for (kind, timer, life, room, vx, expectedKind, expectedVX) in [
            (UInt8(27), UInt8(1), UInt8(1), RoomID(8, 9), 0, UInt8(64), 3),
            (UInt8(27), UInt8(1), UInt8(1), RoomID(8, 9), 0, UInt8(64), 3),
            (UInt8(16), UInt8(1), UInt8(1), RoomID(8, 9), 0, UInt8(64), 3),
            (UInt8(19), UInt8(1), UInt8(4), RoomID(8, 10), -29, UInt8(64), 3),
            (UInt8(17), UInt8(1), UInt8(3), RoomID(8, 10), 0, UInt8(64), 3),
            (UInt8(17), UInt8(1), UInt8(2), RoomID(8, 10), 0, UInt8(64), 3),
            (UInt8(17), UInt8(2), UInt8(1), RoomID(8, 10), 0, UInt8(68), -3),
        ] {
            XCTAssertEqual(
                try CapturedInjuryStart.advance(
                    kind: kind, timer: timer, lifeByte: life,
                    room: room, velocityX: vx
                ),
                CapturedInjuryStartStep(
                    kind: expectedKind, timer: 32, velocityX: expectedVX
                )
            )
        }
    }

    func testRejectsUnobservedPlayerStates() throws {
        for (kind, timer, life, room, vx) in [
            (UInt8(27), UInt8(0), UInt8(1), RoomID(8, 9), 0),
            (UInt8(27), UInt8(1), UInt8(4), RoomID(8, 9), 0),
            (UInt8(16), UInt8(1), UInt8(1), RoomID(8, 10), 0),
            (UInt8(19), UInt8(1), UInt8(4), RoomID(8, 10), 0),
            (UInt8(17), UInt8(1), UInt8(1), RoomID(8, 10), 0),
            (UInt8(17), UInt8(2), UInt8(3), RoomID(8, 10), 0),
            (UInt8(65), UInt8(1), UInt8(1), RoomID(8, 9), 0),
        ] {
            XCTAssertThrowsError(try CapturedInjuryStart.advance(
                kind: kind, timer: timer, lifeByte: life,
                room: room, velocityX: vx
            ))
        }
    }

    func testPrivateFirstInjuryOnsetsWhenProvided() throws {
        guard let directory = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_INJURY_START_DIR"
        ] else { throw XCTSkip("Set the ignored player-write report directory") }
        for (name, frames, onset, kind, life, room, oldVX) in [
            ("player-onset-no-fire-encounter-190.json", 190, 164, 27, 1, 152, 0),
            ("player-onset-unrelated-a-control-190.json", 190, 170, 27, 1, 152, 0),
            ("player-onset-fire-before-contact-250.json", 250, 229, 16, 1, 152, 0),
            ("restart-ready-w-q-player-writes-v2-900.json", 900, 870, 19, 4, 168, -29),
        ] {
            let report = try JSONDecoder().decode(
                InjuryEntryReport.self,
                from: Data(contentsOf: URL(fileURLWithPath: directory)
                    .appendingPathComponent(name))
            )
            XCTAssertEqual(report.matchingRAMFrames, frames)
            try checkOnset(
                report.playerStateWrites, frame: onset, kind: kind,
                timer: 1, life: life, room: room, velocityX: oldVX,
                kindWriter: 43413, velocityWriter: 43417
            )
        }
    }

    func testPrivateLaterInjuryEntriesWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_LONG_WQ_CONTACT"
        ] else { throw XCTSkip("Set the ignored 1800-frame W/Q contact report") }
        let report = try JSONDecoder().decode(
            InjuryEntryReport.self, from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        XCTAssertEqual(report.matchingRAMFrames, 1800)
        for (frame, timer, life, kindWriter, velocityWriter) in [
            (1064, 1, 3, 43413, 43417),
            (1251, 1, 2, 43413, 43417),
            (1386, 2, 1, 43424, 43428),
        ] {
            try checkOnset(
                report.playerStateWrites, frame: frame, kind: 17,
                timer: timer, life: life, room: 168, velocityX: 0,
                kindWriter: kindWriter, velocityWriter: velocityWriter
            )
        }
    }

    private func checkOnset(
        _ writes: [InjuryEntryWrite], frame: Int, kind: Int,
        timer previousTimer: Int, life: Int, room: Int, velocityX: Int,
        kindWriter: Int, velocityWriter: Int
    ) throws {
        let updates = writes.filter { $0.frame == frame }
        let timer = try XCTUnwrap(updates.first {
            $0.address == 38660 && $0.instructionAddress == 43397
        })
        let actor = try XCTUnwrap(updates.first {
            $0.address == 38658 && $0.instructionAddress == kindWriter
        })
        let velocity = try XCTUnwrap(updates.first {
            $0.address == 38664 && $0.instructionAddress == velocityWriter
        })
        XCTAssertTrue(timer.cycle < actor.cycle && actor.cycle < velocity.cycle)
        XCTAssertEqual(timer.previous, previousTimer)
        XCTAssertEqual(actor.previous, kind)
        XCTAssertEqual(Int(Int8(bitPattern: UInt8(velocity.previous))), velocityX)
        let predicted = try CapturedInjuryStart.advance(
            kind: UInt8(actor.previous), timer: UInt8(timer.previous),
            lifeByte: UInt8(life), room: RoomID(room % 16, room / 16),
            velocityX: velocityX
        )
        XCTAssertEqual(Int(predicted.kind), actor.value)
        XCTAssertEqual(Int(predicted.timer), timer.value)
        XCTAssertEqual(
            predicted.velocityX, Int(Int8(bitPattern: UInt8(velocity.value)))
        )
    }
}
