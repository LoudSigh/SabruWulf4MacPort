import CryptoKit
import Darwin
import Foundation

private struct AddressHit: Encodable {
    let address: String
    let count: Int
}

private struct CallHit: Encodable {
    let source: String
    let target: String
    let count: Int
}

private struct PageSummary: Encodable {
    let start: String
    let uniqueInstructionStarts: Int
    let uniqueWriteAddresses: Int
}

private struct SourceReadPage: Encodable {
    let start: String
    let uniqueAddresses: Int
}

private struct TraceReport: Encodable {
    let schemaVersion: Int
    let mode: String
    let snapshotSha256: String
    let romSha256: String
    let inputHeld: String?
    let initialPC: String
    let finalPC: String
    let finalRamSha256: String
    let finalScreenSha256: String
    let steps: Int
    let cycles: Int
    let stopReason: String
    let uniqueInstructionStartsInRAM: Int
    let uniqueCallEdges: Int
    let returns: Int
    let uniqueRAMWriteAddresses: Int
    let instructionStartsBelow0x6000: [String]
    let screenWrites: Int
    let otherRAMWrites: Int
    let pages: [PageSummary]
    let mostFrequentInstructionStarts: [AddressHit]
    let mostFrequentCallEdges: [CallHit]
    let mostFrequentRAMWrites: [AddressHit]
    let mostFrequentScreenWriterPCs: [AddressHit]
    let candidateRendererSourceReadPages: [SourceReadPage]
}

private enum TraceError: Error, CustomStringConvertible {
    case usage
    case invalidROM
    case unsupportedSnapshot
    case invalidStepBudget
    case outputRedirection

    var description: String {
        switch self {
        case .usage:
            return "Usage: SnapshotTrace <48k.rom> <snapshot.z80> [steps: 1...1000000] [--key q|a|o|p|space] | --self-test"
        case .invalidROM:
            return "Reference ROM must contain exactly 16384 bytes"
        case .unsupportedSnapshot:
            return "Expected a 48K snapshot with exactly 49152 RAM bytes"
        case .invalidStepBudget:
            return "Step budget must be an integer between 1 and 1000000"
        case .outputRedirection:
            return "Unable to redirect emulator initialization diagnostics away from JSON output"
        }
    }
}

private func sha256(_ bytes: [UInt8]) -> String {
    SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
}

private func hex(_ value: UInt16) -> String {
    String(format: "0x%04X", value)
}

private struct CallEdge: Hashable {
    let source: UInt16
    let target: UInt16
}

private struct Metrics {
    var instructionStarts: [UInt16: Int] = [:]
    var ramWrites: [UInt16: Int] = [:]
    var screenWriterPCs: [UInt16: Int] = [:]
    var candidateRendererSourceReads: [UInt16: Int] = [:]
    var calls: [CallEdge: Int] = [:]
    var returns = 0
    var screenWrites = 0
    var otherRAMWrites = 0

    mutating func recordPC(_ pc: UInt16) {
        if pc >= 0x4000 { instructionStarts[pc, default: 0] += 1 }
    }

    mutating func recordWrite(_ address: UInt16, from pc: UInt16) {
        guard address >= 0x4000 else { return }
        ramWrites[address, default: 0] += 1
        if address < 0x5B00 {
            screenWrites += 1
            screenWriterPCs[pc, default: 0] += 1
        } else {
            otherRAMWrites += 1
        }
    }

    mutating func recordCall(from source: UInt16, to target: UInt16) {
        calls[CallEdge(source: source, target: target), default: 0] += 1
    }

    mutating func recordRead(_ address: UInt16, from pc: UInt16) {
        guard (0xBA00..<0xBC00).contains(Int(pc)),
              address >= 0x5B00,
              !(0xBA00..<0xBC00).contains(Int(address))
        else {
            return
        }
        candidateRendererSourceReads[address, default: 0] += 1
    }

