import Foundation

public enum CapturedMovementError: Error, LocalizedError {
    case unsupportedBoundary
    case unsupportedAction
    case invalidInitialState
    case unsupportedSchedule
    case unsupportedTimeRange
    case unsupportedRuntimeDivergence

    public var errorDescription: String? {
        switch self {
        case .unsupportedBoundary:
            "This movement preview has not validated an exit in that direction."
        case .unsupportedAction:
            "Attack behavior has not been verified for this movement preview."
        case .invalidInitialState:
            "The imported world does not support the captured player start."
        case .unsupportedSchedule:
            "The observed new-game slice verifies 60 Q/W/E/R frames then idle, W for 18 then E for 42 and idle, or W for 18 then Q for 42 and 20 idle frames."
        case .unsupportedTimeRange:
            "The observed new-game movement slice ends after 110 source-checked frames."
        case .unsupportedRuntimeDivergence:
            "The measured path stops before an unclassified divergence (R after source frame 866, W/Q after frame 870)."
        }
    }
}

/// Source-backed movement from the captured gameplay state; dynamic actors and combat are excluded.
public enum CapturedMovementOrigin: Equatable, Sendable {
    case gameplayCapture
    case observedNewGameReady
}

public struct CapturedMovementState: Sendable {
    public private(set) var room = WorldReference.capturedGameplayRoom
    public private(set) var player = WorldReference.capturedPlayerPosition
    public private(set) var frame = 0
    public private(set) var transitioning = false
    public private(set) var playerSpriteID: Int?
    public let referenceFrameOffset: Int

    private let world: WorldReference
    private var velocityX = -3
    private var velocityY = 0
    private var pendingNorthFrames = 0
    private var settlingNorthFrames = 0
    private var pendingSouthFrames = 0
    private var pendingWestFrames = 0
    private var pendingEastFrames = 0
    private var settlingSouthFrames = 0
    private enum ReadyInputPath: Equatable, Sendable {
        case single(OriginalAction)
        case westThenNorth
        case rightThenLeft
    }

    private var readyInputPath: ReadyInputPath?
    private var observedSpritePhaseEpoch = 791
    private var reversedSpritePhase = false

    public init(
        world: WorldReference, origin: CapturedMovementOrigin = .gameplayCapture
    ) throws {
        let start = origin == .observedNewGameReady
            ? GridPoint(120, 112) : Self.capturedPosition
        guard world.schemaVersion == 2,
              try !world.overlapsBackgroundBounds(
                  in: Self.capturedRoom, actorAt: start,
                  width: 14, height: 22
              ) else {
            throw CapturedMovementError.invalidInitialState
        }
        self.world = world
        player = start
        referenceFrameOffset = origin == .observedNewGameReady ? 790 : 0
        velocityX = origin == .observedNewGameReady ? 0 : -3
        playerSpriteID = origin == .observedNewGameReady ? 16 : nil
    }

    private static let capturedRoom = WorldReference.capturedGameplayRoom
    private static let capturedPosition = WorldReference.capturedPlayerPosition

