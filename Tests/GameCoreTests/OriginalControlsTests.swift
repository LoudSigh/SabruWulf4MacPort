import XCTest
@testable import GameCore

final class OriginalControlsTests: XCTestCase {
    func testSpectrumKeyboardRowMapsToFiveActions() {
        XCTAssertEqual(OriginalAction.fromSpectrumKey("q"), .left)
        XCTAssertEqual(OriginalAction.fromSpectrumKey("w"), .right)
        XCTAssertEqual(OriginalAction.fromSpectrumKey("e"), .up)
        XCTAssertEqual(OriginalAction.fromSpectrumKey("r"), .down)
        XCTAssertEqual(OriginalAction.fromSpectrumKey("t"), .fire)
        XCTAssertEqual(OriginalAction.fromSpectrumKey("Q"), .left)
    }

    func testUnrelatedKeysAreNotInventedOriginalControls() {
        XCTAssertNil(OriginalAction.fromSpectrumKey("a"))
        XCTAssertNil(OriginalAction.fromSpectrumKey("p"))
        XCTAssertNil(OriginalAction.fromSpectrumKey(" "))
    }
}
