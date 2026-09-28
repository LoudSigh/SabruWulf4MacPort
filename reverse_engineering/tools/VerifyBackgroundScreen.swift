import CryptoKit
import Darwin
import Foundation

private enum ScreenError: Error, CustomStringConvertible {
    case usage
    case invalidInput
    case frameBudget(frame: Int)
    case unimplemented(pc: UInt16)
    case mismatchedPixels(matching: Int, covered: Int)

    var description: String {
        switch self {
        case .usage:
            "Usage: VerifyBackgroundScreen <48k.rom> <gameplay.z80> <private-world.json> <private-background-atlas.json> [--schedule <private-or-source-free-schedule.json> <frames: 1...600>]"
        case .invalidInput:
            "Expected the verified 48K ROM, gameplay snapshot, atlas and valid schedule"
        case .frameBudget(let frame):
            "Reference CPU exceeded 100000 steps in frame \(frame)"
        case .unimplemented(let pc):
            String(format: "Reference CPU encountered an unimplemented opcode at 0x%04X", pc)
        case .mismatchedPixels(let matching, let covered):
            "Only \(matching) of \(covered) covered background pixels match the source screen"
        }
    }
}

private struct Report: Encodable {
    let snapshotSHA256: String
    let roomID: Int
    let roomTemplate: Int
    let placements: Int
    let coveredPixels: Int
    let matchingRGBPixels: Int
    let uncoveredPixels: Int
    let replayFrame: Int?
}

private struct Segment: Decodable {
    let key: String
    let startFrame: Int
    let endFrame: Int
}

