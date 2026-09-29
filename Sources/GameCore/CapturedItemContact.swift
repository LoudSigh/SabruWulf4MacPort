/// A source-selected item/record contact test; it does not schedule pickup or infer inventory.
public enum CapturedItemContact {
    public static func overlaps(
        playerKind: UInt8, playerRoom: UInt8, playerX: UInt8, playerY: UInt8,
        suppressionFlag: UInt8,
        recordRoom: UInt8, recordX: UInt8, recordY: UInt8
    ) -> Bool {
        guard suppressionFlag == 0, playerRoom == recordRoom,
              (16..<48).contains(Int(playerKind)) else {
            return false
        }
        return CapturedActorContact.geometryOverlaps(
            playerKind: playerKind, playerX: playerX, playerY: playerY,
            otherX: recordX, otherY: recordY,
            playerRightReach: 12, playerAboveReach: 12
        )
    }
}