    func topInstructions(_ limit: Int = 40) -> [AddressHit] {
        instructionStarts.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }.prefix(limit).map { AddressHit(address: hex($0.key), count: $0.value) }
    }

    func topCalls(_ limit: Int = 40) -> [CallHit] {
        calls.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            if $0.key.source != $1.key.source { return $0.key.source < $1.key.source }
            return $0.key.target < $1.key.target
        }.prefix(limit).map {
            CallHit(source: hex($0.key.source), target: hex($0.key.target), count: $0.value)
        }
    }

    func topWrites(_ limit: Int = 40) -> [AddressHit] {
        ramWrites.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }.prefix(limit).map { AddressHit(address: hex($0.key), count: $0.value) }
    }

    func topScreenWriterPCs(_ limit: Int = 40) -> [AddressHit] {
        screenWriterPCs.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }.prefix(limit).map { AddressHit(address: hex($0.key), count: $0.value) }
    }

    func pages() -> [PageSummary] {
        stride(from: 0x4000, to: 0x10000, by: 0x1000).map { start in
            let end = start + 0x1000
            return PageSummary(
                start: hex(UInt16(start)),
                uniqueInstructionStarts: instructionStarts.keys.reduce(0) {
                    $0 + (Int($1) >= start && Int($1) < end ? 1 : 0)
                },
                uniqueWriteAddresses: ramWrites.keys.reduce(0) {
                    $0 + (Int($1) >= start && Int($1) < end ? 1 : 0)
                }
            )
        }
    }

    func rendererSourcePages() -> [SourceReadPage] {
        stride(from: 0x4000, to: 0x10000, by: 0x1000).compactMap { start in
            let end = start + 0x1000
            let count = candidateRendererSourceReads.keys.reduce(0) {
                $0 + (Int($1) >= start && Int($1) < end ? 1 : 0)
            }
            if count == 0 { return nil }
            return SourceReadPage(start: hex(UInt16(start)), uniqueAddresses: count)
        }
    }
}

private func selfTest() {
    var metrics = Metrics()
    metrics.recordPC(0x0038)
    metrics.recordPC(0xB8A1)
    metrics.recordPC(0xB8A1)
    metrics.recordWrite(0x4000, from: 0xBA18)
    metrics.recordWrite(0x6000, from: 0xB000)
    metrics.recordWrite(0x2000, from: 0xB000)
    metrics.recordCall(from: 0xB8A1, to: 0x9000)
    metrics.recordRead(0x7000, from: 0xBA18)
    metrics.recordRead(0xBA19, from: 0xBA18)
    precondition(metrics.instructionStarts.count == 1)
    precondition(metrics.topInstructions()[0].count == 2)
    precondition(metrics.screenWrites == 1 && metrics.otherRAMWrites == 1)
    precondition(metrics.ramWrites.count == 2)
    precondition(metrics.topScreenWriterPCs()[0].address == "0xBA18")
    precondition(metrics.calls.count == 1)
    precondition(metrics.candidateRendererSourceReads.count == 1)
    precondition(metrics.pages().reduce(0) { $0 + $1.uniqueInstructionStarts } == 1)
    print("SnapshotTrace self-test passed")
}

