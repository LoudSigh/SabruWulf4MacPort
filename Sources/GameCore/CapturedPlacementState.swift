import Foundation

public enum CapturedPlacementError: Error, LocalizedError {
    case unsupportedFormat
    case sourceMismatch
    case invalidRecord
    case missingSprite

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "Not a supported private four-record placement export."
        case .sourceMismatch:
            "The placement export does not match the imported 48K world."
        case .invalidRecord:
            "The placement contains an invalid record ID, room, coordinate or sprite ID."
        case .missingSprite:
            "Import the matching private sprite atlas; each record needs a nonempty mask."
        }
    }
}

public struct CapturedPlacementRecord: Decodable, Equatable, Sendable {
    public let id: Int
    public let spriteID: Int
    public let roomID: Int
    public let x: Int
    public let y: Int
}

/// Four observed actor records, not identified collectibles or game state.
public struct CapturedPlacementState: Decodable, Sendable {
    public let schemaVersion: Int
    public let snapshotSHA256: String
    public let sourceFrame: Int
    public let records: [CapturedPlacementRecord]

    public static func load(from data: Data, world: WorldReference) throws -> Self {
        guard data.count <= 32_000 else {
            throw CapturedPlacementError.unsupportedFormat
        }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.schemaVersion == 1, (1...1800).contains(result.sourceFrame) else {
            throw CapturedPlacementError.unsupportedFormat
        }
        guard result.snapshotSHA256 == WorldReference.supportedSnapshotSHA256,
              world.snapshotSha256 == result.snapshotSHA256,
              world.schemaVersion == 2 else {
            throw CapturedPlacementError.sourceMismatch
        }
        guard result.records.count == 4,
              Set(result.records.map(\.id)) == Set(0..<4),
              Set(result.records.map(\.roomID)).count == 4,
              Set(result.records.map(\.spriteID)).count == 4,
              result.records.allSatisfy({
                  (0..<256).contains($0.roomID)
                      && (0..<SpriteAtlas.spriteCount).contains($0.spriteID)
                      && (0..<256).contains($0.x) && (0..<192).contains($0.y)
                      && world.roomType(at: RoomID($0.roomID % 16, $0.roomID / 16)) != nil
              }) else {
            throw CapturedPlacementError.invalidRecord
        }
        return result
    }

    public func validate(spriteAtlas: SpriteAtlas) throws {
        for record in records {
            guard try spriteAtlas.mask(at: record.spriteID) != nil else {
                throw CapturedPlacementError.missingSprite
            }
        }
    }
}
