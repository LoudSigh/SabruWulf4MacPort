public struct BackgroundScene: Sendable {
    public static let width = 256
    public static let height = 192

    public let colors: [SpectrumRGB]
    public let covered: [Bool]

    public init(
        world: WorldReference, atlas: BackgroundAtlas, template: Int,
        flashOn: Bool = false
    ) throws {
        try atlas.validate(world: world)
        guard world.rooms.indices.contains(template) else {
            throw WorldReferenceError.invalidPosition
        }
        var colors = Array(
            repeating: SpectrumRGB(red: 0, green: 0, blue: 0),
            count: Self.width * Self.height
        )
        var covered = Array(repeating: false, count: colors.count)
        for placement in world.rooms[template].placements {
            let mask = try atlas.mask(at: placement.graphicAddress)
            let indices = mask.paletteIndices(
                flashOn: flashOn, invertBitmap: true
            )
            for y in 0..<mask.height where placement.y + y < Self.height {
                for x in 0..<mask.width where placement.x + x < Self.width {
                    let target = (placement.y + y) * Self.width + placement.x + x
                    colors[target] = SpectrumPalette.colors[
                        Int(indices[y * mask.width + x])
                    ]
                    covered[target] = true
                }
            }
        }
        self.colors = colors
        self.covered = covered
    }

    public var rgba: [UInt8] {
        var result = [UInt8]()
        result.reserveCapacity(colors.count * 4)
        for index in colors.indices {
            let color = colors[index]
            result.append(contentsOf: [
                color.red, color.green, color.blue,
                covered[index] ? 255 : 0,
            ])
        }
        return result
    }
}
