import Foundation
import XCTest
@testable import GameCore

final class CapturedEnemyExpiryTests: XCTestCase {
    func testMovingEnemyStopsAndReseedsFromSuppliedRNG() throws {
        let state = try CapturedEnemyExpiry.resolve(
            kind: 108, timer: 1, room: RoomID(8, 9),
            velocityX: -48, velocityY: 80,
            rngByte: 69, clockByte: 38
        )
        XCTAssertEqual(
            state, CapturedEnemyExpiryState(
                kind: 108, timer: 13, velocityX: 0, velocityY: 0
            )
        )
        for rng in UInt8.min...UInt8.max {
            let next = try CapturedEnemyExpiry.resolve(
                kind: 111, timer: 1, room: RoomID(8, 9),
                velocityX: 96, velocityY: 80,
                rngByte: rng, clockByte: 0
            )
            XCTAssertEqual(next.timer, (rng & 7) | 8)
            XCTAssertEqual(next.kind, 111)
            XCTAssertEqual(next.velocityX, 0)
            XCTAssertEqual(next.velocityY, 0)
        }
    }

    func testStoppedEnemyChoosesSuppliedDirectionWithoutResettingTimer() throws {
        let state = try CapturedEnemyExpiry.resolve(
            kind: 108, timer: 1, room: RoomID(8, 9),
            velocityX: 0, velocityY: 0,
            rngByte: 153, clockByte: 38
        )
        XCTAssertEqual(
            state, CapturedEnemyExpiryState(
                kind: 108, timer: 0, velocityX: -80, velocityY: 80
            )
        )
    }

    func testRejectsUnobservedExpiryState() throws {
        for (kind, timer, room, x, y) in [
            (UInt8(8), UInt8(1), RoomID(8, 9), 0, 0),
            (UInt8(108), UInt8(2), RoomID(8, 9), 0, 0),
            (UInt8(108), UInt8(1), RoomID(8, 10), 0, 0),
            (UInt8(108), UInt8(1), RoomID(8, 9), 32, 80),
            (UInt8(108), UInt8(1), RoomID(8, 9), -48, 0),
        ] {
            XCTAssertThrowsError(try CapturedEnemyExpiry.resolve(
                kind: kind, timer: timer, room: room,
                velocityX: x, velocityY: y,
                rngByte: 69, clockByte: 38
            ))
        }
    }

    func testPrivateTimerExpiryParityWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["SABRE_PRIVATE_ENEMY_EXPIRY_REPORT"]
        else { throw XCTSkip("Set the ignored 250-frame expiry report path") }
        struct Comparison: Decodable {
            let calls: Int
            let matchingCalls: Int
            let stoppedFrames: [Int]
            let resumedFrames: [Int]
        }
        struct Report: Decodable {
            let framesCompared: Int
            let matchingRAMFrames: Int
            let enemyExpiryComparison: Comparison
        }
        let report = try JSONDecoder().decode(
            Report.self, from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        XCTAssertEqual(report.framesCompared, 250)
        XCTAssertEqual(report.matchingRAMFrames, 250)
        XCTAssertEqual(report.enemyExpiryComparison.calls, 2)
        XCTAssertEqual(report.enemyExpiryComparison.matchingCalls, 2)
        XCTAssertEqual(report.enemyExpiryComparison.stoppedFrames, [184])
        XCTAssertEqual(report.enemyExpiryComparison.resumedFrames, [220])
    }
}
