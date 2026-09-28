import Foundation
import XCTest
@testable import GameCore

final class CapturedInjuryStartTests: XCTestCase {
    func testFourObservedInjuryEntries() throws {
        for (kind, life, room, vx) in [
            (UInt8(27), UInt8(1), RoomID(8, 9), 0),
            (UInt8(27), UInt8(1), RoomID(8, 9), 0),
            (UInt8(16), UInt8(1), RoomID(8, 9), 0),
            (UInt8(19), UInt8(4), RoomID(8, 10), -29),
        ] {
            XCTAssertEqual(
                try CapturedInjuryStart.advance(
                    kind: kind, timer: 1, lifeByte: life,
                    room: room, velocityX: vx
                ),
                CapturedInjuryStartStep(kind: 64, timer: 32, velocityX: 3)
            )
        }
    }

    func testRejectsUnobservedPlayerStates() throws {
        for (kind, timer, life, room, vx) in [
            (UInt8(27), UInt8(0), UInt8(1), RoomID(8, 9), 0),
            (UInt8(27), UInt8(1), UInt8(4), RoomID(8, 9), 0),
            (UInt8(16), UInt8(1), UInt8(1), RoomID(8, 10), 0),
            (UInt8(19), UInt8(1), UInt8(4), RoomID(8, 10), 0),
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
            let playerStateWrites: [Write]
        }
        for (name, frames, onset, kind, life, room, oldVX) in [
            ("player-onset-no-fire-encounter-190.json", 190, 164, 27, 1, 152, 0),
            ("player-onset-unrelated-a-control-190.json", 190, 170, 27, 1, 152, 0),
            ("player-onset-fire-before-contact-250.json", 250, 229, 16, 1, 152, 0),
            ("restart-ready-w-q-player-writes-v2-900.json", 900, 870, 19, 4, 168, -29),
        ] {
            let report = try JSONDecoder().decode(
                Report.self,
                from: Data(contentsOf: URL(fileURLWithPath: directory)
                    .appendingPathComponent(name))
            )
            XCTAssertEqual(report.matchingRAMFrames, frames)
            let updates = report.playerStateWrites.filter { $0.frame == onset }
            let timer = try XCTUnwrap(updates.first {
                $0.address == 38660 && $0.instructionAddress == 43397
            })
            let actor = try XCTUnwrap(updates.first {
                $0.address == 38658 && $0.instructionAddress == 43413
            })
            let velocity = try XCTUnwrap(updates.first {
                $0.address == 38664 && $0.instructionAddress == 43417
            })
            XCTAssertTrue(timer.cycle < actor.cycle && actor.cycle < velocity.cycle)
            XCTAssertEqual(timer.previous, 1)
            XCTAssertEqual(actor.previous, kind)
            XCTAssertEqual(Int(Int8(bitPattern: UInt8(velocity.previous))), oldVX)
            let predicted = try CapturedInjuryStart.advance(
                kind: UInt8(actor.previous), timer: UInt8(timer.previous),
                lifeByte: UInt8(life), room: RoomID(room % 16, room / 16),
                velocityX: oldVX
            )
            XCTAssertEqual(Int(predicted.kind), actor.value)
            XCTAssertEqual(Int(predicted.timer), timer.value)
            XCTAssertEqual(predicted.velocityX, velocity.value)
        }
    }
}
