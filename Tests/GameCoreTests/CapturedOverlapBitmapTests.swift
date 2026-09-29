import Foundation
import XCTest
@testable import GameCore

final class CapturedOverlapBitmapTests: XCTestCase {
    func testXorProjectsOnlyOverlappingMaskPixels() throws {
        let player = CapturedActorSprite(
            mask: try SpriteMask(record: Data([1, 2, 0x80, 0x40])),
            actorAt: GridPoint(4, 10)
        )
        let other = CapturedActorSprite(
            mask: try SpriteMask(record: Data([1, 2, 0xC0, 0xC0])),
            actorAt: GridPoint(5, 10)
        )
        let pixels = CapturedOverlapBitmap.xorPlayerRectangle(
            player: player, overlapping: other
        )
        XCTAssertEqual(pixels.count, 16)
        XCTAssertEqual(Array(pixels[0..<4]), [false, false, true, false])
        XCTAssertEqual(Array(pixels[8..<12]), [true, true, true, false])
    }

    func testNonoverlappingActorLeavesPlayerMaskUntouched() throws {
        let player = CapturedActorSprite(
            mask: try SpriteMask(record: Data([1, 1, 0xAA])),
            actorAt: GridPoint(20, 20)
        )
        let other = CapturedActorSprite(
            mask: try SpriteMask(record: Data([1, 1, 0xFF])),
            actorAt: GridPoint(30, 20)
        )
        XCTAssertEqual(
            CapturedOverlapBitmap.xorPlayerRectangle(
                player: player, overlapping: other
            ), player.screenPixels()
        )
    }
}
