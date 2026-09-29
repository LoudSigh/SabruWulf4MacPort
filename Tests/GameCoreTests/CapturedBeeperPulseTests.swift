import Foundation
import XCTest
@testable import GameCore

final class CapturedBeeperPulseTests: XCTestCase {
    func testMeasuredCounterAndInterruptBounds() throws {
        XCTAssertEqual(try CapturedBeeperPulse.highDurationTStates(
            delayCounter: 1, interruptionTStates: 0
        ), 31)
        XCTAssertEqual(try CapturedBeeperPulse.highDurationTStates(
            delayCounter: 0, interruptionTStates: 0
        ), 3346)
        XCTAssertEqual(try CapturedBeeperPulse.highDurationTStates(
            delayCounter: 255, interruptionTStates: 895
        ), 4228)
        XCTAssertEqual(try CapturedBeeperPulse.highDurationTStates(
            delayCounter: 1, interruptionTStates: 1124
        ), 1155)
        XCTAssertThrowsError(try CapturedBeeperPulse.highDurationTStates(
            delayCounter: 1, interruptionTStates: 1
        ))
    }

    func testPrivateFiveHundredSourcePulseDurationsWhenProvided() throws {
        guard let directory = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_BEEPER_COUNTER_DIR"
        ] else { throw XCTSkip("Set ignored source beeper-counter reports") }
        struct Write: Decodable {
            let cycle: Int
            let speakerHigh: Bool
            let delayCounter: UInt8
        }
        struct Report: Decodable {
            let framesCompared: Int
            let matchingRAMFrames: Int
            let beeperWrites: [Write]
        }
        let base = URL(fileURLWithPath: directory)
        var matched = 0
        var uninterrupted = 0
        var delayed895 = 0
        var delayed1124 = 0
        for (name, pairs) in [
            ("fire190", 92), ("no-fire190", 204), ("unrelated190", 204),
        ] {
            let report = try JSONDecoder().decode(Report.self, from: Data(
                contentsOf: base.appendingPathComponent(
                    "beeper-counter-\(name).json"
                )
            ))
            XCTAssertEqual(report.framesCompared, 190)
            XCTAssertEqual(report.matchingRAMFrames, 190)
            XCTAssertEqual(report.beeperWrites.count, pairs * 2)
            for index in 0..<pairs {
                let high = report.beeperWrites[index * 2]
                let low = report.beeperWrites[index * 2 + 1]
                XCTAssertTrue(high.speakerHigh)
                XCTAssertFalse(low.speakerHigh)
                let baseDuration = try CapturedBeeperPulse.highDurationTStates(
                    delayCounter: high.delayCounter, interruptionTStates: 0
                )
                let extra = low.cycle - high.cycle - baseDuration
                switch extra {
                case 0: uninterrupted += 1
                case 895: delayed895 += 1
                case 1124: delayed1124 += 1
                default: return XCTFail("Unclassified source pulse delay")
                }
                XCTAssertEqual(
                    try CapturedBeeperPulse.highDurationTStates(
                        delayCounter: high.delayCounter,
                        interruptionTStates: extra
                    ), low.cycle - high.cycle
                )
                matched += 1
            }
        }
        XCTAssertEqual(matched, 500)
        XCTAssertEqual(uninterrupted, 494)
        XCTAssertEqual(delayed895, 5)
        XCTAssertEqual(delayed1124, 1)
    }
}
