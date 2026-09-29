import Foundation

public enum PrivateReferenceBundleError: Error, LocalizedError {
    case missingFile(String)
    case emptyFile(String)
    case oversizedFile(String)

    public var errorDescription: String? {
        switch self {
        case .missingFile(let name):
            "The private reference folder is missing \(name). Run the local preview launcher first."
        case .emptyFile(let name):
            "The private reference file \(name) is empty."
        case .oversizedFile(let name):
            "The private reference file \(name) exceeds its import limit."
        }
    }
}

/// A local-only import of the verified reference files; no source assets are bundled.
public struct PrivateReferenceBundle {
    public let world: WorldReference
    public let backgrounds: BackgroundAtlas
    public let sprites: SpriteAtlas
    public let placements: CapturedPlacementState
    public let replay: ReferenceReplay

    public static func load(from directory: URL) throws -> Self {
        let prefix = "snapshot-\(WorldReference.supportedSnapshotSHA256.prefix(12))"
        func read(_ name: String, maximum: Int) throws -> Data {
            let url = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw PrivateReferenceBundleError.missingFile(name)
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { handle.closeFile() }
            guard let data = try handle.read(upToCount: maximum + 1), !data.isEmpty
            else { throw PrivateReferenceBundleError.emptyFile(name) }
            guard data.count <= maximum else {
                throw PrivateReferenceBundleError.oversizedFile(name)
            }
            return data
        }

        let world = try WorldReference.load(
            from: read("\(prefix)-world-v2.json", maximum: 2_000_000)
        )
        let backgrounds = try BackgroundAtlas.load(
            from: read("\(prefix)-background-atlas-v1.json", maximum: 100_000)
        )
        try backgrounds.validate(world: world)
        let sprites = try SpriteAtlas.load(
            from: read("\(prefix)-sprite-atlas-v1.json", maximum: 100_000)
        )
        let placements = try CapturedPlacementState.load(
            from: read("\(prefix)-placement-frame656-v1.json", maximum: 32_000),
            world: world
        )
        try placements.validate(spriteAtlas: sprites)
        let replay = try ReferenceReplay.load(
            from: read("replay-restart-e-q-west-1050.json", maximum: 2_000_000)
        )
        return Self(
            world: world, backgrounds: backgrounds, sprites: sprites,
            placements: placements, replay: replay
        )
    }
}
