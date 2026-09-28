import CryptoKit
import Foundation

public enum BackgroundAtlasError: Error, LocalizedError {
    case unsupportedFormat
    case invalidRecord
    case integrityMismatch
    case mismatchedWorld
    case missingGraphic

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "Not a supported private 48K background atlas."
        case .invalidRecord: "The background atlas has an invalid or overlapping record."
        case .integrityMismatch: "The background records differ from the verified snapshots."
        case .mismatchedWorld: "The background atlas does not match the imported private world."
        case .missingGraphic: "The selected world placement has no background bitmap."
        }
    }
}

/// Decodes the 1-bit background bitmap; original drawing order and colors remain separate.
public struct BackgroundMask: Sendable {
    public let width: Int
    public let height: Int
    private let decodedPixels: [Bool]
    private let sourceAttributes: [UInt8]
    private let decodedPaletteIndices: [UInt8]

    public init(record: Data) throws {
        guard record.count >= 5 else { throw BackgroundAtlasError.invalidRecord }
        let height = Int(record[0])
        let bytesPerRow = Int(record[1])
        let bitmapLength = height * bytesPerRow
        let attributes = 2 + bitmapLength
        guard (1...192).contains(height), (1...32).contains(bytesPerRow),
              attributes + 1 < record.count,
              Int(record[attributes]) == (height + 7) / 8,
              Int(record[attributes + 1]) == bytesPerRow,
              record.count == attributes + 2
                + Int(record[attributes]) * bytesPerRow else {
            throw BackgroundAtlasError.invalidRecord
        }
        let pixelWidth = bytesPerRow * 8
        width = pixelWidth
        self.height = height
        let bitmap = Array(record[2..<attributes])
        let attributeBytes = Array(record[(attributes + 2)..<record.count])
        let pixels = (0..<(pixelWidth * height)).map { index in
            let byte = bitmap[(index / pixelWidth) * bytesPerRow + (index % pixelWidth) / 8]
            return byte & (1 << (7 - index % 8)) != 0
        }
        decodedPixels = pixels
        sourceAttributes = attributeBytes
        decodedPaletteIndices = pixels.indices.map { index in
            let attributeOffset = (index / pixelWidth / 8) * bytesPerRow
                + (index % pixelWidth) / 8
            return SpectrumAttribute(attributeBytes[attributeOffset])
                .paletteIndex(pixelOn: pixels[index])
        }
    }

    public func pixels() -> [Bool] {
        decodedPixels
    }

    public func paletteIndices(
        flashOn: Bool = false, invertBitmap: Bool = false
    ) -> [UInt8] {
        if !flashOn && !invertBitmap { return decodedPaletteIndices }
        let bytesPerRow = width / 8
        return decodedPixels.indices.map { index in
            let attributeOffset = (index / width / 8) * bytesPerRow
                + (index % width) / 8
            return SpectrumAttribute(sourceAttributes[attributeOffset])
                .paletteIndex(
                    pixelOn: decodedPixels[index] != invertBitmap,
                    flashOn: flashOn
                )
        }
    }
}

public struct BackgroundAtlas: Sendable {
    public static let graphicCount = 41

    private struct Record: Decodable {
        let address: Int
        let data: Data
    }

    private struct Payload: Decodable {
        let schemaVersion: Int
        let snapshotSHA256: String
        let records: [Record]
    }

    private let masks: [Int: BackgroundMask]

    public static func load(from data: Data) throws -> Self {
        try load(
            from: data,
            expectedHash: "2691664c054cf02c5dc03076f5cc6633857d98c0c800cb053787bd9dd5360f61",
            expectedBytes: 9_686
        )
    }

    static func load(from data: Data, expectedHash: String, expectedBytes: Int) throws -> Self {
        guard data.count <= 100_000 else { throw BackgroundAtlasError.unsupportedFormat }
        let atlas = try JSONDecoder().decode(Payload.self, from: data)
        guard atlas.schemaVersion == 1,
              atlas.snapshotSHA256 == WorldReference.supportedSnapshotSHA256,
              atlas.records.count == graphicCount else {
            throw BackgroundAtlasError.unsupportedFormat
        }
        let addresses = atlas.records.map(\.address)
        guard addresses.first == 28_860,
              addresses == Array(Set(addresses)).sorted(),
              addresses.allSatisfy({ (28_860...38_515).contains($0) }) else {
            throw BackgroundAtlasError.invalidRecord
        }
        var aggregate = Data()
        var masks: [Int: BackgroundMask] = [:]
        for (index, record) in atlas.records.enumerated() {
            let next = index + 1 < atlas.records.count
                ? atlas.records[index + 1].address : 0x9692
            guard (index + 1 == atlas.records.count
                ? record.address + record.data.count <= next
                : record.address + record.data.count == next) else {
                throw BackgroundAtlasError.invalidRecord
            }
            masks[record.address] = try BackgroundMask(record: record.data)
            aggregate.append(record.data)
        }
        let digest = SHA256.hash(data: aggregate)
            .map { String(format: "%02x", $0) }.joined()
        guard aggregate.count == expectedBytes, digest == expectedHash else {
            throw BackgroundAtlasError.integrityMismatch
        }
        return Self(masks: masks)
    }

    public func validate(world: WorldReference) throws {
        guard world.schemaVersion == 2,
              Set(world.rooms.flatMap(\.placements).map(\.graphicAddress))
                == Set(masks.keys),
              world.rooms.allSatisfy({ room in
                  room.placements.allSatisfy({ placement in
                      guard let mask = masks[placement.graphicAddress],
                            let width = placement.widthPixels,
                            let height = placement.heightPixels else { return false }
                      return mask.width == width && mask.height == height
                  })
              }) else {
            throw BackgroundAtlasError.mismatchedWorld
        }
    }

    public func mask(at address: Int) throws -> BackgroundMask {
        guard let mask = masks[address] else { throw BackgroundAtlasError.missingGraphic }
        return mask
    }
}