private func key(_ name: String) throws -> KeyboardMatrix.Key {
    switch name {
    case "q": .q
    case "w": .w
    case "e": .e
    case "r": .r
    case "t": .t
    default: throw ScreenError.invalidInput
    }
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

@main
private struct VerifyBackgroundScreen {
    static func main() {
        do {
            let args = CommandLine.arguments
            guard args.count == 5 || (args.count == 8 && args[5] == "--schedule")
            else { throw ScreenError.usage }
            let targetFrame: Int?
            let segments: [Segment]
            if args.count == 8 {
                guard let frames = Int(args[7]), (1...600).contains(frames) else {
                    throw ScreenError.usage
                }
                let scheduleData = try Data(contentsOf: URL(fileURLWithPath: args[6]))
                guard scheduleData.count <= 64_000 else { throw ScreenError.invalidInput }
                segments = try JSONDecoder().decode([Segment].self, from: scheduleData)
                var previousEnd = 0
                guard !segments.isEmpty else { throw ScreenError.invalidInput }
                for segment in segments {
                    guard segment.startFrame >= previousEnd,
                          segment.endFrame > segment.startFrame,
                          segment.endFrame <= frames else {
                        throw ScreenError.invalidInput
                    }
                    _ = try key(segment.key)
                    previousEnd = segment.endFrame
                }
                targetFrame = frames
            } else {
                targetFrame = nil
                segments = []
            }
            let rom = try Data(contentsOf: URL(fileURLWithPath: args[1]))
            let source = try Data(contentsOf: URL(fileURLWithPath: args[2]))
            guard sha256(rom) == "d55daa439b673b0e3f5897f99ac37ecb45f974d1862b4dadb85dec34af99cb42",
                  sha256(source) == WorldReference.supportedSnapshotSHA256,
                  let snapshot = try? Z80Snapshot.load(from: source),
                  snapshot.ram128Banks == nil, snapshot.ram48.count == 49_152 else {
                throw ScreenError.invalidInput
            }
            let world = try WorldReference.load(
                from: Data(contentsOf: URL(fileURLWithPath: args[3]))
            )
            let atlas = try BackgroundAtlas.load(
                from: Data(contentsOf: URL(fileURLWithPath: args[4]))
            )
            try atlas.validate(world: world)
            let savedOutput = dup(STDOUT_FILENO)
            guard savedOutput >= 0 else { throw ScreenError.invalidInput }
            fflush(stdout)
            guard dup2(STDERR_FILENO, STDOUT_FILENO) >= 0 else {
                close(savedOutput)
                throw ScreenError.invalidInput
            }
            let emulator = Speccy48Emulator(rom: [UInt8](rom))
            fflush(stdout)
            guard dup2(savedOutput, STDOUT_FILENO) >= 0 else {
                close(savedOutput)
                throw ScreenError.invalidInput
            }
            close(savedOutput)
            emulator.apply(snapshot: snapshot)
            var cpu = emulator.cpu
            var memory = emulator.mem
            var cycles = 0
            var nextInterrupt = 69_888
            if let targetFrame {
                var active: KeyboardMatrix.Key?
                for frame in 0..<targetFrame {
                    let next = try segments.first(where: {
                        $0.startFrame <= frame && frame < $0.endFrame
                    }).map { try key($0.key) }
                    if next != active {
                        if let active { emulator.keyboard.release(active) }
                        if let next { emulator.keyboard.press(next) }
                        active = next
                    }
                    let boundary = cycles + 69_888
                    var steps = 0
                    while cycles < boundary {
                        let result = cpu.step(
                            read: { memory.read($0) },
                            write: { memory.write($0, $1) },
                            ioRead: { port in
                                port & 1 == 0
                                    ? emulator.keyboard.readPortFE(highByte: UInt8(port >> 8))
                                    : 0xFF
                            },
                            ioWrite: { _, _ in }
                        )
                        steps += 1
                        guard steps <= 100_000 else {
                            throw ScreenError.frameBudget(frame: frame + 1)
                        }
                        switch result {
                        case .ok(let cost): cycles += cost
                        case .unimplemented: throw ScreenError.unimplemented(pc: cpu.pc)
                        }
                        while cycles >= nextInterrupt {
                            cycles += cpu.acceptMaskableInterrupt(
                                read: { memory.read($0) },
                                write: { memory.write($0, $1) }
                            )
                            nextInterrupt += 69_888
                        }
                    }
                }
            }
            let roomID = Int(memory.read(0x9703))
            let room = RoomID(roomID % 16, roomID / 16)
            guard let roomType = world.roomType(at: room) else {
                throw ScreenError.invalidInput
            }
            let screen = ULA.render(mem: memory, flashOn: false)
            let placements = world.rooms[roomType].placements
            let area = 256 * 192
            var predicted = Array(repeating: SpectrumRGB(red: 0, green: 0, blue: 0), count: area)
            var covered = Array(repeating: false, count: area)
            for placement in placements {
                let bitmap = try atlas.mask(at: placement.graphicAddress)
                let indices = bitmap.paletteIndices(invertBitmap: true)
                for y in 0..<bitmap.height {
                    let screenY = placement.y + y
                    guard (0..<192).contains(screenY) else { continue }
                    for x in 0..<bitmap.width {
                        let screenX = placement.x + x
                        guard (0..<256).contains(screenX) else { continue }
                        let target = screenY * 256 + screenX
                        let sourceIndex = y * bitmap.width + x
                        predicted[target] = SpectrumPalette.colors[Int(indices[sourceIndex])]
                        covered[target] = true
                    }
                }
            }
            var matches = 0
            var count = 0
            for index in 0..<area where covered[index] {
                count += 1
                let color = predicted[index]
                let offset = index * 4
                if color.red == screen[offset + 2],
                   color.green == screen[offset + 1],
                   color.blue == screen[offset] {
                    matches += 1
                }
            }
            guard count > 0, matches == count,
                  (targetFrame != nil || count == 29_056) else {
                throw ScreenError.mismatchedPixels(matching: matches, covered: count)
            }
            let report = Report(
                snapshotSHA256: sha256(source), roomID: roomID, roomTemplate: roomType,
                placements: placements.count, coveredPixels: count,
                matchingRGBPixels: matches, uncoveredPixels: area - count,
                replayFrame: targetFrame
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(report))
            FileHandle.standardOutput.write(Data([0x0A]))
        } catch {
            fputs("VerifyBackgroundScreen: \(error)\n", stderr)
            exit(1)
        }
    }
}
