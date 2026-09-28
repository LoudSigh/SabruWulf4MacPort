import Foundation
import XCTest
@testable import GameCore

final class CapturedIntermediateInjuryTickTests: XCTestCase {
    func testStationaryIntermediateLives() throws {
        for life in [UInt8(3), 2] {
            XCTAssertEqual(try CapturedIntermediateInjuryTick.advance(
                kind: 64, timer: 32, lifeByte: life,
                room: RoomID(8, 10), x: 191, y: 112
            ), CapturedNewGameInjuryPhase(kind: 65, timer: 63))
        }
    }

    func testRejectsUnobservedIntermediateStates() {
        for (kind, timer, life, room, x) in [
            (UInt8(68), UInt8(32), UInt8(3), RoomID(8, 10), 191),
            (UInt8(64), UInt8(31), UInt8(3), RoomID(8, 10), 191),
            (UInt8(64), UInt8(32), UInt8(1), RoomID(8, 10), 191),
            (UInt8(64), UInt8(32), UInt8(3), RoomID(8, 9), 191),
            (UInt8(64), UInt8(32), UInt8(3), RoomID(8, 10), 190),
        ] {
            XCTAssertThrowsError(try CapturedIntermediateInjuryTick.advance(
                kind: kind, timer: timer, lifeByte: life,
                room: room, x: x, y: 112
            ))
        }
    }

    func testPrivateIntermediateTransitionsWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_NEW_GAME_INJURY_COUNTDOWN"
        ] else { throw XCTSkip("Set the ignored 1500-frame W/Q injury report") }
        struct Write: Decodable {
            let frame: Int
            let address: Int
            let previous: Int
            let value: Int
            let instructionAddress: Int
        }
        struct Report: Decodable {
            let matchingRAMFrames: Int
            let playerStateWrites: [Write]
        }
        let report = try JSONDecoder().decode(
            Report.self, from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        XCTAssertEqual(report.matchingRAMFrames, 1500)
        for (onset, exit, life) in [(1064, 1066, UInt8(3)), (1251, 1253, 2)] {
            let writes = report.playerStateWrites.filter { $0.frame == exit }
            let kind = try XCTUnwrap(writes.first {
                $0.address == 38658 && $0.instructionAddress == 43520
            })
            let timer = try XCTUnwrap(writes.first {
                $0.address == 38660 && $0.instructionAddress == 43523
            })
            XCTAssertFalse(report.playerStateWrites.contains {
                (onset...exit).contains($0.frame) && $0.address == 38661
            })
            let result = try CapturedIntermediateInjuryTick.advance(
                kind: UInt8(kind.previous), timer: UInt8(timer.previous),
                lifeByte: life, room: RoomID(8, 10), x: 191, y: 112
            )
            XCTAssertEqual(Int(result.kind), kind.value)
            XCTAssertEqual(Int(result.timer), timer.value)
        }
    }
}
