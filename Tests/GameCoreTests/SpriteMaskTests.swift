import Foundation
import XCTest
@testable import GameCore

final class SpriteMaskTests: XCTestCase {
    func testDecodesMostSignificantBitFirstRows() throws {
        let sprite = try SpriteMask(record: Data([2, 2, 0x80, 0x01, 0x01, 0x80]))
        XCTAssertEqual(sprite.width, 16)
        XCTAssertEqual(sprite.height, 2)
        XCTAssertTrue(try sprite.isSet(x: 0, y: 0))
        XCTAssertTrue(try sprite.isSet(x: 15, y: 0))
        XCTAssertTrue(try sprite.isSet(x: 7, y: 1))
        XCTAssertTrue(try sprite.isSet(x: 8, y: 1))
        XCTAssertFalse(try sprite.isSet(x: 1, y: 0))
    }

    func testRejectsTruncatedAndInvalidBounds() throws {
        XCTAssertThrowsError(try SpriteMask(record: Data([2, 2, 0x80])))
        XCTAssertThrowsError(try SpriteMask(record: Data([0, 2])))
        XCTAssertThrowsError(try SpriteMask(record: Data([9, 1])))
        let sprite = try SpriteMask(record: Data([1, 1, 0]))
        XCTAssertThrowsError(try sprite.isSet(x: 8, y: 0))
        XCTAssertThrowsError(try sprite.isSet(x: 0, y: -1))
    }
}
