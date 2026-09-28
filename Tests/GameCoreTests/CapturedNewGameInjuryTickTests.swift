import Foundation
import XCTest
@testable import GameCore

private struct PlayerWrite: Decodable {
    let frame: Int
    let instructionAddress: Int
    let cycle: Int
    let address: Int
    let previous: Int
    let value: Int
}

private struct PlayerWriteReport: Decodable {
    let matchingRAMFrames: Int
    let playerStateWrites: [PlayerWrite]
}

final class CapturedNewGameInjuryTickTests: XCTestCase {
    func testBoundedFourLifeKnockback() throws {
        var x = 56
        var timer: UInt8 = 32
        for _ in 0..<45 {
            let next = try CapturedNewGameInjuryTick.advance(
                kind: 64, room: RoomID(8, 10),
                x: x, y: 112, timer: timer, lifeByte: 4, velocityX: 3
            )
            x = next.x
            timer = next.timer
        }
        XCTAssertEqual(x, 191)
        XCTAssertEqual(timer, 77)
        XCTAssertThrowsError(try CapturedNewGameInjuryTick.advance(
            kind: 64, room: RoomID(8, 10),
            x: x, y: 112, timer: timer, lifeByte: 4, velocityX: 3
        ))
        XCTAssertEqual(try CapturedNewGameInjuryTick.finishKnockback(
            kind: 64, room: RoomID(8, 10),
            x: x, y: 112, timer: timer, lifeByte: 4
        ), CapturedNewGameInjuryPhase(kind: 65, timer: 63))
    }

    func testBoundedFinalLifeKnockback() throws {
        var x = 191
        var timer: UInt8 = 32
        for _ in 0..<45 {
            let next = try CapturedNewGameInjuryTick.advance(
                kind: 68, room: RoomID(8, 10),
                x: x, y: 112, timer: timer, lifeByte: 1, velocityX: -3
            )
            x = next.x
            timer = next.timer
        }
        XCTAssertEqual(x, 56)
        XCTAssertEqual(timer, 77)
        XCTAssertEqual(try CapturedNewGameInjuryTick.finishKnockback(
            kind: 68, room: RoomID(8, 10),
            x: x, y: 112, timer: timer, lifeByte: 1
        ), CapturedNewGameInjuryPhase(kind: 69, timer: 63))
        XCTAssertThrowsError(try CapturedNewGameInjuryTick.advance(
            kind: 68, room: RoomID(8, 10),
            x: x, y: 112, timer: timer, lifeByte: 1, velocityX: -3
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
        let report = try JSONDecoder().decode(
            PlayerWriteReport.self, from: Data(contentsOf: URL(fileURLWithPath: path))
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

    func testPrivateFullFourLifeKnockbackWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_NEW_GAME_INJURY_COUNTDOWN"
        ] else { throw XCTSkip("Set ignored 1500-frame W/Q player-write report") }
        let report = try JSONDecoder().decode(
            PlayerWriteReport.self, from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        XCTAssertEqual(report.matchingRAMFrames, 1500)
        let xWrites = report.playerStateWrites.filter {
            (871...917).contains($0.frame)
                && $0.address == 38661 && $0.instructionAddress == 43500
        }
        let timerWrites = report.playerStateWrites.filter {
            (871...917).contains($0.frame)
                && $0.address == 38660 && $0.instructionAddress == 43509
        }
        XCTAssertEqual(xWrites.count, 45)
        XCTAssertEqual(timerWrites.count, 45)
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
        let transition = report.playerStateWrites.filter { $0.frame == 918 }
        let kind = try XCTUnwrap(transition.first {
            $0.address == 38658 && $0.instructionAddress == 43520
        })
        let timer = try XCTUnwrap(transition.first {
            $0.address == 38660 && $0.instructionAddress == 43523
        })
        let phase = try CapturedNewGameInjuryTick.finishKnockback(
            kind: UInt8(kind.previous), room: RoomID(8, 10),
            x: 191, y: 112, timer: UInt8(timer.previous), lifeByte: 4
        )
        XCTAssertEqual(Int(phase.kind), kind.value)
        XCTAssertEqual(Int(phase.timer), timer.value)
    }

    func testPrivateFinalLifeKnockbackWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_NEW_GAME_INJURY_COUNTDOWN"
        ] else { throw XCTSkip("Set ignored 1500-frame W/Q player-write report") }
        let report = try JSONDecoder().decode(
            PlayerWriteReport.self, from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        XCTAssertEqual(report.matchingRAMFrames, 1500)
        let xWrites = report.playerStateWrites.filter {
            (1387...1433).contains($0.frame)
                && $0.address == 38661 && $0.instructionAddress == 43500
        }
        let timerWrites = report.playerStateWrites.filter {
            (1387...1433).contains($0.frame)
                && $0.address == 38660 && $0.instructionAddress == 43509
        }
        XCTAssertEqual(xWrites.count, 45)
        XCTAssertEqual(timerWrites.count, 45)
        for (position, timer) in zip(xWrites, timerWrites) {
            XCTAssertLessThan(position.cycle, timer.cycle)
            let predicted = try CapturedNewGameInjuryTick.advance(
                kind: 68, room: RoomID(8, 10),
                x: position.previous, y: 112,
                timer: UInt8(timer.previous), lifeByte: 1, velocityX: -3
            )
            XCTAssertEqual(predicted.x, position.value)
            XCTAssertEqual(Int(predicted.timer), timer.value)
        }
        let transition = report.playerStateWrites.filter { $0.frame == 1434 }
        let kind = try XCTUnwrap(transition.first {
            $0.address == 38658 && $0.instructionAddress == 43520
        })
        let timer = try XCTUnwrap(transition.first {
            $0.address == 38660 && $0.instructionAddress == 43523
        })
        let phase = try CapturedNewGameInjuryTick.finishKnockback(
            kind: UInt8(kind.previous), room: RoomID(8, 10),
            x: 56, y: 112, timer: UInt8(timer.previous), lifeByte: 1
        )
        XCTAssertEqual(Int(phase.kind), kind.value)
        XCTAssertEqual(Int(phase.timer), timer.value)
    }
}
