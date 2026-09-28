import Foundation
import XCTest
@testable import GameCore

final class CapturedNewGameInjuryTickTests: XCTestCase {
    func testBoundedFourLifeKnockback() throws {
        var x = 56
        var timer: UInt8 = 32
        for _ in 0..<28 {
            let next = try CapturedNewGameInjuryTick.advance(
                kind: 64, room: RoomID(8, 10),
                x: x, y: 112, timer: timer, lifeByte: 4, velocityX: 3
            )
            x = next.x
            timer = next.timer
        }
        XCTAssertEqual(x, 140)
        XCTAssertEqual(timer, 60)
        XCTAssertThrowsError(try CapturedNewGameInjuryTick.advance(
            kind: 64, room: RoomID(8, 10),
            x: x, y: 112, timer: timer, lifeByte: 4, velocityX: 3
        ))
    }

    func testRejectsUnmeasuredInjuryStates() throws {
        for (kind, room, x, timer, lives, velocity) in [
            (UInt8(65), RoomID(8, 10), 56, UInt8(32), UInt8(4), 3),
            (UInt8(64), RoomID(8, 9), 56, UInt8(32), UInt8(4), 3),
            (UInt8(64), RoomID(8, 10), 55, UInt8(32), UInt8(4), 3),
            (UInt8(64), RoomID(8, 10), 56, UInt8(31), UInt8(4), 3),
            (UInt8(64), RoomID(8, 10), 56, UInt8(32), UInt8(1), 3),
            (UInt8(64), RoomID(8, 10), 56, UInt8(32), UInt8(4), -3),
        ] {
            XCTAssertThrowsError(try CapturedNewGameInjuryTick.advance(
                kind: kind, room: room, x: x, y: 112,
                timer: timer, lifeByte: lives, velocityX: velocity
            ))
        }
    }

    func testPrivateKnockbackWritesWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_NEW_GAME_INJURY_WRITES"
        ] else { throw XCTSkip("Set ignored W/Q player-write report") }
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
        let report = try JSONDecoder().decode(
            Report.self, from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        XCTAssertEqual(report.matchingRAMFrames, 900)
        XCTAssertTrue(report.playerStateWrites.contains {
            $0.frame == 870 && $0.address == 38658
                && $0.previous == 19 && $0.value == 64
        })
        let xWrites = report.playerStateWrites.filter {
            (871...900).contains($0.frame)
                && $0.address == 38661 && $0.instructionAddress == 43500
        }
        let timerWrites = report.playerStateWrites.filter {
            (871...900).contains($0.frame)
                && $0.address == 38660 && $0.instructionAddress == 43509
        }
        XCTAssertEqual(xWrites.count, 28)
        XCTAssertEqual(timerWrites.count, 28)
        for (position, timer) in zip(xWrites, timerWrites) {
            XCTAssertLessThan(position.cycle, timer.cycle)
            let predicted = try CapturedNewGameInjuryTick.advance(
                kind: 64, room: RoomID(8, 10),
                x: position.previous, y: 112,
                timer: UInt8(timer.previous), lifeByte: 4, velocityX: 3
            )
            XCTAssertEqual(predicted.x, position.value)
            XCTAssertEqual(Int(predicted.timer), timer.value)
        }
    }
}
