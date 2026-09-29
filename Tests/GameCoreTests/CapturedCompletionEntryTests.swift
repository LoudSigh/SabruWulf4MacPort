import Foundation
import XCTest
@testable import GameCore

final class CapturedCompletionEntryTests: XCTestCase {
    func testSpatialThresholdDoesNotInferFourPieces() throws {
        XCTAssertFalse(try CapturedCompletionEntry.enters(
            playerKind: 21, playerRoom: 168, playerY: 112
        ))
        XCTAssertTrue(try CapturedCompletionEntry.enters(
            playerKind: 21, playerRoom: 136, playerY: 112
        ))
        XCTAssertTrue(try CapturedCompletionEntry.enters(
            playerKind: 21, playerRoom: 136, playerY: 127
        ))
        XCTAssertFalse(try CapturedCompletionEntry.enters(
            playerKind: 21, playerRoom: 136, playerY: 128
        ))
        XCTAssertThrowsError(try CapturedCompletionEntry.enters(
            playerKind: 65, playerRoom: 136, playerY: 112
        ))
    }

    func testPrivateFiveCompletionRegionBranchesWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_COMPLETION_REGION"
        ] else { throw XCTSkip("Set the ignored edited-room completion report") }
        struct Branch: Decodable {
            let roomAtFork: UInt8
            let yAtFork: UInt8
            let progressAtFork: Int
            let manualFullRAMFrames: Int
            let manualFullCPUFrames: Int
            let completionPCVisits: Int
            let firstCompletionFrame: Int?
            let matchingCapturedMenuCenterPixels: Int
            let fullScreenRGBAHash: String
        }
        let branches = try JSONDecoder().decode(
            [Branch].self, from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        XCTAssertEqual(branches.count, 5)
        XCTAssertEqual(branches.map(\.progressAtFork), [15, 0, 15, 0, 15])
        XCTAssertEqual(branches.map(\.roomAtFork), [168, 136, 136, 136, 136])
        XCTAssertEqual(branches.map(\.yAtFork), [112, 112, 112, 127, 128])
        var successfulScreenHashes: [String] = []
        for branch in branches {
            XCTAssertEqual(branch.manualFullRAMFrames, 100)
            XCTAssertEqual(branch.manualFullCPUFrames, 100)
            let predicted = try CapturedCompletionEntry.enters(
                playerKind: 21, playerRoom: branch.roomAtFork,
                playerY: branch.yAtFork
            )
            XCTAssertEqual(branch.completionPCVisits, predicted ? 1 : 0)
            XCTAssertEqual(branch.firstCompletionFrame, predicted ? 1 : nil)
            if predicted {
                XCTAssertEqual(branch.matchingCapturedMenuCenterPixels, 2414)
                successfulScreenHashes.append(branch.fullScreenRGBAHash)
            }
        }
        XCTAssertEqual(Set(successfulScreenHashes).count, 1)
        XCTAssertNotEqual(branches[0].fullScreenRGBAHash, successfulScreenHashes[0])
        XCTAssertNotEqual(branches[4].fullScreenRGBAHash, successfulScreenHashes[0])
    }
}
