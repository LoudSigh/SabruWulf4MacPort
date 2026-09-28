import XCTest
@testable import GameCore

final class SpectrumAttributeTests: XCTestCase {
    func testInkPaperBrightAndFlash() {
        let greenPaper = SpectrumAttribute(0x60)
        XCTAssertEqual(greenPaper.inkIndex, 0)
        XCTAssertEqual(greenPaper.paperIndex, 4)
        XCTAssertTrue(greenPaper.bright)
        XCTAssertEqual(greenPaper.paletteIndex(pixelOn: true), 8)
        XCTAssertEqual(greenPaper.paletteIndex(pixelOn: false), 12)
        XCTAssertEqual(SpectrumPalette.colors[12], SpectrumRGB(
            red: 0, green: 255, blue: 0
        ))

        let flash = SpectrumAttribute(0x92)
        XCTAssertTrue(flash.flashes)
        XCTAssertEqual(flash.paletteIndex(pixelOn: true), 2)
        XCTAssertEqual(flash.paletteIndex(pixelOn: true, flashOn: true), 2)
        XCTAssertEqual(SpectrumPalette.colors[2], SpectrumRGB(
            red: 215, green: 0, blue: 0
        ))
        let inverted = SpectrumAttribute(0xA2)
        XCTAssertEqual(inverted.paletteIndex(pixelOn: true), 2)
        XCTAssertEqual(inverted.paletteIndex(pixelOn: true, flashOn: true), 4)
    }
}
