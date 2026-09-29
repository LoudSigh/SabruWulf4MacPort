import Foundation

public enum CapturedCompletionEntryError: Error, LocalizedError {
    case unsupportedPlayer

    public var errorDescription: String? {
        "The measured completion entry covers only the source's normal player kinds."
    }
}

/// A source-selected spatial completion check; reaching this room naturally is unverified.
public enum CapturedCompletionEntry {
    public static func enters(
        playerKind: UInt8, playerRoom: UInt8, playerY: UInt8
    ) throws -> Bool {
        guard (16..<32).contains(Int(playerKind)) else {
            throw CapturedCompletionEntryError.unsupportedPlayer
        }
        return playerRoom == 136 && playerY < 128
    }
}
