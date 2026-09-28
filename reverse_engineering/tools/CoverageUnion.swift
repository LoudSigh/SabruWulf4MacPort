import CryptoKit
import Foundation

private enum CoverageError: Error, CustomStringConvertible {
    case usage
    case invalidReport
    case overlapsData

    var description: String {
        switch self {
        case .usage:
            "Usage: CoverageUnion <byte-coverage.json> <private-sprite-atlas.json> <private-coverage-report.json>... | --self-test"
        case .invalidReport:
            "Expected checked reference-relative RAM frames and bounded, sorted PC addresses"
        case .overlapsData:
            "A verified executed PC start falls within known immutable game data"
        }
    }
}

private struct Interval: Decodable {
    let start: String
    let endExclusive: String
}

private struct ByteCoverage: Decodable {
    let knownDataIntervals: [Interval]
}

private struct SpriteRecord: Decodable {
    let address: Int
    let bitmap: Data
}

private struct SpritePayload: Decodable {
    let records: [SpriteRecord]
}

private struct TraceCoverage: Decodable {
    let distinctRAMInstructionStarts: Int
    let ramInstructionStartSHA256: String
    let ramStartsByPage: [String: Int]
    let ramInstructionStarts: [Int]
}

private struct TraceReport: Decodable {
    let schemaVersion: Int
    let snapshotSHA256: String
    let romSHA256: String
    let frameBoundaryMode: String
    let framesCompared: Int
    let matchingRAMFrames: Int
    let codeCoverage: TraceCoverage
}

private struct Summary: Encodable {
    let verifiedRAMFrames: Int
    let distinctExecutedRAMPCStartsInUnion: Int
    let minimumExecutedRAMPC: String
    let maximumExecutedRAMPC: String
    let unionLittleEndian16SHA256: String
    let executedPCStartsWithinKnownDataIntervals: Int
    let executedPCStartsWithinValidatedSpriteRecords: Int
}

private func bytesAndHash(_ addresses: [Int]) -> String {
    var bytes = Data()
    for address in addresses {
        bytes.append(UInt8(truncatingIfNeeded: address))
        bytes.append(UInt8(truncatingIfNeeded: address >> 8))
    }
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}

private func isSortedUnique(_ addresses: [Int]) -> Bool {
    addresses.allSatisfy { (0x4000...0xFFFF).contains($0) }
        && zip(addresses, addresses.dropFirst()).allSatisfy { $0.0 < $0.1 }
}

@main
private struct CoverageUnion {
    static func main() {
        do {
            let args = CommandLine.arguments
            if args.count == 2, args[1] == "--self-test" {
                let sample = [0x9000, 0x9011]
                guard isSortedUnique(sample), !isSortedUnique([0x9000, 0x9000]),
                      !isSortedUnique([0x3FFF]),
                      bytesAndHash(sample)
                        == "d904c468f2a49ad2c31c334586579f5fbd8779d09d3291eda1419cde5dbafb4d" else {
                    throw CoverageError.invalidReport
                }
                print("CoverageUnion self-test passed")
                return
            }
            guard (4...24).contains(args.count) else { throw CoverageError.usage }
            let dataMap = try Data(contentsOf: URL(fileURLWithPath: args[1]))
            let atlasData = try Data(contentsOf: URL(fileURLWithPath: args[2]))
            guard dataMap.count <= 1_000_000, atlasData.count <= 100_000 else {
                throw CoverageError.invalidReport
            }
            _ = try SpriteAtlas.load(from: atlasData)
            let intervals = try JSONDecoder().decode(
                ByteCoverage.self, from: dataMap
            ).knownDataIntervals.map { item -> Range<Int> in
                guard let start = Int(item.start.dropFirst(2), radix: 16),
                      let end = Int(item.endExclusive.dropFirst(2), radix: 16),
                      start < end else {
                    throw CoverageError.invalidReport
                }
                return start..<end
            }
            let records = try JSONDecoder().decode(
                SpritePayload.self, from: atlasData
            ).records.map { $0.address..<($0.address + $0.bitmap.count) }
            var union: Set<Int> = []
            var frames = 0
            for path in args.dropFirst(3) {
                let input = try Data(contentsOf: URL(fileURLWithPath: path))
                guard input.count <= 2_000_000 else { throw CoverageError.invalidReport }
                let trace = try JSONDecoder().decode(TraceReport.self, from: input)
                let addresses = trace.codeCoverage.ramInstructionStarts
                var byPage: [String: Int] = [:]
                for address in addresses {
                    byPage[String(format: "0x%02X", address >> 8), default: 0] += 1
                }
                guard trace.schemaVersion == 1,
                      trace.snapshotSHA256 == WorldReference.supportedSnapshotSHA256,
                      trace.romSHA256
                        == "d55daa439b673b0e3f5897f99ac37ecb45f974d1862b4dadb85dec34af99cb42",
                      trace.frameBoundaryMode == "reference-relative",
                      (1...900).contains(trace.framesCompared),
                      trace.framesCompared == trace.matchingRAMFrames,
                      addresses.count == trace.codeCoverage.distinctRAMInstructionStarts,
                      byPage == trace.codeCoverage.ramStartsByPage,
                      isSortedUnique(addresses),
                      bytesAndHash(addresses)
                        == trace.codeCoverage.ramInstructionStartSHA256 else {
                    throw CoverageError.invalidReport
                }
                frames += trace.matchingRAMFrames
                union.formUnion(addresses)
            }
            let sorted = union.sorted()
            guard let first = sorted.first, let last = sorted.last else {
                throw CoverageError.invalidReport
            }
            let intervalConflicts = sorted.filter { address in
                intervals.contains { $0.contains(address) }
            }.count
            let spriteConflicts = sorted.filter { address in
                records.contains { $0.contains(address) }
            }.count
            guard intervalConflicts == 0, spriteConflicts == 0 else {
                throw CoverageError.overlapsData
            }
            let result = Summary(
                verifiedRAMFrames: frames,
                distinctExecutedRAMPCStartsInUnion: sorted.count,
                minimumExecutedRAMPC: String(format: "0x%04X", first),
                maximumExecutedRAMPC: String(format: "0x%04X", last),
                unionLittleEndian16SHA256: bytesAndHash(sorted),
                executedPCStartsWithinKnownDataIntervals: intervalConflicts,
                executedPCStartsWithinValidatedSpriteRecords: spriteConflicts
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(result))
            FileHandle.standardOutput.write(Data([0x0A]))
        } catch {
            fputs("CoverageUnion: \(error)\n", stderr)
            exit(1)
        }
    }
}
