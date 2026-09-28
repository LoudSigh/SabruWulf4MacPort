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
    case invalidSchedule

    var description: String {
        switch self {
        case .usage:
            return "Usage: SnapshotReplay <48k.rom> <gameplay.z80> <none|q|w|e|r|t|a|o|p|space> [frames: 1...150] [--hold] [--reference-timing] [--actor-kind] | <48k.rom> <gameplay.z80> --schedule <private.json> <frames: 1...800> [--reference-timing] [--actor-kind] | --self-test"
        case .invalidROM:
            return "Expected exactly 16384 reference ROM bytes"
        case .invalidSnapshot:
            return "Expected a 48K snapshot containing 49152 RAM bytes"
        case .unsupportedKey:
            return "Supported inputs: none, q, w, e, r, t, a, o, p, space"
        case .stepBudget:
            return "Replay exceeded 100000 CPU steps in a frame"
        case let .unimplemented(pc):
            return String(format: "Unimplemented Z80 instruction at 0x%04X", pc)
        case .outputRedirection:
            return "Could not separate emulator diagnostics from JSON output"
        case .invalidSchedule:
            return "Expected nonoverlapping zero-based key intervals within the requested frame count"
        }
    }
}

private struct ScheduledInput: Codable {
    let key: String
    let startFrame: Int
    let endFrame: Int
}

private func validatedSchedule(_ data: Data, frames: Int) throws -> [ScheduledInput] {
    guard data.count <= 64_000 else { throw ReplayError.invalidSchedule }
    let entries = try JSONDecoder().decode([ScheduledInput].self, from: data)
    guard !entries.isEmpty else { throw ReplayError.invalidSchedule }
    var previousEnd = 0
    for entry in entries {
        guard entry.startFrame >= previousEnd, entry.endFrame > entry.startFrame,
              entry.endFrame <= frames, try key(entry.key) != nil else {
            throw ReplayError.invalidSchedule
        }
        previousEnd = entry.endFrame
    }
    return entries
}

private struct FrameReport: Encodable {
    let index: Int
    let screenSHA256: String
    let ramSHA256: String
    let executedRAMInstructions: Int
    let keyboardPortReads: Int
    let screenWriteEvents: Int
    let savedActorX: Int
    let savedActorY: Int
    let savedRoom: Int
    let reportedLives: Int
    let playerRoomID: Int
    let playerX: Int
    let playerY: Int
    let playerKind: Int?
}

private struct ReplayReport: Encodable {
    let schemaVersion: Int
    let snapshotSHA256: String
    let romSHA256: String
    let frameBoundaryMode: String?
    let input: String
    let schedule: [ScheduledInput]?
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
    case "w": .w
    case "e": .e
    case "r": .r
    case "t": .t
    case "a": .a
    case "o": .o
    case "p": .p
    case "space": .space
    default: throw ReplayError.unsupportedKey
    }
}

