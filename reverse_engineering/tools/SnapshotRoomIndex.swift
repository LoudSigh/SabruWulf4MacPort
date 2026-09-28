import CryptoKit
import Foundation

private enum RoomIndexError: Error, CustomStringConvertible {
    case usage
    case unsupportedSnapshot
    case invalidTable
    case invalidLayout(index: Int, value: UInt8)
    case unterminatedRoom(address: Int)
    case nonContiguousRooms(address: Int)
    case unsafeOutput
    case inconsistentCaptures
    case existingOutputMismatch

    var description: String {
        switch self {
        case .usage:
            return "Usage: SnapshotRoomIndex <menu.z80> <gameplay.z80> [--private-map] | --self-test"
        case .unsupportedSnapshot:
            return "Both inputs must be 48K snapshots with exactly 49152 RAM bytes"
        case .invalidTable:
            return "Room table does not match the expected 48-entry, little-endian index"
        case let .invalidLayout(index, value):
            return "Layout position \(index) references nonexistent room type \(value)"
        case let .unterminatedRoom(address):
            return "Room record at \(hex(address)) has no terminator before the next record"
        case let .nonContiguousRooms(address):
            return "Room record at \(hex(address)) does not end at the next record boundary"
        case .unsafeOutput:
            return "Run from the repository root with an ignored, non-symlink private directory"
        case .inconsistentCaptures:
            return "The two snapshots disagree on the world layout or room records"
        case .existingOutputMismatch:
            return "Private world map already exists with different content"
        }
    }
}

private struct InputSummary: Encodable {
    let snapshotSha256: String
    let layoutSha256: String
    let roomTableSha256: String
    let specialRoomSha256: String
    let roomRecordsSha256: String
    let uniqueRoomTypesUsed: Int
    let minimumRoomType: Int
    let maximumRoomType: Int
    let firstRoomPointer: String
    let secondRoomPointer: String
    let uniqueRoomRecords: Int
    let roomRecordsEndExclusive: String
    let totalBackgroundPlacements: Int
    let distinctBackgroundReferences: Int
    let minimumBackgroundReference: String
    let maximumBackgroundReference: String
    let minimumPlacementsPerRoom: Int
    let maximumPlacementsPerRoom: Int
    let menuBackgroundPlacements: Int
    let placementsOff8PixelGrid: Int
}

private struct Report: Encodable {
    let schemaVersion: Int
    let layoutAddress: String
    let layoutDimensions: [Int]
    let layoutBytes: Int
    let roomTableAddress: String
    let roomTablePointers: Int
    let specialMenuRoomAddress: String
    let menu: InputSummary
    let gameplay: InputSummary
    let layoutIdenticalBetweenCaptures: Bool
    let roomTableIdenticalBetweenCaptures: Bool
    let specialRoomIdenticalBetweenCaptures: Bool
    let roomRecordsIdenticalBetweenCaptures: Bool
}

private let layoutStart = 24678
private let layoutCount = 256
private let tableStart = 24934
private let pointerCount = 48

private func sha256(_ bytes: [UInt8]) -> String {
    SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
}

private func hex(_ value: Int) -> String {
    String(format: "0x%04X", value)
}

private func slice(_ ram: [UInt8], address: Int, length: Int) -> [UInt8] {
    let start = address - 0x4000
    return Array(ram[start..<(start + length)])
}

private func pointers(_ bytes: [UInt8]) throws -> [Int] {
    guard bytes.count == pointerCount * 2 else { throw RoomIndexError.invalidTable }
    let result = stride(from: 0, to: bytes.count, by: 2).map {
        Int(bytes[$0]) | (Int(bytes[$0 + 1]) << 8)
    }
    guard result[0] == 25088, result[1] == 25162,
          result.allSatisfy({ (25088..<65536).contains($0) })
    else {
        throw RoomIndexError.invalidTable
    }
    return result
}

private func validatedLayout(_ bytes: [UInt8]) throws -> Set<UInt8> {
    guard bytes.count == layoutCount else {
        throw RoomIndexError.invalidLayout(index: bytes.count, value: 0)
    }
    for (index, value) in bytes.enumerated() where Int(value) >= pointerCount {
        throw RoomIndexError.invalidLayout(index: index, value: value)
    }
    return Set(bytes)
}

private struct RecordSummary {
    let placements: Int
    let backgroundPointers: Set<Int>
    let offGrid: Int
    let endExclusive: Int
}

