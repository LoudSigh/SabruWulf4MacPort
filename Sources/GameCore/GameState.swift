public struct GridPoint: Hashable, Sendable {
    public let x: Int
    public let y: Int

    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }
}

public enum Direction: Sendable {
    case north, south, west, east

    var offset: GridPoint {
        switch self {
        case .north: GridPoint(0, -1)
        case .south: GridPoint(0, 1)
        case .west: GridPoint(-1, 0)
        case .east: GridPoint(1, 0)
        }
    }
}

public struct RoomID: Hashable, Sendable {
    public let x: Int
    public let y: Int

    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }
}

public struct Room: Sendable {
    public static let width = 9
    public static let height = 7

    public let id: RoomID
    public let walls: Set<GridPoint>
    public let item: GridPoint

    public init(id: RoomID) {
        self.id = id
        self.item = GridPoint(6, 2)
        self.walls = [
            GridPoint(2, 2), GridPoint(2, 3), GridPoint(2, 4),
            GridPoint(5, 3), GridPoint(6, 3)
        ]
    }

    public func isWalkable(_ point: GridPoint) -> Bool {
        (0..<Self.width).contains(point.x)
            && (0..<Self.height).contains(point.y)
            && !walls.contains(point)
    }
}

public struct GameState: Sendable {
    public private(set) var roomID = RoomID(0, 0)
    public private(set) var player = GridPoint(1, 1)
    public private(set) var enemy = GridPoint(7, 5)
    public private(set) var health = 3
    public private(set) var collected: Set<RoomID> = []
    public private(set) var isPaused = false
    public private(set) var isGameOver = false
    public private(set) var tickCount = 0
    public private(set) var invulnerability = 0

    public var room: Room { Room(id: roomID) }

    public init() {}

    public mutating func reset() {
        self = GameState()
    }

    public mutating func togglePause() {
        guard !isGameOver else { return }
        isPaused.toggle()
    }

    public mutating func move(_ direction: Direction) {
        guard !isPaused && !isGameOver else { return }
        let delta = direction.offset
        let next = GridPoint(player.x + delta.x, player.y + delta.y)

        if room.isWalkable(next) {
            player = next
        } else if let destination = adjacentRoom(direction, from: player) {
            roomID = destination
            switch direction {
            case .north: player = GridPoint(4, Room.height - 1)
            case .south: player = GridPoint(4, 0)
            case .west: player = GridPoint(Room.width - 1, 3)
            case .east: player = GridPoint(0, 3)
            }
            enemy = GridPoint(7, 5)
            invulnerability = 1
        } else {
            return
        }

        if player == room.item {
            collected.insert(roomID)
        }
        checkEnemyContact()
    }

    public mutating func tick() {
        guard !isPaused && !isGameOver else { return }
        tickCount += 1
        if invulnerability > 0 { invulnerability -= 1 }
        // The enemy patrols a fixed, traversable two-cell segment.
        enemy = GridPoint(tickCount.isMultiple(of: 2) ? 7 : 6, 5)
        checkEnemyContact()
    }

    private mutating func checkEnemyContact() {
        guard player == enemy && invulnerability == 0 else { return }
        health -= 1
        if health == 0 {
            isGameOver = true
        } else {
            player = GridPoint(1, 1)
            invulnerability = 2
        }
    }

    private func adjacentRoom(_ direction: Direction, from point: GridPoint) -> RoomID? {
        let destination: RoomID
        switch direction {
        case .north where point == GridPoint(4, 0): destination = RoomID(roomID.x, roomID.y - 1)
        case .south where point == GridPoint(4, Room.height - 1):
            destination = RoomID(roomID.x, roomID.y + 1)
        case .west where point == GridPoint(0, 3): destination = RoomID(roomID.x - 1, roomID.y)
        case .east where point == GridPoint(Room.width - 1, 3):
            destination = RoomID(roomID.x + 1, roomID.y)
        default: return nil
        }
        guard (0..<2).contains(destination.x), (0..<2).contains(destination.y) else { return nil }
        return destination
    }
}
