import Foundation

public enum SpriteMaskError: Error, LocalizedError {
    case invalidRecord
    case outOfBounds

    public var errorDescription: String? {
        switch self {
        case .invalidRecord: "Invalid 48K sprite bitmap record."
        case .outOfBounds: "Sprite pixel coordinate is outside the bitmap."
        }
    }
}

/// Decodes the bitmap shape only. Palette, mask compositing, and animation are separate.
public struct SpriteMask: Sendable {
    public let width: Int
    public let height: Int
    private let bitmap: [UInt8]

    public init(record: Data) throws {
        guard record.count >= 2 else { throw SpriteMaskError.invalidRecord }
        let bytesPerRow = Int(record[0])
        let height = Int(record[1])
        guard (1...8).contains(bytesPerRow),
              (1...64).contains(height),
              record.count == 2 + bytesPerRow * height
        else {
            throw SpriteMaskError.invalidRecord
        }
        width = bytesPerRow * 8
        self.height = height
        bitmap = Array(record.dropFirst(2))
    }

    public func isSet(x: Int, y: Int) throws -> Bool {
        guard (0..<width).contains(x), (0..<height).contains(y) else {
            throw SpriteMaskError.outOfBounds
        }
        let offset = y * (width / 8) + x / 8
        return bitmap[offset] & (1 << (7 - x % 8)) != 0
    }
}
