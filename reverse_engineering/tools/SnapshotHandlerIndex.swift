import CryptoKit
import Darwin
import Foundation

private enum HandlerIndexError: Error, CustomStringConvertible {
    case usage
    case unsupportedSnapshot
    case invalidTable
    case differingCaptures

    var description: String {
        switch self {
        case .usage:
            "Usage: SnapshotHandlerIndex <menu.z80> <gameplay.z80> | --self-test"
        case .unsupportedSnapshot:
            "Expected the two hashed, 48K Sabre Wulf snapshots"
        case .invalidTable:
            "The 196-entry actor handler table has invalid bounds or targets"
        case .differingCaptures:
            "Actor handler pointers differ between the supplied captures"
        }
    }
}

private struct HandlerIndex {
    static let address = 0x9B3E
    static let end = 0x9CC6
    static let count = 196

    let bytes: Data
    let targets: [UInt16]

    init(ram: [UInt8]) throws {
        let start = Self.address - 0x4000
        guard ram.count == 49_152, start >= 0,
              start + Self.count * 2 <= ram.count,
              Self.end - Self.address == Self.count * 2 else {
            throw HandlerIndexError.invalidTable
        }
        let records = Data(ram[start..<(start + Self.count * 2)])
        let parsed = (0..<Self.count).map { index in
            UInt16(records[index * 2]) | (UInt16(records[index * 2 + 1]) << 8)
        }
        guard parsed.allSatisfy({
            (Self.end..<0xBF84).contains(Int($0))
        }) else {
            throw HandlerIndexError.invalidTable
        }
        bytes = records
        targets = parsed
    }
}

private struct Report: Encodable {
    let schemaVersion = 1
    let menuSnapshotSHA256: String
    let gameplaySnapshotSHA256: String
    let start: String
    let endExclusive: String
    let pointerCount: Int
    let dataByteCount: Int
    let distinctTargets: Int
    let pointerBytesSHA256: String
    let targetsWithinRAMCodeCandidateBounds: Bool
    let identicalBetweenCaptures: Bool
    let lowPlayerKindGroupSharedTarget: Bool
    let highPlayerKindGroupSharedTarget: Bool
    let playerKindGroupsDistinct: Bool
    let enemyKindGroupSharedTarget: Bool
    let fourRecordKindGroupSharedTarget: Bool
    let twoGuardianKindGroupSharedTarget: Bool
}

private func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

@main
private struct SnapshotHandlerIndex {
    static func main() {
        do {
            if CommandLine.arguments.count == 2,
               CommandLine.arguments[1] == "--self-test" {
                var ram = [UInt8](repeating: 0, count: 49_152)
                let start = HandlerIndex.address - 0x4000
                for index in 0..<HandlerIndex.count {
                    let pointer = UInt16(HandlerIndex.end + (index % 25) * 2)
                    ram[start + index * 2] = UInt8(truncatingIfNeeded: pointer)
                    ram[start + index * 2 + 1] =
                        UInt8(truncatingIfNeeded: pointer >> 8)
                }
                let parsed = try HandlerIndex(ram: ram)
                guard parsed.targets.count == 196,
                      Set(parsed.targets).count == 25,
                      parsed.bytes.count == 392 else {
                    throw HandlerIndexError.invalidTable
                }
                ram[start] = 0
                ram[start + 1] = 0x40
                var rejected = false
                do {
                    _ = try HandlerIndex(ram: ram)
                } catch HandlerIndexError.invalidTable {
                    rejected = true
                }
                guard rejected else { throw HandlerIndexError.invalidTable }
                print("Synthetic handler-table bounds test passed")
                return
            }
            guard CommandLine.arguments.count == 3 else {
                throw HandlerIndexError.usage
            }
            let menu = try Data(contentsOf: URL(
                fileURLWithPath: CommandLine.arguments[1]
            ))
            let game = try Data(contentsOf: URL(
                fileURLWithPath: CommandLine.arguments[2]
            ))
            guard hash(menu)
                    == "34d98ec3dc55d60755a7d9ceebe45c3a7e345ce5961692d25d2d6718bcdc20ea",
                  hash(game) == WorldReference.supportedSnapshotSHA256,
                  let menuSnapshot = try? Z80Snapshot.load(from: menu),
                  let gameSnapshot = try? Z80Snapshot.load(from: game),
                  menuSnapshot.ram128Banks == nil,
                  gameSnapshot.ram128Banks == nil else {
                throw HandlerIndexError.unsupportedSnapshot
            }
            let first = try HandlerIndex(ram: menuSnapshot.ram48)
            let second = try HandlerIndex(ram: gameSnapshot.ram48)
            guard first.bytes == second.bytes else {
                throw HandlerIndexError.differingCaptures
            }
            let targets = second.targets
            guard targets.count == 196, Set(targets).count == 25,
                  Set(targets[16...31]).count == 1,
                  Set(targets[32...47]).count == 1,
                  targets[16] != targets[32],
                  Set(targets[108...111]).count == 1,
                  Set(targets[144...147]).count == 1,
                  Set(targets[148...149]).count == 1,
                  hash(second.bytes)
                    == "fbd27b08d673c9d780d377e650f990726d401738885f8cd4117d92b32f79a224" else {
                throw HandlerIndexError.invalidTable
            }
            let report = Report(
                menuSnapshotSHA256: hash(menu),
                gameplaySnapshotSHA256: hash(game),
                start: "0x9B3E", endExclusive: "0x9CC6",
                pointerCount: targets.count, dataByteCount: second.bytes.count,
                distinctTargets: Set(targets).count,
                pointerBytesSHA256: hash(second.bytes),
                targetsWithinRAMCodeCandidateBounds: true,
                identicalBetweenCaptures: true,
                lowPlayerKindGroupSharedTarget:
                    Set(targets[16...31]).count == 1,
                highPlayerKindGroupSharedTarget:
                    Set(targets[32...47]).count == 1,
                playerKindGroupsDistinct: targets[16] != targets[32],
                enemyKindGroupSharedTarget:
                    Set(targets[108...111]).count == 1,
                fourRecordKindGroupSharedTarget:
                    Set(targets[144...147]).count == 1,
                twoGuardianKindGroupSharedTarget:
                    Set(targets[148...149]).count == 1
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(report))
            FileHandle.standardOutput.write(Data([0x0A]))
        } catch {
            fputs("SnapshotHandlerIndex: \(error)\n", stderr)
            exit(1)
        }
    }
}
