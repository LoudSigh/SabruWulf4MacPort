import CryptoKit
import Foundation

private struct SnapshotSummary: Encodable {
    let sha256: String
    let ramSha256: String
    let screenSha256: String
    let pc: String
    let sp: String
    let nonzeroBitmapBytes: Int
    let distinctAttributeBytes: Int
}

private struct RegionCount: Encodable {
    let start: String
    let endExclusive: String
    let changed: Int
}

private struct Comparison: Encodable {
    let schemaVersion: Int
    let romSha256: String
    let first: SnapshotSummary
    let second: SnapshotSummary
    let changedRamBytes: Int
    let regions: [RegionCount]
    let pages: [RegionCount]
}

private enum ComparisonError: Error, CustomStringConvertible {
    case incorrectUsage
    case invalidROM
    case unsupportedSnapshot

    var description: String {
        switch self {
        case .incorrectUsage:
            return "Usage: SnapshotCompare <48k.rom> <first.z80> <second.z80> | --self-test"
        case .invalidROM:
            return "Reference ROM must contain exactly 16384 bytes"
        case .unsupportedSnapshot:
            return "Both snapshots must contain flat 49152-byte 48K RAM images"
        }
    }
}

private func sha256(_ bytes: [UInt8]) -> String {
    SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
}

private func hex(_ value: UInt16) -> String {
    String(format: "0x%04X", value)
}

private func differences(
    _ first: [UInt8], _ second: [UInt8], from start: Int, to end: Int
) -> Int {
    zip(first[start..<end], second[start..<end])
        .reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) }
}

private func summary(_ input: [UInt8], _ snapshot: Z80Snapshot) -> SnapshotSummary {
    let ram = snapshot.ram48
    return SnapshotSummary(
        sha256: sha256(input),
        ramSha256: sha256(ram),
        screenSha256: sha256(Array(ram[0..<0x1B00])),
        pc: hex(snapshot.cpu.pc),
        sp: hex(snapshot.cpu.sp),
        nonzeroBitmapBytes: ram[0..<0x1800].reduce(0) { $0 + ($1 == 0 ? 0 : 1) },
        distinctAttributeBytes: Set(ram[0x1800..<0x1B00]).count
    )
}

private func selfTest() {
    let first = [UInt8](repeating: 0, count: 8192)
    var second = first
    second[0] = 1
    second[4096] = 1
    second[8191] = 1
    precondition(differences(first, second, from: 0, to: 4096) == 1)
    precondition(differences(first, second, from: 4096, to: 8192) == 2)
    precondition(differences(first, second, from: 0, to: 8192) == 3)
    print("SnapshotCompare self-test passed")
}

@main
private struct SnapshotCompare {
    static func main() {
        do {
            if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
                selfTest()
                return
            }
            guard CommandLine.arguments.count == 4 else {
                throw ComparisonError.incorrectUsage
            }
            let rom = try [UInt8](Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            guard rom.count == 0x4000 else { throw ComparisonError.invalidROM }
            let firstInput = try [UInt8](
                Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
            )
            let secondInput = try [UInt8](
                Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
            )
            let first = try Z80Snapshot.load(from: Data(firstInput))
            let second = try Z80Snapshot.load(from: Data(secondInput))
            guard first.ram128Banks == nil, second.ram128Banks == nil,
                  first.ram48.count == 0xC000, second.ram48.count == 0xC000
            else {
                throw ComparisonError.unsupportedSnapshot
            }

            let segments = [
                (0x0000, 0x1800),
                (0x1800, 0x1B00),
                (0x1B00, 0x2000),
                (0x2000, 0xC000),
            ]
            let result = Comparison(
                schemaVersion: 1,
                romSha256: sha256(rom),
                first: summary(firstInput, first),
                second: summary(secondInput, second),
                changedRamBytes: differences(first.ram48, second.ram48, from: 0, to: 0xC000),
                regions: segments.map { (start, end) in
                    RegionCount(
                        start: hex(UInt16(start + 0x4000)),
                        endExclusive: end == 0xC000 ? "0x10000" : hex(UInt16(end + 0x4000)),
                        changed: differences(first.ram48, second.ram48, from: start, to: end)
                    )
                },
                pages: stride(from: 0, to: 0xC000, by: 0x1000).map { start in
                    RegionCount(
                        start: hex(UInt16(start + 0x4000)),
                        endExclusive: start == 0xB000
                            ? "0x10000" : hex(UInt16(start + 0x5000)),
                        changed: differences(
                            first.ram48, second.ram48, from: start, to: start + 0x1000
                        )
                    )
                }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(result))
            FileHandle.standardOutput.write(Data([0x0A]))
        } catch {
            fputs("SnapshotCompare: \(error)\n", stderr)
            exit(1)
        }
    }
}
