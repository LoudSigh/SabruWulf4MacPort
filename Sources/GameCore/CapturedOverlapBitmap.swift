/// Projects the observed two-actor bitmap XOR; selecting an overlap and its draw timing remain external.
public enum CapturedOverlapBitmap {
    public static func xorPlayerRectangle(
        player: CapturedActorSprite, overlapping: CapturedActorSprite
    ) -> [Bool] {
        let playerPixels = player.screenPixels()
        let otherPixels = overlapping.screenPixels()
        return playerPixels.enumerated().map { index, playerOn in
            let x = player.topLeft.x + index % player.mask.width
            let y = player.topLeft.y + index / player.mask.width
            let otherColumn = x - overlapping.topLeft.x
            let otherRow = y - overlapping.topLeft.y
            guard (0..<overlapping.mask.width).contains(otherColumn),
                  (0..<overlapping.mask.height).contains(otherRow) else {
                return playerOn
            }
            return playerOn != otherPixels[
                otherRow * overlapping.mask.width + otherColumn
            ]
        }
    }
}
