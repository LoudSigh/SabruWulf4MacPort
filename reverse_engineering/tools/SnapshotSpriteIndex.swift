import CryptoKit
import Foundation

private enum SpriteIndexError: Error, CustomStringConvertible {
    case usage
    case invalidSnapshot
    case invalidTable

    var description: String {
        switch self {
        case .usage:
            return "Usage: SnapshotSpriteIndex <menu.z80> <gameplay.z80> | --self-test"
        case .invalidSnapshot:
            return "Expected two ZX Spectrum 48K snapshots"
        case .invalidTable:
            return "Expected 196 valid sprite pointers beginning at the documented table address"
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
        let width = Int(snapshot.ram48[offset])
        let height = Int(snapshot.ram48[offset + 1])
        let length = 2 + width * height
        let next = index + 1 < unique.count ? unique[index + 1] : 65536
        if width <= 8 && height <= 64 && length <= next - address {
            validHeaders += 1
            payloadBytes += length
            spriteRecordBytes.append(
                contentsOf: snapshot.ram48[offset..<(offset + length)]
            )
            largest = max(largest, length)
            if length == next - address { aligned += 1 }
        }
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
            guard CommandLine.arguments.count == 3 else { throw SpriteIndexError.usage }
            let menu = try inspect([UInt8](Data(
                contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
            )))
            let gameplay = try inspect([UInt8](Data(
                contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])
            )))
            let report = Report(
                menu: menu,
                gameplay: gameplay,
                tableIdenticalBetweenCaptures: menu.tableSha256 == gameplay.tableSha256
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(report))
            FileHandle.standardOutput.write(Data([0x0A]))
        } catch {
            fputs("SnapshotSpriteIndex: \(error)\n", stderr)
            exit(1)
        }
    }
}
