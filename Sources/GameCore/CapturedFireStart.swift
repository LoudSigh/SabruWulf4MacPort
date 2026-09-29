import Foundation

public enum CapturedFireStartError: Error, LocalizedError {
    case unsupportedState

    public var errorDescription: String? {
        "The measured fire entry requires a normal player kind and the observed ready state."
    }
}

public struct CapturedFireEntry: Equatable, Sendable {
    public let kind: UInt8
    public let sourceByte96AD: UInt8
}

/// One source-selected fire entry; no swing cadence, collision or damage is implied.
public enum CapturedFireStart {
    public static func begin(
        playerKind: UInt8, playerByte5: UInt8
    ) throws -> CapturedFireEntry {
        guard (16..<32).contains(Int(playerKind)), playerByte5 == 0x47 else {
            throw CapturedFireStartError.unsupportedState
        }
        return CapturedFireEntry(
            kind: 32 | ((playerKind << 1) & 0x0F),
            sourceByte96AD: 24
        )
    }
}
