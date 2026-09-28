import CryptoKit
import Foundation

private enum SpriteIndexError: Error, CustomStringConvertible {
    case usage
    case invalidSnapshot
    case invalidTable
    case inconsistentCaptures
    case unsafeOutput
    case existingOutputMismatch

    var description: String {
        switch self {
        case .usage:
            return "Usage: SnapshotSpriteIndex <menu.z80> <gameplay.z80> [--private-atlas] | --self-test"
        case .invalidSnapshot:
            return "Expected two ZX Spectrum 48K snapshots"
        case .invalidTable:
            return "Expected 196 valid sprite pointers beginning at the documented table address"
        case .inconsistentCaptures:
            return "The two snapshots have different sprite records or pointers"
        case .unsafeOutput:
            return "Run from the repository root with an ignored, non-symlink private directory"
        case .existingOutputMismatch:
            return "The existing private sprite atlas has different content"
        }
    }
}

private struct Summary: Encodable {
    let snapshotSha256: String
    let tableSha256: String
    let uniquePointers: Int
    let firstPointer: String
    let lastPointer: String
    let minimumPointer: String
    let maximumPointer: String
    let validSpriteHeaders: Int
    let recordsEndingAtNextPointer: Int
    let payloadBytesAccountedFor: Int
    let spriteRecordSHA256: String
    let largestRecordBytes: Int
}

private struct Report: Encodable {
    let schemaVersion = 1
    let tableStart = "0xBF84"
    let tableEndExclusive = "0xC10C"
    let pointerCount = 196
    let menu: Summary
    let gameplay: Summary
    let tableIdenticalBetweenCaptures: Bool
}

private struct AtlasRecord: Encodable {
    let address: Int
    let bitmap: Data
}

private struct PrivateAtlas: Encodable {
    let schemaVersion = 1
    let snapshotSHA256: String
    let pointers: [Int]
    let records: [AtlasRecord]
}

private func sha256(_ bytes: [UInt8]) -> String {
    SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
}

private func hex(_ address: Int) -> String {
    String(format: "0x%04X", address)
}

private func decode(_ bytes: [UInt8]) throws -> [Int] {
    guard bytes.count == 392 else { throw SpriteIndexError.invalidTable }
    let pointers = stride(from: 0, to: bytes.count, by: 2).map {
        Int(bytes[$0]) | (Int(bytes[$0 + 1]) << 8)
    }
    guard pointers.first == 49420,
          pointers[1] == 55330,
          pointers[16] == 50452,
          pointers.allSatisfy({ (49420..<65536).contains($0) })
    else {
        throw SpriteIndexError.invalidTable
    }
    return pointers
}

private func inspect(_ file: [UInt8]) throws -> Summary {
    let snapshot = try Z80Snapshot.load(from: Data(file))
    guard snapshot.ram128Banks == nil, snapshot.ram48.count == 49152 else {
        throw SpriteIndexError.invalidSnapshot
    }
    let start = 49028 - 0x4000
    let bytes = Array(snapshot.ram48[start..<(start + 392)])
    let pointers = try decode(bytes)
    let unique = Array(Set(pointers)).sorted()
    var validHeaders = 0
    var aligned = 0
    var payloadBytes = 0
    var spriteRecordBytes: [UInt8] = []
    var largest = 0
    for (index, address) in unique.enumerated() {
        let offset = address - 0x4000
        guard offset + 1 < snapshot.ram48.count else {
            throw SpriteIndexError.invalidTable
        }
        let width = Int(snapshot.ram48[offset])
        let height = Int(snapshot.ram48[offset + 1])
        let length = 2 + width * height
        let next = index + 1 < unique.count ? unique[index + 1] : 65536
        let validBitmap = (1...8).contains(width) && (1...64).contains(height)
        let emptySentinel = address == 49420 && width == 0 && height == 0
        guard validBitmap || emptySentinel,
              length <= next - address,
              length <= snapshot.ram48.count - offset else {
            throw SpriteIndexError.invalidTable
        }
        validHeaders += 1
        payloadBytes += length
        spriteRecordBytes.append(contentsOf: snapshot.ram48[offset..<(offset + length)])
        largest = max(largest, length)
        if length == next - address { aligned += 1 }
    }
    return Summary(
        snapshotSha256: sha256(file),
        tableSha256: sha256(bytes),
        uniquePointers: Set(pointers).count,
        firstPointer: hex(pointers[0]),
        lastPointer: hex(pointers[195]),
        minimumPointer: hex(pointers.min()!),
        maximumPointer: hex(pointers.max()!),
        validSpriteHeaders: validHeaders,
        recordsEndingAtNextPointer: aligned,
        payloadBytesAccountedFor: payloadBytes,
        spriteRecordSHA256: sha256(spriteRecordBytes),
        largestRecordBytes: largest
    )
}

