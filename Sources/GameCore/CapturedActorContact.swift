/// A source-checked player/entity contact predicate; it does not apply damage.
public enum CapturedActorContact {
    public static func overlaps(
        playerKind: UInt8, playerRoom: UInt8, playerX: UInt8, playerY: UInt8,
        playerByte5: UInt8, suppressionFlag: UInt8,
        otherRoom: UInt8, otherX: UInt8, otherY: UInt8,
        playerRightReach: UInt8, playerAboveReach: UInt8
    ) -> Bool {
        guard playerByte5 == 0x47, suppressionFlag == 0,
              playerRoom == otherRoom, (16..<48).contains(Int(playerKind)) else {
            return false
        }
        return geometryOverlaps(
            playerKind: playerKind, playerX: playerX, playerY: playerY,
            otherX: otherX, otherY: otherY,
            playerRightReach: playerRightReach,
            playerAboveReach: playerAboveReach
        )
    }

    static func geometryOverlaps(
        playerKind: UInt8, playerX: UInt8, playerY: UInt8,
        otherX: UInt8, otherY: UInt8,
        playerRightReach: UInt8, playerAboveReach: UInt8
    ) -> Bool {
        let dx = Int(playerX) - Int(otherX)
        let horizontalReach = dx < 0
            ? (playerKind < 32 ? 12 : 28) : Int(playerRightReach)
        guard abs(dx) < horizontalReach else { return false }
        let dy = Int(playerY) - Int(otherY)
        let verticalReach = dy < 0 ? Int(playerAboveReach) : 15
        return abs(dy) < verticalReach
    }
}
