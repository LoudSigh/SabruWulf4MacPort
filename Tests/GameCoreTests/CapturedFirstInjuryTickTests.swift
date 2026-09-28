import XCTest
@testable import GameCore

final class CapturedFirstInjuryTickTests: XCTestCase {
    func testCountsDownOnlyOnSourceActorUpdates() throws {
        var timer: UInt8 = 63
        for _ in 0..<62 {
            let next = try CapturedFirstInjuryTick.advance(
                kind: 65, timer: timer, lifeByte: 1
            )
            XCTAssertEqual(next.kind, 65)
            XCTAssertEqual(next.lifeByte, 1)
            timer = next.timer
        }
        XCTAssertEqual(timer, 1)
        let final = try CapturedFirstInjuryTick.advance(
            kind: 65, timer: timer, lifeByte: 1
        )
        XCTAssertEqual(final, CapturedInjuryStep(kind: 17, timer: 0, lifeByte: 0))
    }

    func testRejectsUnverifiedInjuryStates() {
        for (kind, timer, lives): (UInt8, UInt8, UInt8) in [
            (64, 32, 1), (65, 0, 1), (65, 64, 1),
            (65, 12, 0), (65, 12, 2), (69, 12, 1),
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
}
