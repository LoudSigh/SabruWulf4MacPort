import CryptoKit
import Darwin
import Foundation

private enum ReplayError: Error, CustomStringConvertible {
    case usage
    case invalidROM
    case invalidSnapshot
    case unsupportedKey
    case stepBudget
    case unimplemented(pc: UInt16)
    case outputRedirection

    var description: String {
        switch self {
        case .usage:
            return "Usage: SnapshotReplay <48k.rom> <gameplay.z80> <none|q|a|o|p|space> [frames: 1...150] | --self-test"
        case .invalidROM:
            return "Expected exactly 16384 reference ROM bytes"
        case .invalidSnapshot:
            return "Expected a 48K snapshot containing 49152 RAM bytes"
        case .unsupportedKey:
            return "Supported inputs: none, q, a, o, p, space"
        case .stepBudget:
            return "Replay exceeded 100000 CPU steps in a frame"
        case let .unimplemented(pc):
            return String(format: "Unimplemented Z80 instruction at 0x%04X", pc)
        case .outputRedirection:
            return "Could not separate emulator diagnostics from JSON output"
        }
    }
}

private struct FrameReport: Encodable {
    let index: Int
    let screenSHA256: String
    let ramSHA256: String
    let executedRAMInstructions: Int
    let keyboardPortReads: Int
    let screenWriteEvents: Int
}

private struct ReplayReport: Encodable {
    let schemaVersion: Int
    let snapshotSHA256: String
    let romSHA256: String
    let input: String
    let pressedAtFrame: Int?
    let releasedAtFrame: Int?
    let frames: [FrameReport]
    let finalScreenSHA256: String
    let finalRAMSHA256: String
}

private func sha256(_ bytes: [UInt8]) -> String {
    SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
}

private func key(_ input: String) throws -> KeyboardMatrix.Key? {
    switch input {
    case "none": nil
    case "q": .q
    case "a": .a
    case "o": .o
    case "p": .p
    case "space": .space
    default: throw ReplayError.unsupportedKey
    }
}

@main
private struct SnapshotReplay {
    static func main() {
        do {
            if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
                guard try key("none") == nil, try key("q") != nil else {
                    throw ReplayError.unsupportedKey
                }
                do {
                    _ = try key("invalid")
                    throw ReplayError.unsupportedKey
                } catch ReplayError.unsupportedKey {}
                print("SnapshotReplay self-test passed")
                return
            }
            guard (4...5).contains(CommandLine.arguments.count) else {
                throw ReplayError.usage
            }
            let maxFrames: Int
            if CommandLine.arguments.count == 5 {
                guard let count = Int(CommandLine.arguments[4]), (1...150).contains(count)
                else { throw ReplayError.usage }
                maxFrames = count
            } else {
                maxFrames = 100
            }
            let input = CommandLine.arguments[3]
            let heldKey = try key(input)
            let rom = try [UInt8](Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            guard rom.count == 16384 else { throw ReplayError.invalidROM }
            let source = try [UInt8](
                Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
            )
            let snapshot = try Z80Snapshot.load(from: Data(source))
            guard snapshot.ram128Banks == nil, snapshot.ram48.count == 49152 else {
                throw ReplayError.invalidSnapshot
            }

            let savedOutput = dup(STDOUT_FILENO)
            guard savedOutput >= 0 else { throw ReplayError.outputRedirection }
            fflush(stdout)
            guard dup2(STDERR_FILENO, STDOUT_FILENO) >= 0 else {
                close(savedOutput)
                throw ReplayError.outputRedirection
            }
            let emulator = Speccy48Emulator(rom: rom)
            fflush(stdout)
            guard dup2(savedOutput, STDOUT_FILENO) >= 0 else {
                close(savedOutput)
                throw ReplayError.outputRedirection
            }
            close(savedOutput)
            emulator.apply(snapshot: snapshot)
            var cpu = emulator.cpu
            var memory = emulator.mem
            var cycles = 0
            var nextInterrupt = 69_888
            var frames: [FrameReport] = []
            for frame in 0..<maxFrames {
                if frame == 20, let heldKey { emulator.keyboard.press(heldKey) }
                if frame == 40, let heldKey { emulator.keyboard.release(heldKey) }
                let boundary = (frame + 1) * 69_888
                var steps = 0
                var ramSteps = 0
                var feReads = 0
                var screenWrites = 0
                while cycles < boundary {
                    if cpu.pc >= 0x4000 { ramSteps += 1 }
                    let result = cpu.step(
                        read: { memory.read($0) },
                        write: { addr, value in
                            memory.write(addr, value)
                            if (0x4000..<0x5B00).contains(Int(addr)) { screenWrites += 1 }
                        },
                        ioRead: { port in
                            if port & 1 == 0 {
                                feReads += 1
                                return emulator.keyboard.readPortFE(highByte: UInt8(port >> 8))
                            }
                            return 0xFF
                        },
                        ioWrite: { _, _ in }
                    )
                    steps += 1
                    if steps > 100_000 {
                        throw ReplayError.stepBudget
                    }
                    switch result {
                    case .ok(let cost):
                        cycles += cost
                    case .unimplemented:
                        throw ReplayError.unimplemented(pc: cpu.pc)
                    }
                    while cycles >= nextInterrupt {
                        cycles += cpu.acceptMaskableInterrupt(
                            read: { memory.read($0) },
                            write: { memory.write($0, $1) }
                        )
                        nextInterrupt += 69_888
                    }
                }
                let ram = memory.exportRam48K()
                frames.append(FrameReport(
                    index: frame + 1,
                    screenSHA256: sha256(Array(ram.prefix(6912))),
                    ramSHA256: sha256(ram),
                    executedRAMInstructions: ramSteps,
                    keyboardPortReads: feReads,
                    screenWriteEvents: screenWrites
                ))
            }
            guard let last = frames.last else { throw ReplayError.usage }
            let report = ReplayReport(
                schemaVersion: 1,
                snapshotSHA256: sha256(source),
                romSHA256: sha256(rom),
                input: input,
                pressedAtFrame: heldKey == nil ? nil : 20,
                releasedAtFrame: heldKey == nil ? nil : 40,
                frames: frames,
                finalScreenSHA256: last.screenSHA256,
                finalRAMSHA256: last.ramSHA256
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(report))
            FileHandle.standardOutput.write(Data([0x0A]))
        } catch {
            fputs("SnapshotReplay: \(error)\n", stderr)
            exit(1)
        }
    }
}
