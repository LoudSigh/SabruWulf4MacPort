import XCTest
@testable import GameCore

final class SpectrumCoordinatesTests: XCTestCase {
    func testSourceUpwardYBecomesScreenDownwardY() {
        XCTAssertEqual(SpectrumCoordinates.screenY(forSourceY: 112), 80)
        XCTAssertEqual(SpectrumCoordinates.screenY(forSourceY: 87), 105)
        XCTAssertEqual(SpectrumCoordinates.screenY(forSourceY: 134), 58)
        XCTAssertEqual(SpectrumCoordinates.backgroundTop(sourceY: 136, height: 56), 0)
        XCTAssertEqual(SpectrumCoordinates.backgroundTop(sourceY: 16, height: 88), 88)
    }
}