private func frameBoundary(currentCycle: Int, frame: Int, referenceTiming: Bool) -> Int {
    referenceTiming ? currentCycle + 69_888 : (frame + 1) * 69_888
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
                let sample = Data("""
                    [{"key":"w","startFrame":20,"endFrame":46},
                     {"key":"e","startFrame":46,"endFrame":120}]
                    """.utf8)
                guard try validatedSchedule(sample, frames: 120).count == 2 else {
                    throw ReplayError.invalidSchedule
                }
                do {
                    _ = try validatedSchedule(sample, frames: 100)
                    throw ReplayError.invalidSchedule
                } catch ReplayError.invalidSchedule {}
                guard frameBoundary(currentCycle: 69_900, frame: 1, referenceTiming: true)
                        == 139_788,
                      frameBoundary(currentCycle: 69_900, frame: 1, referenceTiming: false)
                        == 139_776 else { throw ReplayError.usage }
                print("SnapshotReplay self-test passed")
                return
            }
            let arguments = CommandLine.arguments
            let isSchedule = arguments.count > 3 && arguments[3] == "--schedule"
            let maxFrames: Int
            let options: [String]
            if isSchedule {
                guard (6...8).contains(arguments.count) else { throw ReplayError.usage }
                guard let count = Int(arguments[5]), (1...800).contains(count)
                else { throw ReplayError.usage }
                maxFrames = count
                options = Array(arguments.dropFirst(6))
            } else {
                guard (4...8).contains(arguments.count) else { throw ReplayError.usage }
                let trailing = Array(arguments.dropFirst(4))
                if let first = trailing.first, let count = Int(first) {
                    guard (1...150).contains(count) else { throw ReplayError.usage }
                    maxFrames = count
                    options = Array(trailing.dropFirst())
                } else {
                    maxFrames = 100
                    options = trailing
                }
            }
            guard Set(options).count == options.count,
                  options.allSatisfy({
                      isSchedule ? ["--reference-timing", "--actor-kind"].contains($0)
                          : ["--hold", "--reference-timing", "--actor-kind"].contains($0)
                  }) else { throw ReplayError.usage }
            let referenceTiming = options.contains("--reference-timing")
            let includeActorKind = options.contains("--actor-kind")
            let input = isSchedule ? "schedule" : arguments[3]
            let heldKey = isSchedule ? nil : try key(input)
            let schedule = isSchedule
                ? try validatedSchedule(Data(contentsOf: URL(fileURLWithPath: arguments[4])), frames: maxFrames)
                : []
            let holdToEnd = options.contains("--hold")
            let rom = try [UInt8](Data(contentsOf: URL(fileURLWithPath: arguments[1])))
            guard rom.count == 16384 else { throw ReplayError.invalidROM }
            let source = try [UInt8](
                Data(contentsOf: URL(fileURLWithPath: arguments[2]))
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
            var previousKey: KeyboardMatrix.Key?
            for frame in 0..<maxFrames {
                let frameKey: KeyboardMatrix.Key?
                if isSchedule {
                    frameKey = try schedule.first(where: {
                        $0.startFrame <= frame && frame < $0.endFrame
                    }).flatMap { try key($0.key) }
                } else {
                    frameKey = frame >= 20 && (frame < 40 || holdToEnd) ? heldKey : nil
                }
                if previousKey != frameKey {
                    if let previousKey { emulator.keyboard.release(previousKey) }
                    if let frameKey { emulator.keyboard.press(frameKey) }
                    previousKey = frameKey
                }
                let boundary = frameBoundary(
                    currentCycle: cycles, frame: frame, referenceTiming: referenceTiming
                )
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
                let playerBase: UInt16 = 0x9702
                frames.append(FrameReport(
                    index: frame + 1,
                    screenSHA256: sha256(Array(ram.prefix(6912))),
                    ramSHA256: sha256(ram),
                    executedRAMInstructions: ramSteps,
                    keyboardPortReads: feReads,
                    screenWriteEvents: screenWrites,
                    savedActorX: Int(memory.read(38560)),
                    savedActorY: Int(memory.read(38561)),
                    savedRoom: Int(memory.read(38562)),
                    reportedLives: Int(memory.read(38589)),
                    playerRoomID: Int(memory.read(playerBase &+ 1)),
                    playerX: Int(memory.read(playerBase &+ 3)),
                    playerY: Int(memory.read(playerBase &+ 4)),
                    playerKind: includeActorKind ? Int(memory.read(playerBase)) : nil
                ))
            }
            guard let last = frames.last else { throw ReplayError.usage }
            let report = ReplayReport(
                schemaVersion: isSchedule ? 2 : 1,
                snapshotSHA256: sha256(source),
                romSHA256: sha256(rom),
                frameBoundaryMode: referenceTiming ? "reference-relative" : nil,
                input: input,
                schedule: isSchedule ? schedule : nil,
                pressedAtFrame: heldKey == nil ? nil : 20,
                releasedAtFrame: heldKey == nil || holdToEnd ? nil : 40,
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
