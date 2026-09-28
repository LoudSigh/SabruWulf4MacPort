import CryptoKit
import Foundation
import XCTest
@testable import GameCore

final class CapturedEnemyDirectionTests: XCTestCase {
    func testAllEightChoicesUseSignedSixteenthPixelVelocities() throws {
        XCTAssertEqual(
            (0...7).map { CapturedEnemyDirection.velocity(index: UInt8($0)) },
            [-96, -80, -64, -48, 48, 64, 80, 96]
        )
        XCTAssertEqual(
            try CapturedEnemyDirection.choose(kind: 108, rngByte: 55, clockByte: 230),
            CapturedEnemyDirectionChoice(kind: 110, velocityX: 96, velocityY: 80)
        )
        XCTAssertEqual(
            try CapturedEnemyDirection.choose(kind: 108, rngByte: 28, clockByte: 230),
            CapturedEnemyDirectionChoice(kind: 110, velocityX: 48, velocityY: 80)
        )
        XCTAssertEqual(
            try CapturedEnemyDirection.choose(kind: 108, rngByte: 227, clockByte: 230),
            CapturedEnemyDirectionChoice(kind: 108, velocityX: -48, velocityY: 80)
        )
        XCTAssertEqual(
            try CapturedEnemyDirection.choose(kind: 109, rngByte: 227, clockByte: 230).kind,
            109
        )
        XCTAssertThrowsError(try CapturedEnemyDirection.choose(
            kind: 6, rngByte: 55, clockByte: 230
        ))
    }

    func testPrivateDirectionDataIdenticalInBothCapturesWhenProvided() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let menu = environment["SABRE_PRIVATE_MENU_RAM"],
              let game = environment["SABRE_PRIVATE_GAME_RAM"] else {
            throw XCTSkip("Set both private 48K RAM paths for bounded direction data check")
        }
        for (path, expectedHash) in [
            (menu, "05277ed154c9ae7e33fae10dfeb7524a65cedcb212869a9ebc536d1d0d172e1b"),
            (game, "6de170c1b2518c82c5bfefc0f7dbfc8b8766097e020950d51b01baf045064864"),
        ] {
            let ram = try Data(contentsOf: URL(fileURLWithPath: path))
            let hash = SHA256.hash(data: ram).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(ram.count, 49_152)
            XCTAssertEqual(hash, expectedHash)
            for index in 0..<8 {
                XCTAssertEqual(
                    ram[0xA601 - 0x4000 + index],
                    UInt8(truncatingIfNeeded:
                        CapturedEnemyDirection.velocity(index: UInt8(index)))
                )
            }
        }
    }
}
