public struct SpectrumRGB: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
}

/// Standard 48K ULA attribute decoding, independent of room draw order.
public struct SpectrumAttribute: Sendable {
    public let value: UInt8

    public init(_ value: UInt8) {
        self.value = value
    }

    public var inkIndex: UInt8 { value & 0x07 }
    public var paperIndex: UInt8 { (value >> 3) & 0x07 }
    public var bright: Bool { value & 0x40 != 0 }
    public var flashes: Bool { value & 0x80 != 0 }

    public func paletteIndex(pixelOn: Bool, flashOn: Bool = false) -> UInt8 {
        let inverted = flashes && flashOn
        let color = pixelOn != inverted ? inkIndex : paperIndex
        return color + (bright ? 8 : 0)
    }
}

public enum SpectrumPalette {
    public static let colors: [SpectrumRGB] = (0..<16).map { index in
        let value = (index & 7) == 0 ? UInt8(0)
            : (index & 8) == 0 ? UInt8(0xD7) : UInt8(0xFF)
        return SpectrumRGB(
            red: index & 2 == 0 ? 0 : value,
            green: index & 4 == 0 ? 0 : value,
            blue: index & 1 == 0 ? 0 : value
        )
    }
}
