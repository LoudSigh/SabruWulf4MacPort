import Foundation

public enum ReferenceReplayError: Error, LocalizedError {
    case unsupportedFormat
    case invalidFrames

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "Not a supported private Sabre Wulf gameplay replay."
        case .invalidFrames:
            "Replay frames must be sequential with valid actor coordinates."
        }
    }
}

public struct ReferenceFrame: Decodable, Sendable {
    public let index: Int
    public let playerRoomID: Int
    public let playerX: Int
    public let playerY: Int
    public let reportedLives: Int
}

/// Recorded source-state observations, not a substitute for the native game simulation.
public struct ReferenceReplay: Decodable, Sendable {
    public let schemaVersion: Int
    public let snapshotSHA256: String
    public let input: String
    public let frames: [ReferenceFrame]

    public static func load(from data: Data) throws -> Self {
        guard data.count <= 2_000_000 else { throw ReferenceReplayError.unsupportedFormat }
        let replay = try JSONDecoder().decode(Self.self, from: data)
        guard replay.schemaVersion == 1,
              replay.snapshotSHA256 == WorldReference.supportedSnapshotSHA256,
              ["none", "q", "w", "e", "r", "t", "a", "o", "p", "space"].contains(replay.input)
        else {
            throw ReferenceReplayError.unsupportedFormat
        }
        guard (1...150).contains(replay.frames.count),
              replay.frames.enumerated().allSatisfy({ offset, frame in
                  frame.index == offset + 1
                      && (0..<256).contains(frame.playerRoomID)
                      && (0..<256).contains(frame.playerX)
                      && (0..<192).contains(frame.playerY)
                      && (0...9).contains(frame.reportedLives)
              })
        else {
            throw ReferenceReplayError.invalidFrames
        }
        return replay
    }
}
