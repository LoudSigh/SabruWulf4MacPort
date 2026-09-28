import Foundation
import XCTest
@testable import GameCore

final class CapturedRNGStepTests: XCTestCase {
    func testRefreshAndClockInputsWrapAtEightBits() {
        XCTAssertEqual(
            CapturedRNGStep.refresh(previous: 177, refreshOperand: 57, carry: true), 235
        )
        XCTAssertEqual(
            CapturedRNGStep.refresh(previous: 177, refreshOperand: 57, carry: false), 234
        )
        XCTAssertEqual(
            CapturedRNGStep.refresh(previous: 255, refreshOperand: 255, carry: true), 255
        )
        XCTAssertEqual(
            CapturedRNGStep.clock(previous: 255, counterLowByte: 2, clockByte: 5), 6
        )
        XCTAssertEqual(
            CapturedRNGStep.clock(previous: 255, counterLowByte: 3, clockByte: 5), 7
        )
        XCTAssertEqual(
            CapturedRNGStep.clock(previous: 0, counterLowByte: 0, clockByte: 0), 0
        )
    }

    func testPrivateSourceWritesWhenProvided() throws {
        guard let directory = ProcessInfo.processInfo.environment["SABRE_PRIVATE_ENTITY_TRACE_DIR"]
        else { throw XCTSkip("Set the ignored private RNG comparison directory") }
        struct Comparison: Decodable {
            let refreshCalls: Int
            let clockCalls: Int
            let matchingWrites: Int
        }
        struct Report: Decodable {
            let framesCompared: Int
            let matchingRAMFrames: Int
            let rngStepComparison: Comparison
        }
        for (scenario, frames, refresh, clock) in [
            ("fire-before-contact", 190, 1955, 74),
            ("no-fire-encounter", 190, 2000, 76),
            ("unrelated-a-control", 190, 1975, 75),
            ("fire-before-contact", 250, 2491, 94),
        ] {
            let file = URL(fileURLWithPath: directory)
                .appendingPathComponent("rng-step-\(scenario)-\(frames).json")
            let report = try JSONDecoder().decode(
                Report.self, from: Data(contentsOf: file)
            )
            XCTAssertEqual(report.framesCompared, frames)
            XCTAssertEqual(report.matchingRAMFrames, frames)
            XCTAssertEqual(report.rngStepComparison.refreshCalls, refresh)
            XCTAssertEqual(report.rngStepComparison.clockCalls, clock)
            XCTAssertEqual(report.rngStepComparison.matchingWrites, refresh + clock)
        }
    }
}
