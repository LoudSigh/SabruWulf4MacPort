import CryptoKit
import Darwin
import Foundation

private enum ProbeError: Error, CustomStringConvertible {
    case usage
    case unsupportedInput
    case stepBudget(frame: Int)
    case unimplemented(frame: Int, pc: UInt16)

    var description: String {
        switch self {
        case .usage:
            "Usage: RNGIntervention <48k.rom> <gameplay.z80> <schedule.json> <frames: 1...600> <fixed-byte: 0...255> <start-frame: 0...frames-1>"
        case .unsupportedInput:
            "Expected the verified 48K ROM and snapshot, and sorted bounded keyboard intervals"
        case .stepBudget(let frame):
            "Reference CPU exceeded 100000 steps in frame \(frame)"
        case .unimplemented(let frame, let pc):
            String(format: "Unsupported reference opcode at 0x%04X in frame %d", pc, frame)
        }
    }
}

private struct Segment: Decodable {
    let key: String
    let startFrame: Int
    let endFrame: Int
}

private struct Frame: Encodable {
    let index: Int
    let playerKind: Int
    let playerX: Int
    let playerY: Int
    let enemyKind: Int
    let enemyX: Int
    let enemyY: Int
    let rng: Int
}

private struct Report: Encodable {
    let mode = "experimental-rng-intervention-not-reference-parity"
    let fixedRNGByte: Int
    let interventionStartFrame: Int
    let frames: [Frame]
}

private func key(_ name: String) throws -> KeyboardMatrix.Key {
    switch name {
    case "q": .q
    case "w": .w
    case "e": .e
    case "r": .r
    case "t": .t
    case "a": .a
    case "o": .o
    case "p": .p
    case "space": .space
    default: throw ProbeError.unsupportedInput
    }
}

private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

@main
private struct RNGIntervention {
    static func main() {
        do {
            let args = CommandLine.arguments
            guard args.count == 7,
                  let count = Int(args[4]), (1...600).contains(count),
                  let forced = Int(args[5]), (0...255).contains(forced),
                  let startFrame = Int(args[6]), (0..<count).contains(startFrame) else {
                throw ProbeError.usage
            }
            let rom = try Data(contentsOf: URL(fileURLWithPath: args[1]))
            let source = try Data(contentsOf: URL(fileURLWithPath: args[2]))
            let scheduleData = try Data(contentsOf: URL(fileURLWithPath: args[3]))
            guard digest(rom) == "d55daa439b673b0e3f5897f99ac37ecb45f974d1862b4dadb85dec34af99cb42",
                  digest(source) == "803e4197989c73408cfc5113f8f30c81ac0269958aa9e105b474b6f52437203c",
                  scheduleData.count <= 64_000,
                  let snapshot = try? Z80Snapshot.load(from: source),
                  snapshot.ram128Banks == nil, snapshot.ram48.count == 49_152 else {
                throw ProbeError.unsupportedInput
            }
            let segments = try JSONDecoder().decode([Segment].self, from: scheduleData)
            var lastEnd = 0
            guard !segments.isEmpty else { throw ProbeError.unsupportedInput }
            for segment in segments {
                guard segment.startFrame >= lastEnd,
                      segment.endFrame > segment.startFrame,
                      segment.endFrame <= count else {
                    throw ProbeError.unsupportedInput
                }
                _ = try key(segment.key)
                lastEnd = segment.endFrame
            }
            let savedOutput = dup(STDOUT_FILENO)
            guard savedOutput >= 0 else { throw ProbeError.unsupportedInput }
            fflush(stdout)
            guard dup2(STDERR_FILENO, STDOUT_FILENO) >= 0 else {
                close(savedOutput)
                throw ProbeError.unsupportedInput
            }
            let emulator = Speccy48Emulator(rom: [UInt8](rom))
            fflush(stdout)
            guard dup2(savedOutput, STDOUT_FILENO) >= 0 else {
                close(savedOutput)
                throw ProbeError.unsupportedInput
            }
            close(savedOutput)
            emulator.apply(snapshot: snapshot)
            var cpu = emulator.cpu
            var memory = emulator.mem
            var cycles = 0
            var nextInterrupt = 69_888
            var active: KeyboardMatrix.Key?
            var frames: [Frame] = []
            for frame in 0..<count {
                let pressed = try segments.first(where: {
                    $0.startFrame <= frame && frame < $0.endFrame
                }).map { try key($0.key) }
                if pressed != active {
                    if let active { emulator.keyboard.release(active) }
                    if let pressed { emulator.keyboard.press(pressed) }
                    active = pressed
                }
                let boundary = cycles + 69_888
                var steps = 0
                while cycles < boundary {
                    let result = cpu.step(
                        read: { memory.read($0) },
                        write: { address, value in
                            memory.write(
                                address,
                                address == 0x9695 && frame >= startFrame
                                    ? UInt8(forced) : value
                            )
                        },
                        ioRead: { port in
                            port & 1 == 0
                                ? emulator.keyboard.readPortFE(highByte: UInt8(port >> 8))
                                : 0xFF
                        },
                        ioWrite: { _, _ in }
                    )
                    steps += 1
                    guard steps <= 100_000 else {
                        throw ProbeError.stepBudget(frame: frame + 1)
                    }
                    switch result {
                    case .ok(let cost): cycles += cost
                    case .unimplemented:
                        throw ProbeError.unimplemented(frame: frame + 1, pc: cpu.pc)
                    }
                    while cycles >= nextInterrupt {
                        cycles += cpu.acceptMaskableInterrupt(
                            read: { memory.read($0) },
                            write: { memory.write($0, $1) }
                        )
                        nextInterrupt += 69_888
                    }
                }
                let enemyBase: UInt16 = 0x9702 + 12 * 12
                frames.append(Frame(
                    index: frame + 1,
                    playerKind: Int(memory.read(0x9702)),
                    playerX: Int(memory.read(0x9705)),
                    playerY: Int(memory.read(0x9706)),
                    enemyKind: Int(memory.read(enemyBase)),
                    enemyX: Int(memory.read(enemyBase &+ 3)),
                    enemyY: Int(memory.read(enemyBase &+ 4)),
                    rng: Int(memory.read(0x9695))
                ))
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(Report(
                fixedRNGByte: forced, interventionStartFrame: startFrame,
                frames: frames
            )))
            FileHandle.standardOutput.write(Data([0x0A]))
        } catch {
            fputs("RNGIntervention: \(error)\n", stderr)
            exit(1)
        }
    }
}
