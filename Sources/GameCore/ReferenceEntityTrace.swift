import CryptoKit
import Foundation

public enum ReferenceEntityTraceError: Error, LocalizedError {
    case unsupportedFormat
    case invalidFrames
    case mismatchedReplay
    case unverifiedOverlapTrace
    case unverifiedOverlapReplay

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "Not a supported private actor comparison."
        case .invalidFrames:
            "The actor comparison has missing or invalid frame positions."
        case .mismatchedReplay:
            "Import the matching gameplay replay before viewing this entity comparison."
        case .unverifiedOverlapTrace:
            "The slot-18 actor states differ from the measured source. Regenerate the private actor trace."
        case .unverifiedOverlapReplay:
            "The W replay's actor bitmap IDs differ from the measured source. Regenerate the private replay."
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
    private static let overlapTraceSHA256 =
        "f293a184e935767f69631bbccc25bc27468d12adfa8eafccf5c06c58ac8e669b"
    private static let overlapPlayerIDsSHA256 =
        "f911149f989670815f3f306426b154262da713fd3e8f2193ebc69593acea31c9"

    public let schemaVersion: Int
    public let snapshotSHA256: String
    public let frameBoundaryMode: String?
    public let framesCompared: Int
    public let trace: [ReferenceEntityFrame]
    public let entitySlot: Int?

    public var observedSlot: Int { entitySlot ?? 12 }

    public static func load(from data: Data) throws -> Self {
        guard data.count <= 2_000_000 else {
            throw ReferenceEntityTraceError.unsupportedFormat
        }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.schemaVersion == 1,
              result.snapshotSHA256 == WorldReference.supportedSnapshotSHA256,
              [12, 18].contains(result.observedSlot),
              (result.frameBoundaryMode.map {
                  ["absolute", "reference-relative"].contains($0)
              } ?? true) else {
            throw ReferenceEntityTraceError.unsupportedFormat
        }
        guard (1...900).contains(result.framesCompared),
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
        if result.observedSlot == 18 {
            guard result.entitySlot == 18,
                  result.frameBoundaryMode == "reference-relative",
                  result.framesCompared == 100,
                  result.trace.allSatisfy({
                      let manual = $0.manualEntity
                      let source = $0.fullEmulatorEntity
                      let player = $0.manualPlayer
                      let sourcePlayer = $0.fullEmulatorPlayer
                      return manual.kind == source.kind
                          && manual.roomID == source.roomID
                          && manual.x == source.x && manual.y == source.y
                          && player.roomID == sourcePlayer.roomID
                          && player.x == sourcePlayer.x && player.y == sourcePlayer.y
                  }) else {
                throw ReferenceEntityTraceError.invalidFrames
            }
            let recorded = Data(result.trace.flatMap { frame -> [UInt8] in
                let actor = frame.manualEntity
                let player = frame.manualPlayer
                return [
                    UInt8(actor.kind), UInt8(actor.roomID),
                    UInt8(actor.x), UInt8(actor.y),
                    UInt8(player.roomID), UInt8(player.x), UInt8(player.y),
                ]
            })
            guard digest(recorded) == Self.overlapTraceSHA256 else {
                throw ReferenceEntityTraceError.unverifiedOverlapTrace
            }
        }
        return result
    }

    public func validate(replay: ReferenceReplay) throws {
        if observedSlot == 18 {
            guard replay.frames.count == 100,
                  replay.schedule?.count == 1,
                  let interval = replay.schedule?.first,
                  interval.key == "w", interval.startFrame == 20,
                  interval.endFrame == 40,
                  replay.frames.allSatisfy({ $0.playerKind != nil }),
                  trace[42...52].allSatisfy({
                      $0.manualEntity.kind > 0
                          && $0.manualEntity.roomID == $0.manualPlayer.roomID
                  }) else {
                throw ReferenceEntityTraceError.mismatchedReplay
            }
            let ids = Data(replay.frames.compactMap { $0.playerKind }
                .map(UInt8.init))
            guard Self.digest(ids) == Self.overlapPlayerIDsSHA256 else {
                throw ReferenceEntityTraceError.unverifiedOverlapReplay
            }
        }
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

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func valid(_ marker: ReferenceActorMarker) -> Bool {
        (0...255).contains(marker.roomID)
            && (0...255).contains(marker.x)
            && (0...255).contains(marker.y)
    }
}
