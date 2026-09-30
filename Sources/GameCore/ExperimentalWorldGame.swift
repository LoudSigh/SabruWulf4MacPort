import Foundation

public enum ExperimentalWorldGameError: Error, LocalizedError {
    case invalidStart
    case unsupportedInput

    public var errorDescription: String? {
        switch self {
        case .invalidStart:
            "The imported world does not support the observed new-game start."
        case .unsupportedInput:
            "Experimental exploration supports one direction at a time; combat is not implemented."
        }
    }
}

/// Opt-in free exploration. Unobserved exits and automatic record polling are
/// experimental; the strictly replay-checked movement preview remains separate.
public struct ExperimentalWorldGame: Sendable {
    public private(set) var room = WorldReference.capturedGameplayRoom
    public private(set) var player = GridPoint(120, 112)
    public private(set) var frame = 0
    public private(set) var progressBits: UInt8 = 0
    public private(set) var collectedRecordIDs: Set<Int> = []
    public private(set) var scores: CapturedScoreState
    public private(set) var paused = false
    public private(set) var facing: OriginalAction = .right

    private let world: WorldReference
    private let placements: CapturedPlacementState
    private var velocityX = 0
    private var velocityY = 0
    private var crossing: (direction: OriginalAction, ticks: Int)?
    private var settling = 0

    public init(world: WorldReference, placements: CapturedPlacementState) throws {
        guard world.schemaVersion == 2,
              placements.snapshotSHA256 == world.snapshotSha256,
              placements.records.count == 4,
              placements.records.allSatisfy({
                  (144...147).contains($0.spriteID)
              }),
              try !world.overlapsBackgroundBounds(
                  in: WorldReference.capturedGameplayRoom,
                  actorAt: GridPoint(120, 112), width: 14, height: 22
              ) else {
            throw ExperimentalWorldGameError.invalidStart
        }
        self.world = world
        self.placements = placements
        let empty = try CapturedPackedScore(bytes: [0, 0, 0])
        scores = CapturedScoreState(first: empty, second: empty)
    }

    public mutating func togglePause() { paused.toggle() }

    public mutating func advance(holding actions: Set<OriginalAction>) throws {
        guard actions.count <= 1, !actions.contains(.fire) else {
            throw ExperimentalWorldGameError.unsupportedInput
        }
        guard !paused else { return }
        if var crossing {
            crossing.ticks -= 1
            if crossing.ticks == 0 {
                switch crossing.direction {
                case .left: player = GridPoint(239, player.y)
                case .right: player = GridPoint(0, player.y)
                case .up: player = GridPoint(player.x, 191)
                case .down: player = GridPoint(player.x - 1, 39)
                case .fire: throw ExperimentalWorldGameError.unsupportedInput
                }
                velocityX = Self.decay(velocityX)
                velocityY = Self.decay(velocityY)
                settling = crossing.direction == .up || crossing.direction == .down ? 1 : 0
                self.crossing = nil
            } else {
                self.crossing = crossing
            }
            frame += 1
            return
        }
        if settling > 0 {
            settling -= 1
            frame += 1
            return
        }

        let action = actions.first
        if let action { facing = action }
        let horizontal = action == .right ? 7 : action == .left ? -7 : 0
        let vertical = action == .down ? 7 : action == .up ? -7 : 0
        let nextVX = min(48, max(-48, velocityX + horizontal))
        let nextVY = min(48, max(-48, velocityY + vertical))
        let candidate = GridPoint(
            player.x + nextVX / 16, player.y + nextVY / 16
        )
        let exit: (Direction, OriginalAction, Int)?
        if candidate.x >= 240 {
            exit = (.east, .right, 7)
        } else if candidate.x < 0 {
            exit = (.west, .left, 7)
        } else if candidate.y < 40 {
            exit = (.north, .up, 6)
        } else if candidate.y >= 192 {
            exit = (.south, .down, 6)
        } else {
            exit = nil
        }

        if let (direction, action, ticks) = exit {
            if let destination = world.adjacent(to: room, direction: direction) {
                room = destination
                velocityX = nextVX
                velocityY = nextVY
                crossing = (action, ticks)
            } else {
                velocityX = 0
                velocityY = 0
            }
        } else {
            player = try world.resolveBackgroundBounds(
                in: room, from: player, to: candidate, width: 14, height: 22
            )
            velocityX = Self.decay(nextVX)
            velocityY = Self.decay(nextVY)
            try checkRecords()
        }
        frame += 1
    }

    private mutating func checkRecords() throws {
        let roomIndex = UInt8(room.y * 16 + room.x)
        let kind: UInt8 = switch facing {
        case .left: 16
        case .right: 20
        case .up: 24
        case .down: 28
        case .fire: throw ExperimentalWorldGameError.unsupportedInput
        }
        for record in placements.records where !collectedRecordIDs.contains(record.id) {
            guard CapturedItemContact.overlaps(
                playerKind: kind, playerRoom: roomIndex,
                playerX: UInt8(player.x), playerY: UInt8(player.y),
                suppressionFlag: 0, recordRoom: UInt8(record.roomID),
                recordX: UInt8(record.x), recordY: UInt8(record.y)
            ) else { continue }
            let award = try CapturedRecordAward.applyOnObservedHandler(
                recordKind: UInt8(record.spriteID), activePlayer: 0,
                progressBits: progressBits, scores: scores
            )
            progressBits = award.progressBits
            scores = award.scores
            collectedRecordIDs.insert(record.id)
        }
    }

    private static func decay(_ velocity: Int) -> Int {
        if velocity > 0 { return velocity - 1 }
        if velocity < 0 { return velocity + 1 }
        return 0
    }
}
