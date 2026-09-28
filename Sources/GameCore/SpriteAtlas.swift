import CryptoKit
import Foundation

public enum SpriteAtlasError: Error, LocalizedError {
    case unsupportedFormat
    case invalidTable
    case invalidRecord
    case integrityMismatch
    case invalidID

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "Not a supported private 48K sprite atlas."
        case .invalidTable: "The sprite pointer table is incomplete or inconsistent."
        case .invalidRecord: "The atlas contains an invalid or overlapping sprite record."
        case .integrityMismatch: "The sprite atlas differs from the verified snapshot."
        case .invalidID: "The requested sprite ID is outside the source pointer table."
        }
    }
}

/// The private source bitmap shapes only; palette, compositing and animation are unverified.
public struct SpriteAtlas: Sendable {
    public static let spriteCount = 196
    public static let nonEmptyRecordCount = 152

    private struct Record: Decodable {
        let address: Int
        let bitmap: Data
    }

    private struct Payload: Decodable {
        let schemaVersion: Int
        let snapshotSHA256: String
        let pointers: [Int]
        let records: [Record]
    }

    private let pointers: [Int]
    private let masks: [Int: SpriteMask]

    public static func load(from data: Data) throws -> Self {
        try load(
            from: data,
            tableHash: "de3f2a50b66244a65039c0ae772b96baa4c2f8de54f3227027b15af316b7a538",
            recordHash: "5fd461c98ff54f2c67ca8c050fa32880f1660ae6badc3ece9006b5e0b4b2b890",
            expectedBytes: 8_006
        )
    }

    static func load(
        from data: Data, tableHash: String, recordHash: String, expectedBytes: Int
    ) throws -> Self {
        guard data.count <= 100_000 else { throw SpriteAtlasError.unsupportedFormat }
        let atlas = try JSONDecoder().decode(Payload.self, from: data)
        guard atlas.schemaVersion == 1,
              atlas.snapshotSHA256 == WorldReference.supportedSnapshotSHA256 else {
            throw SpriteAtlasError.unsupportedFormat
        }
        let addresses = atlas.records.map(\.address)
        guard atlas.pointers.count == spriteCount,
              atlas.records.count == nonEmptyRecordCount + 1,
              atlas.pointers.first == 49_420,
              addresses.first == 49_420,
              Set(atlas.pointers) == Set(addresses),
              addresses == Array(Set(addresses)).sorted(),
              addresses.allSatisfy({ (49_420...65_535).contains($0) }) else {
            throw SpriteAtlasError.invalidTable
        }
        var table = Data()
        for pointer in atlas.pointers {
            table.append(UInt8(truncatingIfNeeded: pointer))
            table.append(UInt8(truncatingIfNeeded: pointer >> 8))
        }
        var records = Data()
        var masks: [Int: SpriteMask] = [:]
        for (index, record) in atlas.records.enumerated() {
            let next = index + 1 < atlas.records.count
                ? atlas.records[index + 1].address : 65_536
            guard record.bitmap.count <= next - record.address else {
                throw SpriteAtlasError.invalidRecord
            }
            if index == 0 {
                guard record.bitmap == Data([0, 0]) else {
                    throw SpriteAtlasError.invalidRecord
                }
            } else {
                masks[record.address] = try SpriteMask(record: record.bitmap)
            }
            records.append(record.bitmap)
        }
        guard records.count == expectedBytes,
              Self.hash(table) == tableHash,
              Self.hash(records) == recordHash else {
            throw SpriteAtlasError.integrityMismatch
        }
        return Self(pointers: atlas.pointers, masks: masks)
    }

    public func mask(at id: Int) throws -> SpriteMask? {
        guard (0..<Self.spriteCount).contains(id) else { throw SpriteAtlasError.invalidID }
        return masks[pointers[id]]
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
