import Foundation
import XCTest
@testable import GameCore

final class CapturedFinalInjuryTickTests: XCTestCase {
    func testFinalKind69Countdown() throws {
        var timer: UInt8 = 63
        for _ in 0..<62 {
            let step = try CapturedFinalInjuryTick.advance(
                kind: 69, timer: timer, lifeByte: 1,
                room: RoomID(8, 10), x: 56, y: 112
            )
            XCTAssertEqual(step.kind, 69)
            XCTAssertEqual(step.lifeByte, 1)
            timer = step.timer
        }
        XCTAssertEqual(timer, 1)
        XCTAssertEqual(try CapturedFinalInjuryTick.advance(
            kind: 69, timer: timer, lifeByte: 1,
            room: RoomID(8, 10), x: 56, y: 112
        ), CapturedInjuryStep(kind: 21, timer: 0, lifeByte: 0))
    }

    func testRejectsOtherFinalStates() {
        for (kind, timer, life, room, x) in [
            (UInt8(65), UInt8(63), UInt8(1), RoomID(8, 10), 56),
            (UInt8(69), UInt8(0), UInt8(1), RoomID(8, 10), 56),
            (UInt8(69), UInt8(64), UInt8(1), RoomID(8, 10), 56),
            (UInt8(69), UInt8(63), UInt8(2), RoomID(8, 10), 56),
            (UInt8(69), UInt8(63), UInt8(1), RoomID(8, 9), 56),
            (UInt8(69), UInt8(63), UInt8(1), RoomID(8, 10), 57),
        ] {
            XCTAssertThrowsError(try CapturedFinalInjuryTick.advance(
                kind: kind, timer: timer, lifeByte: life,
                room: room, x: x, y: 112
            ))
        }
    }

    func testPrivateFinalLifeCountdownWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_NEW_GAME_INJURY_COUNTDOWN"
        ] else { throw XCTSkip("Set the ignored 1500-frame injury report") }
        struct Comparison: Decodable {
            let sourceUpdates: Int
            let matchingUpdates: Int
            let lifeDecrementFrames: [Int]
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
            let injuryComparison: Comparison
            let playerStateWrites: [Write]
        }
        let report = try JSONDecoder().decode(
            Report.self, from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        XCTAssertEqual(report.matchingRAMFrames, 1500)
        XCTAssertEqual(report.injuryComparison.sourceUpdates, 315)
        XCTAssertEqual(report.injuryComparison.matchingUpdates, 315)
        XCTAssertEqual(report.injuryComparison.lifeDecrementFrames.last, 1499)
        let ticks = report.playerStateWrites.filter {
            (1435...1499).contains($0.frame)
                && $0.address == 38660 && $0.instructionAddress == 43536
        }
        XCTAssertEqual(ticks.count, 63)
        for tick in ticks {
            let predicted = try CapturedFinalInjuryTick.advance(
                kind: 69, timer: UInt8(tick.previous),
                lifeByte: 1, room: RoomID(8, 10), x: 56, y: 112
            )
            XCTAssertEqual(Int(predicted.timer), tick.value)
        }
        XCTAssertTrue(report.playerStateWrites.contains {
            $0.frame == 1499 && $0.address == 38658
                && $0.previous == 69 && $0.value == 21
        })
        XCTAssertTrue(report.playerStateWrites.contains {
            $0.frame == 1499 && $0.address == 38589
                && $0.previous == 1 && $0.value == 0
        })
    }
}
