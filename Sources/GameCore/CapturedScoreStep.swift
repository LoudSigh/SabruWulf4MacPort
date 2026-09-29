import Foundation

public enum CapturedScoreError: Error, LocalizedError {
    case unsupportedState

    public var errorDescription: String? {
        "The measured score update requires three valid packed-BCD bytes per player and two valid packed-BCD point bytes."
    }
}

public struct CapturedPackedScore: Decodable, Equatable, Sendable {
    public let high: UInt8
    public let middle: UInt8
    public let low: UInt8

    public init(bytes: [UInt8]) throws {
        guard bytes.count == 3, bytes.allSatisfy(Self.isBCD) else {
            throw CapturedScoreError.unsupportedState
        }
        high = bytes[0]
        middle = bytes[1]
        low = bytes[2]
    }

    public var bytes: [UInt8] { [high, middle, low] }
    public var decimalValue: Int {
        Self.decimal(high) * 10_000
            + Self.decimal(middle) * 100 + Self.decimal(low)
    }

    public init(from decoder: Decoder) throws {
        try self.init(bytes: decoder.singleValueContainer().decode([UInt8].self))
    }

    func adding(upper: UInt8, lower: UInt8) throws -> Self {
        guard Self.isBCD(upper), Self.isBCD(lower) else {
            throw CapturedScoreError.unsupportedState
        }
        let points = Self.decimal(upper) * 100 + Self.decimal(lower)
        let next = (decimalValue + points) % 1_000_000
        return try Self(bytes: [
            Self.bcd(next / 10_000),
            Self.bcd((next / 100) % 100),
            Self.bcd(next % 100),
        ])
    }

    private static func isBCD(_ byte: UInt8) -> Bool {
        byte >> 4 <= 9 && byte & 0x0F <= 9
    }

    private static func decimal(_ byte: UInt8) -> Int {
        Int(byte >> 4) * 10 + Int(byte & 0x0F)
    }

    private static func bcd(_ value: Int) -> UInt8 {
        UInt8((value / 10) << 4 | (value % 10))
    }
}

/// A source-supplied scoring call; item awards and call timing remain external.
public struct CapturedScoreState: Equatable, Sendable {
    public private(set) var first: CapturedPackedScore
    public private(set) var second: CapturedPackedScore

    public init(first: CapturedPackedScore, second: CapturedPackedScore) {
        self.first = first
        self.second = second
    }

    public mutating func add(
        activePlayer: UInt8, pointsUpper: UInt8, pointsLower: UInt8
    ) throws {
        switch activePlayer {
        case 0:
            first = try first.adding(upper: pointsUpper, lower: pointsLower)
        case 1:
            second = try second.adding(upper: pointsUpper, lower: pointsLower)
        default:
            throw CapturedScoreError.unsupportedState
        }
    }
}
