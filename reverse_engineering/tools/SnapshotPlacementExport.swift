import CryptoKit
import Darwin
import Foundation

private enum ExportError: Error, CustomStringConvertible {
    case usage
    case invalidInput
    case invalidReplay
    case frameMismatch(Int)
    case unimplemented

    var description: String {
        switch self {
        case .usage:
            "Usage: SnapshotPlacementExport <48k.rom> <gameplay.z80> <verified-replay-900.json> <private-world-v2.json> <private-sprite-atlas.json>"
        case .invalidInput:
            "Expected the verified 48K ROM, gameplay snapshot, world and sprite atlas"
        case .invalidReplay:
            "Expected a verified reference-relative scheduled replay including frame 656"
        case .frameMismatch(let frame):
            "Source RAM or screen differs from the independent replay at frame \(frame)"
        case .unimplemented:
            "The reference emulator encountered an unsupported instruction"
        }
    }
}

private struct Interval: Decodable {
    let key: String
    let startFrame: Int
    let endFrame: Int
}

private struct Frame: Decodable {
    let index: Int
    let ramSHA256: String
    let screenSHA256: String
}

private struct Replay: Decodable {
    let snapshotSHA256: String
    let romSHA256: String
    let frameBoundaryMode: String
    let input: String
    let schedule: [Interval]
    let frames: [Frame]
}

private struct Record: Encodable {
    let id: Int
    let spriteID: Int
    let roomID: Int
    let x: Int
    let y: Int
}

private struct Payload: Encodable {
    let schemaVersion = 1
    let snapshotSHA256: String
    let sourceFrame = 656
    let records: [Record]
}

private func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
    case "0": .num0
    case "3": .num3
    default: throw ExportError.invalidReplay
    }
}

@main
private struct SnapshotPlacementExport {
    static func main() {
        do {
            let args = CommandLine.arguments
            guard args.count == 6 else { throw ExportError.usage }
            let rom = try Data(contentsOf: URL(fileURLWithPath: args[1]))
            let source = try Data(contentsOf: URL(fileURLWithPath: args[2]))
            guard hash(rom) == "d55daa439b673b0e3f5897f99ac37ecb45f974d1862b4dadb85dec34af99cb42",
                  hash(source) == WorldReference.supportedSnapshotSHA256,
                  let snapshot = try? Z80Snapshot.load(from: source),
                  snapshot.ram128Banks == nil, snapshot.ram48.count == 49_152 else {
                throw ExportError.invalidInput
            }
            let world = try WorldReference.load(from:
                Data(contentsOf: URL(fileURLWithPath: args[4]))
            )
            let atlas = try SpriteAtlas.load(from:
                Data(contentsOf: URL(fileURLWithPath: args[5]))
            )
            let replayData = try Data(contentsOf: URL(fileURLWithPath: args[3]))
            guard replayData.count <= 2_000_000 else { throw ExportError.invalidReplay }
            let replay = try JSONDecoder().decode(Replay.self, from: replayData)
            guard replay.snapshotSHA256 == hash(source),
                  replay.romSHA256 == hash(rom),
                  replay.frameBoundaryMode == "reference-relative",
                  replay.input == "schedule",
                  replay.frames.count >= 656, replay.frames.count <= 1800,
                  !replay.schedule.isEmpty else {
                throw ExportError.invalidReplay
            }
            var previousEnd = 0
            for interval in replay.schedule {
                guard interval.startFrame >= previousEnd,
                      interval.endFrame > interval.startFrame,
                      interval.endFrame <= replay.frames.count else {
                    throw ExportError.invalidReplay
                }
                _ = try key(interval.key)
                previousEnd = interval.endFrame
            }

            let savedOutput = dup(STDOUT_FILENO)
            guard savedOutput >= 0 else { throw ExportError.invalidInput }
            fflush(stdout)
            guard dup2(STDERR_FILENO, STDOUT_FILENO) >= 0 else {
                close(savedOutput)
                throw ExportError.invalidInput
            }
            let emulator = Speccy48Emulator(rom: [UInt8](rom))
            fflush(stdout)
            guard dup2(savedOutput, STDOUT_FILENO) >= 0 else {
                close(savedOutput)
                throw ExportError.invalidInput
            }
            close(savedOutput)
            emulator.apply(snapshot: snapshot)
            var held: KeyboardMatrix.Key?
            for index in 0..<656 {
                let pressed = try replay.schedule.first(where: {
                    $0.startFrame <= index && index < $0.endFrame
                }).map { try key($0.key) }
                if held != pressed {
                    if let held { emulator.keyboard.release(held) }
                    if let pressed { emulator.keyboard.press(pressed) }
                    held = pressed
                }
                emulator.stepFrame()
                guard emulator.unimplementedCount == 0 else {
                    throw ExportError.unimplemented
                }
                let ram = emulator.mem.exportRam48K()
                let reference = replay.frames[index]
                guard reference.index == index + 1,
                      hash(Data(ram)) == reference.ramSHA256,
                      hash(Data(ram.prefix(6912))) == reference.screenSHA256 else {
                    throw ExportError.frameMismatch(index + 1)
                }
            }
            let base: UInt16 = 0x97FE
            let records = (0..<4).map { id in
                let address = base &+ UInt16(id * 12)
                return Record(
                    id: id, spriteID: Int(emulator.mem.read(address)),
                    roomID: Int(emulator.mem.read(address &+ 1)),
                    x: Int(emulator.mem.read(address &+ 3)),
                    y: Int(emulator.mem.read(address &+ 4))
                )
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let result = try encoder.encode(Payload(
                snapshotSHA256: hash(source), records: records
            ))
            let validated = try CapturedPlacementState.load(
                from: result, world: world
            )
            try validated.validate(spriteAtlas: atlas)
            guard let output = String(data: result, encoding: .utf8) else {
                throw ExportError.invalidInput
            }
            print(output)
        } catch {
            fputs("SnapshotPlacementExport: \(error)\n", stderr)
            exit(1)
        }
    }
}
