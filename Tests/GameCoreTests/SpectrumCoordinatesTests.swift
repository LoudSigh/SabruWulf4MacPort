import XCTest
@testable import GameCore

final class SpectrumCoordinatesTests: XCTestCase {
    func testSourceCoordinatesMatchScreenCoordinates() {
        XCTAssertEqual(SpectrumCoordinates.screenY(forSourceY: 112), 112)
        XCTAssertEqual(SpectrumCoordinates.screenY(forSourceY: 87), 87)
        XCTAssertEqual(SpectrumCoordinates.screenY(forSourceY: 134), 134)
        XCTAssertEqual(SpectrumCoordinates.backgroundTop(sourceY: 136), 136)
        XCTAssertEqual(SpectrumCoordinates.backgroundTop(sourceY: 16), 16)
    }
}
