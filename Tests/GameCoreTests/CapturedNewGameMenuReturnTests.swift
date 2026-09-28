import Foundation
import XCTest
@testable import GameCore

final class CapturedNewGameMenuReturnTests: XCTestCase {
    func testPrivateSecondMenuRoutineSequenceWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_NEW_GAME_MENU_REPORT"
        ] else { throw XCTSkip("Set the ignored 1800-frame menu-routine report") }
        struct Routines: Decodable {
            let setupFrames: [Int]
            let returnFrames: [Int]
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
            let menuRoutineFrames: Routines
            let playerStateWrites: [Write]
        }
        let report = try JSONDecoder().decode(
            Report.self, from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        XCTAssertEqual(report.framesCompared, 1800)
        XCTAssertEqual(report.matchingRAMFrames, 1800)
        XCTAssertEqual(report.menuRoutineFrames.setupFrames, [366, 1596])
        XCTAssertEqual(report.menuRoutineFrames.returnFrames, [497, 1728])
        XCTAssertTrue(report.playerStateWrites.contains {
            $0.frame == 1499 && $0.address == 38589
                && $0.previous == 1 && $0.value == 0
        })
    }
}
