import Foundation

public enum CapturedActiveEnemyError: Error, LocalizedError {
    case unsupportedState

    public var errorDescription: String? {
        "This enemy state is supported only for observed slot-12 movement, countdown and expiry events in room 152."
    }
}

/// One observed enemy update; frame scheduling and RNG selection are external.
public struct CapturedActiveEnemyState: Equatable, Sendable {
    public private(set) var kind: UInt8
    public private(set) var timer: UInt8
    public private(set) var position: GridPoint
    public private(set) var velocityX: Int
    public private(set) var velocityY: Int
    public let room: RoomID
    private var pendingTerminalMotion = false

    public init(
        kind: UInt8, timer: UInt8, room: RoomID, position: GridPoint,
        velocityX: Int, velocityY: Int
    ) throws {
        guard (108...111).contains(Int(kind)), (2...15).contains(Int(timer)),
              room == RoomID(8, 9),
              [-80, -48, 48, 96].contains(velocityX), velocityY == 80 else {
            throw CapturedActiveEnemyError.unsupportedState
        }
        self.kind = kind
        self.timer = timer
        self.position = position
        self.velocityX = velocityX
        self.velocityY = velocityY
        self.room = room
    }

    public mutating func advanceOnSourceUpdate(
        world: WorldReference, countdownOccurred: Bool = true
    ) throws {
        let firstPhase = (2...15).contains(Int(timer))
        let terminalMotion = timer == 1 && pendingTerminalMotion && !countdownOccurred
        let resumedPhase = [UInt8(0), 254, 255].contains(timer)
            && velocityX == -80 && velocityY == 80
        guard (firstPhase || terminalMotion || resumedPhase),
              [-80, -48, 48, 96].contains(velocityX), velocityY == 80,
              !countdownOccurred || (firstPhase || timer == 0 || timer == 255) else {
            throw CapturedActiveEnemyError.unsupportedState
        }
        let next = try CapturedEntityMotion.advanceOnSourceUpdate(
            kind: kind, room: room, from: position,
            velocityX: velocityX, velocityY: velocityY, world: world
        )
        position = next
        kind ^= 1
        pendingTerminalMotion = false
        if countdownOccurred { timer &-= 1 }
    }

    public mutating func advanceCountdownOnSourceUpdate() throws {
        guard (2...15).contains(Int(timer))
                || ((timer == 0 || timer == 255)
                    && velocityX == -80 && velocityY == 80) else {
            throw CapturedActiveEnemyError.unsupportedState
        }
        pendingTerminalMotion = timer == 2
        timer &-= 1
    }

    public mutating func expireOnSourceUpdate(
        rngByte: UInt8, clockByte: UInt8
    ) throws {
        guard timer == 1 else { throw CapturedActiveEnemyError.unsupportedState }
        let next = try CapturedEnemyExpiry.resolve(
            kind: kind, timer: timer, room: room,
            velocityX: velocityX, velocityY: velocityY,
            rngByte: rngByte, clockByte: clockByte
        )
        kind = next.kind
        timer = next.timer
        velocityX = next.velocityX
        velocityY = next.velocityY
        pendingTerminalMotion = false
    }
}