private func writePrivateAtlas(
    menu: Summary, gameplay: Summary, gameplayFile: [UInt8]
) throws -> URL {
    guard menu.tableSha256 == gameplay.tableSha256,
          menu.spriteRecordSHA256 == gameplay.spriteRecordSHA256,
          menu.uniquePointers == 153,
          menu.validSpriteHeaders == 153 else {
        throw SpriteIndexError.inconsistentCaptures
    }
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let tool = root.appendingPathComponent("reverse_engineering/tools/SnapshotSpriteIndex.swift")
    let ignore = root.appendingPathComponent(".gitignore")
    guard FileManager.default.fileExists(atPath: tool.path),
          let rules = try? String(contentsOf: ignore, encoding: .utf8),
          rules.components(separatedBy: .newlines).contains("reverse_engineering/private/")
    else { throw SpriteIndexError.unsafeOutput }
    let directory = root.appendingPathComponent("reverse_engineering/private", isDirectory: true)
    if FileManager.default.fileExists(atPath: directory.path) {
        let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw SpriteIndexError.unsafeOutput }
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let snapshot = try Z80Snapshot.load(from: Data(gameplayFile))
    let tableStart = 49028 - 0x4000
    let pointers = try decode(Array(snapshot.ram48[tableStart..<(tableStart + 392)]))
    let unique = Array(Set(pointers)).sorted()
    let records = try unique.enumerated().map { index, address in
        let offset = address - 0x4000
        guard offset + 1 < snapshot.ram48.count else {
            throw SpriteIndexError.invalidTable
        }
        let width = Int(snapshot.ram48[offset])
        let height = Int(snapshot.ram48[offset + 1])
        let length = 2 + width * height
        let next = index + 1 < unique.count ? unique[index + 1] : 65_536
        let validBitmap = (1...8).contains(width) && (1...64).contains(height)
        let emptySentinel = address == 49420 && width == 0 && height == 0
        guard validBitmap || emptySentinel,
              length <= next - address,
              length <= snapshot.ram48.count - offset else {
            throw SpriteIndexError.invalidTable
        }
        return AtlasRecord(
            address: address, bitmap: Data(snapshot.ram48[offset..<(offset + length)])
        )
    }
    let atlas = PrivateAtlas(
        snapshotSHA256: gameplay.snapshotSha256, pointers: pointers, records: records
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let content = try encoder.encode(atlas)
    let url = directory.appendingPathComponent(
        "snapshot-\(gameplay.snapshotSha256.prefix(12))-sprite-atlas-v1.json"
    )
    if FileManager.default.fileExists(atPath: url.path) {
        guard try Data(contentsOf: url) == content else {
            throw SpriteIndexError.existingOutputMismatch
        }
    } else {
        try content.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    return url
}

@main
private struct SnapshotSpriteIndex {
    static func main() {
        do {
            if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
                let entry: [UInt8] = [0x0C, 0xC1]
                var bytes = Array(repeating: entry, count: 196)
                    .flatMap { $0 }
                bytes[0] = 0x0C; bytes[1] = 0xC1
                bytes[2] = 0x22; bytes[3] = 0xD8
                bytes[32] = 0x14; bytes[33] = 0xC5
                guard try decode(bytes).count == 196 else {
                    throw SpriteIndexError.invalidTable
                }
                bytes[0] = 0
                do {
                    _ = try decode(bytes)
                    throw SpriteIndexError.invalidTable
                } catch SpriteIndexError.invalidTable {}
                print("SnapshotSpriteIndex self-test passed")
                return
            }
            guard (3...4).contains(CommandLine.arguments.count),
                  CommandLine.arguments.count == 3
                    || CommandLine.arguments[3] == "--private-atlas" else {
                throw SpriteIndexError.usage
            }
            let menuFile = try [UInt8](Data(
                contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
            ))
            let gameplayFile = try [UInt8](Data(
                contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])
            ))
            let menu = try inspect(menuFile)
            let gameplay = try inspect(gameplayFile)
            let report = Report(
                menu: menu,
                gameplay: gameplay,
                tableIdenticalBetweenCaptures: menu.tableSha256 == gameplay.tableSha256
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(report))
            FileHandle.standardOutput.write(Data([0x0A]))
            if CommandLine.arguments.count == 4 {
                let url = try writePrivateAtlas(
                    menu: menu, gameplay: gameplay, gameplayFile: gameplayFile
                )
                fputs("Private sprite atlas: \(url.path)\n", stderr)
            }
        } catch {
            fputs("SnapshotSpriteIndex: \(error)\n", stderr)
            exit(1)
        }
    }
}
