import Foundation

public enum ReferenceEntityTraceError: Error, LocalizedError {
    case unsupportedFormat
    case invalidFrames
    case mismatchedReplay

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "Not a supported private moving-entity comparison."
        case .invalidFrames:
            "The moving-entity comparison has missing or invalid frame positions."
        case .mismatchedReplay:
            "Import the matching gameplay replay before viewing this entity comparison."
        }
    }
}

public struct ReferenceEntityMarker: Decodable, Sendable {
    public let kind: Int
    public let roomID: Int
    public let x: Int
    public let y: Int
}

public struct ReferenceActorMarker: Decodable, Sendable {
    public let roomID: Int
    public let x: Int
    public let y: Int
}

public struct ReferenceEntityFrame: Decodable, Sendable {
    public let index: Int
    public let manualEntity: ReferenceEntityMarker
    public let fullEmulatorEntity: ReferenceEntityMarker
    public let manualPlayer: ReferenceActorMarker
    public let fullEmulatorPlayer: ReferenceActorMarker
}

/// A local comparison of one moving-entity slot, not native enemy AI.
public struct ReferenceEntityTrace: Decodable, Sendable {
    public let schemaVersion: Int
    public let snapshotSHA256: String
    public let frameBoundaryMode: String?
    public let framesCompared: Int
    public let trace: [ReferenceEntityFrame]

    public static func load(from data: Data) throws -> Self {
        guard data.count <= 2_000_000 else {
            throw ReferenceEntityTraceError.unsupportedFormat
        }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.schemaVersion == 1,
              result.snapshotSHA256 == WorldReference.supportedSnapshotSHA256,
              (result.frameBoundaryMode.map {
                  ["absolute", "reference-relative"].contains($0)
              } ?? true) else {
            throw ReferenceEntityTraceError.unsupportedFormat
        }
        guard (1...800).contains(result.framesCompared),
              result.trace.count == result.framesCompared,
              result.trace.enumerated().allSatisfy({ offset, frame in
                  frame.index == offset + 1
                      && valid(frame.manualEntity)
                      && valid(frame.fullEmulatorEntity)
                      && valid(frame.manualPlayer)
                      && valid(frame.fullEmulatorPlayer)
              }) else {
            throw ReferenceEntityTraceError.invalidFrames
        }
        return result
    }

    public func validate(replay: ReferenceReplay) throws {
        guard replay.snapshotSHA256 == snapshotSHA256,
              (replay.frameBoundaryMode ?? "absolute")
                == (frameBoundaryMode ?? "absolute"),
              replay.frames.count == framesCompared,
              zip(replay.frames, trace).allSatisfy({ pair in
                  let (frame, entityFrame) = pair
                  return frame.playerRoomID == entityFrame.manualPlayer.roomID
                      && frame.playerX == entityFrame.manualPlayer.x
                      && frame.playerY == entityFrame.manualPlayer.y
              }) else {
            throw ReferenceEntityTraceError.mismatchedReplay
        }
    }

    private static func valid(_ marker: ReferenceEntityMarker) -> Bool {
        (0...255).contains(marker.kind)
            && (0...255).contains(marker.roomID)
            && (0...255).contains(marker.x)
            && (0...255).contains(marker.y)
    }

    private static func valid(_ marker: ReferenceActorMarker) -> Bool {
        (0...255).contains(marker.roomID)
            && (0...255).contains(marker.x)
            && (0...255).contains(marker.y)
    }
}
