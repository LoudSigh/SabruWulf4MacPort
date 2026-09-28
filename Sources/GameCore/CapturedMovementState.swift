import Foundation

public enum CapturedMovementError: Error, LocalizedError {
    case unsupportedBoundary
    case unsupportedAction
    case invalidInitialState

    public var errorDescription: String? {
        switch self {
        case .unsupportedBoundary:
            "This movement preview has not validated an exit in that direction."
        case .unsupportedAction:
            "Attack behavior has not been verified for this movement preview."
        case .invalidInitialState:
            "The imported world does not support the captured player start."
        }
    }
}

/// Source-backed movement from the captured gameplay state; dynamic actors and combat are excluded.
public struct CapturedMovementState: Sendable {
    public private(set) var room = WorldReference.capturedGameplayRoom
    public private(set) var player = WorldReference.capturedPlayerPosition
    public private(set) var frame = 0
    public private(set) var transitioning = false

    private let world: WorldReference
    private var velocityX = -3
    private var velocityY = 0
    private var pendingNorthFrames = 0
    private var pendingSouthFrames = 0
    private var pendingWestFrames = 0
    private var pendingEastFrames = 0
    private var settlingSouthFrames = 0

    public init(world: WorldReference) throws {
        guard world.schemaVersion == 2,
              try !world.overlapsBackgroundBounds(
                  in: Self.capturedRoom, actorAt: Self.capturedPosition,
                  width: 14, height: 22
              ) else {
            throw CapturedMovementError.invalidInitialState
        }
        self.world = world
    }

    private static let capturedRoom = WorldReference.capturedGameplayRoom
    private static let capturedPosition = WorldReference.capturedPlayerPosition

    public mutating func advance(holding actions: Set<OriginalAction> = []) throws {
        guard !actions.contains(.fire) else { throw CapturedMovementError.unsupportedAction }
        if pendingNorthFrames > 0 {
            pendingNorthFrames -= 1
            if pendingNorthFrames == 0 {
                player = GridPoint(player.x, 191)
                velocityX = decay(velocityX)
                velocityY = decay(velocityY)
                transitioning = false
            }
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

        let horizontal = (actions.contains(.right) ? 7 : 0) - (actions.contains(.left) ? 7 : 0)
        let vertical = (actions.contains(.up) ? 7 : 0) - (actions.contains(.down) ? 7 : 0)
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
            pendingNorthFrames = 7
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
        frame += 1
    }

    private func decay(_ velocity: Int) -> Int {
        if velocity > 0 { return velocity - 1 }
        if velocity < 0 { return velocity + 1 }
        return 0
    }
}