@main
private struct SnapshotTrace {
    static func main() {
        do {
            if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
                selfTest()
                return
            }
            guard CommandLine.arguments.count == 3 || CommandLine.arguments.count == 4
                  || (CommandLine.arguments.count == 6 && CommandLine.arguments[4] == "--key")
            else {
                throw TraceError.usage
            }
            let budget: Int
            if CommandLine.arguments.count >= 4 {
                guard let value = Int(CommandLine.arguments[3]), (1...1_000_000).contains(value)
                else {
                    throw TraceError.invalidStepBudget
                }
                budget = value
            } else {
                budget = 20_000
            }
            let inputHeld: String? = CommandLine.arguments.count == 6
                ? CommandLine.arguments[5] : nil
            let key: KeyboardMatrix.Key?
            switch inputHeld {
            case nil: key = nil
            case "q": key = .q
            case "a": key = .a
            case "o": key = .o
            case "p": key = .p
            case "space": key = .space
            default: throw TraceError.usage
            }

            let rom = try [UInt8](Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            guard rom.count == 0x4000 else { throw TraceError.invalidROM }
            let input = try [UInt8](
                Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
            )
            let snapshot = try Z80Snapshot.load(from: Data(input))
            guard snapshot.ram128Banks == nil, snapshot.ram48.count == 0xC000 else {
                throw TraceError.unsupportedSnapshot
            }

            let savedOutput = dup(STDOUT_FILENO)
            guard savedOutput >= 0 else { throw TraceError.outputRedirection }
            fflush(stdout)
            guard dup2(STDERR_FILENO, STDOUT_FILENO) >= 0 else {
                close(savedOutput)
                throw TraceError.outputRedirection
            }
            let emulator = Speccy48Emulator(rom: rom)
            fflush(stdout)
            guard dup2(savedOutput, STDOUT_FILENO) >= 0 else {
                close(savedOutput)
                throw TraceError.outputRedirection
            }
            close(savedOutput)
            emulator.tapeLoadTrapEnabled = false
            emulator.apply(snapshot: snapshot)
            if let key { emulator.keyboard.press(key) }
            var cpu = emulator.cpu
            var memory = emulator.mem
            var metrics = Metrics()
            var stepCount = 0
            var cycleCount = 0
            var stopReason = "budget_exhausted"

            while stepCount < budget {
                if cpu.pc < 0x4000 {
                    stopReason = "entered_rom"
                    break
                }
                if cpu.halted {
                    stopReason = "halted"
                    break
                }
                let pc = cpu.pc
                metrics.recordPC(pc)
                let result = cpu.step(
                    read: { address in
                        metrics.recordRead(address, from: pc)
                        return memory.read(address)
                    },
                    write: { address, value in
                        memory.write(address, value)
                        metrics.recordWrite(address, from: pc)
                    },
                    ioRead: { emulator.ioRead($0) },
                    ioWrite: { emulator.ioWrite($0, $1) },
                    onCall: { target in metrics.recordCall(from: pc, to: target) },
                    onReturn: { metrics.returns += 1 }
                )
                stepCount += 1
                switch result {
                case .ok(let cycles):
                    cycleCount += cycles
                case .unimplemented:
                    stopReason = "unimplemented_instruction"
                }
                if stopReason == "unimplemented_instruction" { break }
            }
            let report = TraceReport(
                schemaVersion: 1,
                mode: "isolated_cpu_without_frame_interrupts_or_precise_io_timing",
                snapshotSha256: sha256(input),
                romSha256: sha256(rom),
                inputHeld: inputHeld,
                initialPC: hex(snapshot.cpu.pc),
                finalPC: hex(cpu.pc),
                finalRamSha256: sha256(memory.exportRam48K()),
                finalScreenSha256: sha256(Array(memory.exportRam48K().prefix(6912))),
                steps: stepCount,
                cycles: cycleCount,
                stopReason: stopReason,
                uniqueInstructionStartsInRAM: metrics.instructionStarts.count,
                uniqueCallEdges: metrics.calls.count,
                returns: metrics.returns,
                uniqueRAMWriteAddresses: metrics.ramWrites.count,
                instructionStartsBelow0x6000: metrics.instructionStarts.keys
                    .filter { $0 < 0x6000 }.sorted().map(hex),
                screenWrites: metrics.screenWrites,
                otherRAMWrites: metrics.otherRAMWrites,
                pages: metrics.pages(),
                mostFrequentInstructionStarts: metrics.topInstructions(),
                mostFrequentCallEdges: metrics.topCalls(),
                mostFrequentRAMWrites: metrics.topWrites(),
                mostFrequentScreenWriterPCs: metrics.topScreenWriterPCs(),
                candidateRendererSourceReadPages: metrics.rendererSourcePages()
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(report))
            FileHandle.standardOutput.write(Data([0x0A]))
        } catch {
            fputs("SnapshotTrace: \(error)\n", stderr)
            exit(1)
        }
    }
}