private func scanRoom(_ ram: [UInt8], address: Int, before next: Int) throws -> RecordSummary {
    var cursor = address
    var count = 0
    var backgrounds: Set<Int> = []
    var offGrid = 0
    while cursor + 1 < next {
        let index = cursor - 0x4000
        let graphic = Int(ram[index]) | (Int(ram[index + 1]) << 8)
        if graphic == 0 {
            return RecordSummary(
                placements: count, backgroundPointers: backgrounds, offGrid: offGrid,
                endExclusive: cursor + 2
            )
        }
        guard cursor + 3 < next else {
            throw RoomIndexError.unterminatedRoom(address: address)
        }
        let x = ram[index + 2]
        let y = ram[index + 3]
        if x % 8 != 0 || y % 8 != 0 { offGrid += 1 }
        backgrounds.insert(graphic)
        count += 1
        cursor += 4
    }
    throw RoomIndexError.unterminatedRoom(address: address)
}

private func summary(_ file: [UInt8], _ snapshot: Z80Snapshot) throws -> InputSummary {
    let layout = slice(snapshot.ram48, address: layoutStart, length: layoutCount)
    let table = slice(snapshot.ram48, address: tableStart, length: pointerCount * 2)
    let used = try validatedLayout(layout)
    let addresses = try pointers(table)
    let uniqueAddresses = Array(Set(addresses)).sorted()
    guard uniqueAddresses.count == pointerCount else { throw RoomIndexError.invalidTable }
    var totalPlacements = 0
    var backgrounds: Set<Int> = []
    var minimum = Int.max
    var maximum = 0
    var offGrid = 0
    for address in addresses {
        let next = uniqueAddresses.first(where: { $0 > address }) ?? 28860
        guard next > address && next <= 0x10000 else {
            throw RoomIndexError.invalidTable
        }
        let record = try scanRoom(snapshot.ram48, address: address, before: next)
        guard record.endExclusive == next else {
            throw RoomIndexError.nonContiguousRooms(address: address)
        }
        totalPlacements += record.placements
        backgrounds.formUnion(record.backgroundPointers)
        minimum = min(minimum, record.placements)
        maximum = max(maximum, record.placements)
        offGrid += record.offGrid
    }
    let menu = try scanRoom(snapshot.ram48, address: 25030, before: addresses[0])
    guard menu.endExclusive == addresses[0] else {
        throw RoomIndexError.nonContiguousRooms(address: 25030)
    }
    guard let firstBackground = backgrounds.min(),
          let lastBackground = backgrounds.max()
    else {
        throw RoomIndexError.invalidTable
    }
    return InputSummary(
        snapshotSha256: sha256(file),
        layoutSha256: sha256(layout),
        roomTableSha256: sha256(table),
        specialRoomSha256: sha256(
            slice(snapshot.ram48, address: 25030, length: 25088 - 25030)
        ),
        roomRecordsSha256: sha256(
            slice(snapshot.ram48, address: 25088, length: 28860 - 25088)
        ),
        uniqueRoomTypesUsed: used.count,
        minimumRoomType: Int(used.min()!),
        maximumRoomType: Int(used.max()!),
        firstRoomPointer: hex(addresses[0]),
        secondRoomPointer: hex(addresses[1]),
        uniqueRoomRecords: uniqueAddresses.count,
        roomRecordsEndExclusive: hex(28860),
        totalBackgroundPlacements: totalPlacements,
        distinctBackgroundReferences: backgrounds.count,
        minimumBackgroundReference: hex(firstBackground),
        maximumBackgroundReference: hex(lastBackground),
        minimumPlacementsPerRoom: minimum,
        maximumPlacementsPerRoom: maximum,
        menuBackgroundPlacements: menu.placements,
        placementsOff8PixelGrid: offGrid
    )
}

private func selfTest() throws {
    let bytes: [UInt8] = [0x00, 0x62, 0x4A, 0x62]
        + Array(repeating: [UInt8(0x00), 0x62], count: 46).flatMap { $0 }
    let parsed = try pointers(bytes)
    precondition(parsed.count == pointerCount)
    let layout = Array(repeating: UInt8(0), count: layoutCount)
    let used = try validatedLayout(layout)
    precondition(used == Set([UInt8(0)]))
    var invalid = layout
    invalid[42] = 48
    do {
        _ = try validatedLayout(invalid)
        preconditionFailure("An out-of-range room type must not be accepted")
    } catch RoomIndexError.invalidLayout(index: 42, value: 48) {
        // Invalid data has an actionable position.
    }
    var ram = [UInt8](repeating: 0, count: 49152)
    ram.replaceSubrange(0x2200..<0x2206, with: [0x00, 0x60, 16, 24, 0, 0])
    let room = try scanRoom(ram, address: 0x6200, before: 0x6206)
    precondition(room.placements == 1 && room.offGrid == 0)
    precondition(room.endExclusive == 0x6206)
    do {
        _ = try scanRoom(ram, address: 0x6200, before: 0x6204)
        preconditionFailure("An unterminated record must fail")
    } catch RoomIndexError.unterminatedRoom(address: 0x6200) {
        // The next room boundary is not an implicit terminator.
    }
    print("SnapshotRoomIndex self-test passed")
}