    public mutating func advance(holding actions: Set<OriginalAction> = []) throws {
        guard !actions.contains(.fire) else { throw CapturedMovementError.unsupportedAction }
        if referenceFrameOffset != 0 {
            if readyInputPath == .single(.down) && frame >= 76 {
                throw CapturedMovementError.unsupportedRuntimeDivergence
            }
            if readyInputPath == .rightThenLeft && frame >= 80 {
                throw CapturedMovementError.unsupportedRuntimeDivergence
            }
            guard frame < 110 else { throw CapturedMovementError.unsupportedTimeRange }
            if frame < 60 {
                guard actions.count == 1, let direction = actions.first,
                      direction != .fire else {
                    throw CapturedMovementError.unsupportedSchedule
                }
                if readyInputPath == nil { readyInputPath = .single(direction) }
                if frame == 18, readyInputPath == .single(.right),
                   direction == .up {
                    readyInputPath = .westThenNorth
                } else if frame == 18, readyInputPath == .single(.right),
                          direction == .left {
                    readyInputPath = .rightThenLeft
                }
                guard let readyInputPath else {
                    throw CapturedMovementError.unsupportedSchedule
                }
                let expected: OriginalAction = switch readyInputPath {
                case .single(let held): held
                case .westThenNorth: frame < 18 ? .right : .up
                case .rightThenLeft: frame < 18 ? .right : .left
                }
                guard direction == expected else {
                    throw CapturedMovementError.unsupportedSchedule
                }
            } else {
                guard actions.isEmpty else { throw CapturedMovementError.unsupportedSchedule }
            }
        }
        if pendingNorthFrames > 0 {
            pendingNorthFrames -= 1
            if pendingNorthFrames == 0 {
                player = GridPoint(player.x, 191)
                velocityX = decay(velocityX)
                velocityY = decay(velocityY)
                transitioning = false
                settlingNorthFrames = referenceFrameOffset == 0 ? 0 : 1
                if let playerSpriteID, referenceFrameOffset != 0 {
                    self.playerSpriteID = 28 + (playerSpriteID % 4 + 1) % 4
                    observedSpritePhaseEpoch -= 1
                }
            }
            frame += 1
            return
        }
        if settlingNorthFrames > 0 {
            settlingNorthFrames -= 1
            frame += 1
            return
        }
        if pendingSouthFrames > 0 {
            pendingSouthFrames -= 1
            if pendingSouthFrames == 0 {
                // The measured return path settles one pixel left before movement resumes.
                player = GridPoint(player.x - 1, 39)
                velocityX = decay(velocityX)
                velocityY = decay(velocityY)
                settlingSouthFrames = 1
            }
            frame += 1
            return
        }
        if pendingWestFrames > 0 {
            pendingWestFrames -= 1
            if pendingWestFrames == 0 {
                player = GridPoint(239, player.y)
                velocityX = decay(velocityX)
                velocityY = decay(velocityY)
                transitioning = false
            }
            frame += 1
            return
        }
        if pendingEastFrames > 0 {
            pendingEastFrames -= 1
            if pendingEastFrames == 0 {
                player = GridPoint(0, player.y)
                velocityX = decay(velocityX)
                velocityY = decay(velocityY)
                transitioning = false
            }
            frame += 1
            return
        }
        if settlingSouthFrames > 0 {
            settlingSouthFrames -= 1
            transitioning = false
            frame += 1
            return
        }

        let previous = player
        let horizontal = (actions.contains(.right) ? 7 : 0) - (actions.contains(.left) ? 7 : 0)
        let vertical = (actions.contains(.down) ? 7 : 0) - (actions.contains(.up) ? 7 : 0)
        let nextVX = min(48, max(-48, velocityX + horizontal))
        let nextVY = min(48, max(-48, velocityY + vertical))
        let next = GridPoint(player.x + nextVX / 16, player.y + nextVY / 16)

        if next.x >= 240 {
            guard room == RoomID(7, 9),
                  let east = world.adjacent(to: room, direction: .east),
                  east == RoomID(8, 9) else {
                throw CapturedMovementError.unsupportedBoundary
            }
            room = east
            velocityX = nextVX
            velocityY = nextVY
            pendingEastFrames = 7
            transitioning = true
        } else if next.x < 0 {
            guard room == RoomID(8, 9),
                  let west = world.adjacent(to: room, direction: .west),
                  west == RoomID(7, 9) else {
                throw CapturedMovementError.unsupportedBoundary
            }
            room = west
            velocityX = nextVX
            velocityY = nextVY
            pendingWestFrames = 7
            transitioning = true
        } else if next.y < 40 {
            guard room == WorldReference.capturedGameplayRoom,
                  let north = world.adjacent(to: room, direction: .north),
                  north == RoomID(8, 9) else {
                throw CapturedMovementError.unsupportedBoundary
            }
            room = north
            velocityX = nextVX
            velocityY = nextVY
            pendingNorthFrames = referenceFrameOffset == 0 ? 7 : 6
            transitioning = true
        } else if next.y >= 192 {
            guard room == RoomID(8, 9),
                  let south = world.adjacent(to: room, direction: .south),
                  south == WorldReference.capturedGameplayRoom else {
                throw CapturedMovementError.unsupportedBoundary
            }
            room = south
            velocityX = nextVX
            velocityY = nextVY
            pendingSouthFrames = 6
            transitioning = true
        } else {
            player = try world.resolveBackgroundBounds(
                in: room, from: player, to: next, width: 14, height: 22
            )
            velocityX = decay(nextVX)
            velocityY = decay(nextVY)
        }
        if referenceFrameOffset != 0, !actions.isEmpty, player != previous {
            let dx = player.x - previous.x
            let dy = player.y - previous.y
            if readyInputPath == .rightThenLeft, dx < 0, !reversedSpritePhase {
                observedSpritePhaseEpoch -= 4
                reversedSpritePhase = true
            }
            let base = dx != 0
                ? (dx > 0 ? 20 : 16) : (dy > 0 ? 28 : 24)
            let sourceFrame = referenceFrameOffset + frame + 1
            playerSpriteID = base + ((sourceFrame - observedSpritePhaseEpoch) / 2) % 4
        }
        if readyInputPath == .westThenNorth, frame >= 76 {
            playerSpriteID = nil
        }
        if readyInputPath == .rightThenLeft, frame >= 60 {
            playerSpriteID = nil
        }
        frame += 1
    }

    private func decay(_ velocity: Int) -> Int {
        if velocity > 0 { return velocity - 1 }
        if velocity < 0 { return velocity + 1 }
        return 0
    }
}
