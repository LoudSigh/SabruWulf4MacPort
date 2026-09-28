import Foundation
import XCTest
@testable import GameCore

final class CapturedFirstInjuryTickTests: XCTestCase {
    func testCountsDownOnlyOnSourceActorUpdates() throws {
        for life in UInt8(1)...UInt8(4) {
            var timer: UInt8 = 63
            for _ in 0..<62 {
                let next = try CapturedFirstInjuryTick.advance(
                    kind: 65, timer: timer, lifeByte: life
                )
                XCTAssertEqual(next.kind, 65)
                XCTAssertEqual(next.lifeByte, life)
                timer = next.timer
            }
            XCTAssertEqual(timer, 1)
            let final = try CapturedFirstInjuryTick.advance(
                kind: 65, timer: timer, lifeByte: life
            )
            XCTAssertEqual(
                final, CapturedInjuryStep(kind: 17, timer: 0, lifeByte: life - 1)
            )
        }
    }

    func testRejectsUnverifiedInjuryStates() {
        for (kind, timer, lives): (UInt8, UInt8, UInt8) in [
            (64, 32, 1), (65, 0, 1), (65, 64, 1),
            (65, 12, 0), (65, 12, 5), (69, 12, 1),
        ] {
            XCTAssertThrowsError(
                try CapturedFirstInjuryTick.advance(
                    kind: kind, timer: timer, lifeByte: lives
                )
            ) { error in
                guard case CapturedInjuryError.unsupportedState = error else {
                    return XCTFail("Unexpected injury-state error: \(error)")
                }
            }
        }
    }

    func testPrivateFourToOneCountdownWhenProvided() throws {
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
            let address: Int
            let previous: Int
            let value: Int
        }
        struct Report: Decodable {
            let framesCompared: Int
            let matchingRAMFrames: Int
            let injuryComparison: Comparison
            let playerStateWrites: [Write]
        }
        let report = try JSONDecoder().decode(
            Report.self, from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        XCTAssertEqual(report.framesCompared, 1500)
        XCTAssertEqual(report.matchingRAMFrames, 1500)
        XCTAssertEqual(report.injuryComparison.sourceUpdates, 315)
        XCTAssertEqual(report.injuryComparison.matchingUpdates, 315)
        XCTAssertEqual(
            report.injuryComparison.lifeDecrementFrames,
            [231, 983, 1131, 1317, 1499]
        )
        let laterLives = report.playerStateWrites.filter {
            $0.address == 38589 && $0.frame > 900
        }
        XCTAssertEqual(
            laterLives.map { [$0.frame, $0.previous, $0.value] },
            [[983, 4, 3], [1131, 3, 2], [1317, 2, 1], [1499, 1, 0]]
        )
    }
}