private func writePrivateMap(layout: [UInt8], snapshotSha: String) throws -> URL {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let tool = root.appendingPathComponent("reverse_engineering/tools/SnapshotRoomIndex.swift")
    let ignore = root.appendingPathComponent(".gitignore")
    guard FileManager.default.fileExists(atPath: tool.path),
          let rules = try? String(contentsOf: ignore, encoding: .utf8),
          rules.components(separatedBy: .newlines).contains("reverse_engineering/private/")
    else {
        throw RoomIndexError.unsafeOutput
    }
    let directory = root.appendingPathComponent(
        "reverse_engineering/private", isDirectory: true
    )
    if FileManager.default.fileExists(atPath: directory.path) {
        let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw RoomIndexError.unsafeOutput }
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let cells = layout.enumerated().map { index, id in
        let x = index % 16
        let y = index / 16
        let hue = (Int(id) * 37) % 360
        return "<div class=\"room\" style=\"background:hsl(\(hue),55%,28%)\" title=\"Column \(x), row \(y), type \(id)\" aria-label=\"Column \(x), row \(y), room type \(id)\">\(id)</div>"
    }.joined(separator: "\n")
    let html = """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <title>Private 16x16 room-type overview</title>
        <style>
        body { background:#101820; color:#fff; font:16px system-ui; margin:24px; }
        .grid { display:grid; grid-template-columns:repeat(16, minmax(28px, 1fr)); max-width:960px; gap:3px; }
        .room { text-align:center; padding:8px 0; border:1px solid #778899; font:14px ui-monospace,monospace; }
        </style>
        </head>
        <body>
        <h1>Private room-type overview</h1>
        <p>16x16 positions. Matching numbers and colors reuse a room template; this is a structural view, not the game's original art. Keep this file out of Git.</p>
        <div class="grid">\(cells)</div>
        </body>
        </html>
        """
    let url = directory.appendingPathComponent("snapshot-\(snapshotSha.prefix(12))-world.html")
    let bytes = Data(html.utf8)
    if FileManager.default.fileExists(atPath: url.path) {
        guard try Data(contentsOf: url) == bytes else {
            throw RoomIndexError.existingOutputMismatch
        }
    } else {
        try bytes.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: url.path
        )
    }
    return url
}

@main
private struct SnapshotRoomIndex {
    static func main() {
        do {
            if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
                try selfTest()
                return
            }
            guard CommandLine.arguments.count == 3
                  || (CommandLine.arguments.count == 4
                      && CommandLine.arguments[3] == "--private-map")
            else {
                throw RoomIndexError.usage
            }
            let first = try [UInt8](
                Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            )
            let second = try [UInt8](
                Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
            )
            let menu = try Z80Snapshot.load(from: Data(first))
            let gameplay = try Z80Snapshot.load(from: Data(second))
            guard menu.ram128Banks == nil, gameplay.ram128Banks == nil,
                  menu.ram48.count == 0xC000, gameplay.ram48.count == 0xC000
            else {
                throw RoomIndexError.unsupportedSnapshot
            }
            let menuSummary = try summary(first, menu)
            let gameplaySummary = try summary(second, gameplay)
            let report = Report(
                schemaVersion: 1,
                layoutAddress: hex(layoutStart),
                layoutDimensions: [16, 16],
                layoutBytes: layoutCount,
                roomTableAddress: hex(tableStart),
                roomTablePointers: pointerCount,
                specialMenuRoomAddress: hex(25030),
                menu: menuSummary,
                gameplay: gameplaySummary,
                layoutIdenticalBetweenCaptures: menuSummary.layoutSha256
                    == gameplaySummary.layoutSha256,
                roomTableIdenticalBetweenCaptures: menuSummary.roomTableSha256
                    == gameplaySummary.roomTableSha256,
                specialRoomIdenticalBetweenCaptures: menuSummary.specialRoomSha256
                    == gameplaySummary.specialRoomSha256,
                roomRecordsIdenticalBetweenCaptures: menuSummary.roomRecordsSha256
                    == gameplaySummary.roomRecordsSha256
            )
            var privateMap: URL?
            if CommandLine.arguments.count == 4 {
                guard report.layoutIdenticalBetweenCaptures,
                      report.roomTableIdenticalBetweenCaptures,
                      report.specialRoomIdenticalBetweenCaptures,
                      report.roomRecordsIdenticalBetweenCaptures
                else {
                    throw RoomIndexError.inconsistentCaptures
                }
                let layout = slice(gameplay.ram48, address: layoutStart, length: layoutCount)
                privateMap = try writePrivateMap(
                    layout: layout, snapshotSha: gameplaySummary.snapshotSha256
                )
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(report))
            FileHandle.standardOutput.write(Data([0x0A]))
            if let privateMap {
                fputs("Private local map: \(privateMap.path)\n", stderr)
            }
        } catch {
            fputs("SnapshotRoomIndex: \(error)\n", stderr)
            exit(1)
        }
    }
}
