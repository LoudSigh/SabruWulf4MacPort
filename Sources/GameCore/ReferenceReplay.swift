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
    public let playerKind: Int?
    public let reportedLives: Int
}

public struct ReferenceInputInterval: Decodable, Sendable {
    public let key: String
    public let startFrame: Int
    public let endFrame: Int
}

/// Recorded source-state observations, not a substitute for the native game simulation.
public struct ReferenceReplay: Decodable, Sendable {
    public let schemaVersion: Int
    public let snapshotSHA256: String
    public let frameBoundaryMode: String?
    public let input: String
    public let schedule: [ReferenceInputInterval]?
    public let frames: [ReferenceFrame]

    public static func load(from data: Data) throws -> Self {
        guard data.count <= 2_000_000 else { throw ReferenceReplayError.unsupportedFormat }
        let replay = try JSONDecoder().decode(Self.self, from: data)
        guard replay.snapshotSHA256 == WorldReference.supportedSnapshotSHA256
        else {
            throw ReferenceReplayError.unsupportedFormat
        }
        guard replay.frameBoundaryMode == nil
                || replay.frameBoundaryMode == "reference-relative" else {
            throw ReferenceReplayError.unsupportedFormat
        }
        let keys = ["q", "w", "e", "r", "t", "a", "o", "p", "space"]
        switch replay.schemaVersion {
        case 1:
            guard replay.schedule == nil,
                  (1...150).contains(replay.frames.count),
                  (keys + ["none"]).contains(replay.input) else {
                throw ReferenceReplayError.unsupportedFormat
            }
        case 2:
            guard replay.input == "schedule",
                  (1...600).contains(replay.frames.count),
                  let schedule = replay.schedule, !schedule.isEmpty else {
                throw ReferenceReplayError.unsupportedFormat
            }
            var previousEnd = 0
            for interval in schedule {
                guard keys.contains(interval.key),
                      interval.startFrame >= previousEnd,
                      interval.endFrame > interval.startFrame,
                      interval.endFrame <= replay.frames.count else {
                    throw ReferenceReplayError.invalidFrames
                }
                previousEnd = interval.endFrame
            }
        default:
            throw ReferenceReplayError.unsupportedFormat
        }
        guard replay.frames.enumerated().allSatisfy({ offset, frame in
            frame.index == offset + 1
                && (0..<256).contains(frame.playerRoomID)
                && (0..<256).contains(frame.playerX)
                && (0..<192).contains(frame.playerY)
                && (frame.playerKind.map { (0...255).contains($0) } ?? true)
                && (0...9).contains(frame.reportedLives)
        })
        else {
            throw ReferenceReplayError.invalidFrames
        }
        return replay
    }
}
