/// Places a decoded player bitmap using the captured actor's screen X and bottom Y.
public struct CapturedActorSprite: Sendable {
    public let mask: SpriteMask
    public let topLeft: GridPoint

    public init(mask: SpriteMask, actorAt position: GridPoint) {
        self.mask = mask
        topLeft = GridPoint(position.x, position.y - mask.height + 1)
    }

    public func screenPixels() -> [Bool] {
        let source = mask.pixels()
        return (0..<mask.height).flatMap { y in
            let offset = (mask.height - y - 1) * mask.width
            return source[offset..<(offset + mask.width)]
        }
    }
}
