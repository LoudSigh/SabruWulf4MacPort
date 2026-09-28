import CryptoKit
import Darwin
import Foundation

private enum VerificationError: Error, CustomStringConvertible {
    case usage
    case invalidInput
    case invalidReplay
    case frameMismatch(index: Int)
    case unimplemented
    case menuMismatch(expected: Int, actual: Int?)

    var description: String {
        switch self {
        case .usage:
            "Usage: VerifyReferenceReplay <48k.rom> <gameplay.z80> <private-reference-replay.json> [--menu <menu.z80> <expected-first-menu-frame> | --menu-after <menu.z80> <after-frame> <expected-first-menu-frame>]"
        case .invalidInput:
            "Expected the verified 48K ROM and gameplay snapshot"
        case .invalidReplay:
            "Expected a bounded reference-relative replay with sorted valid input intervals"
        case .frameMismatch(let index):
            "Reference replay RAM or screen hash differs at frame \(index)"
        case .unimplemented:
            "The unmodified reference emulator encountered an unsupported instruction"
        case .menuMismatch(let expected, let actual):
            "First exact menu text region: expected frame \(expected), observed \(actual.map(String.init) ?? "none")"
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
    let frameBoundaryMode: String?
    let input: String
    let schedule: [Interval]
    let frames: [Frame]
}

private func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func inputKey(_ name: String) throws -> KeyboardMatrix.Key {
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
    default: throw VerificationError.invalidReplay
    }
}

@main
private struct VerifyReferenceReplay {
    static func main() {
        do {
            let args = CommandLine.arguments
            guard args.count == 4
                    || (args.count == 7 && args[4] == "--menu")
                    || (args.count == 8 && args[4] == "--menu-after")
            else { throw VerificationError.usage }
            let rom = try Data(contentsOf: URL(fileURLWithPath: args[1]))
            let snapshotData = try Data(contentsOf: URL(fileURLWithPath: args[2]))
            let romHash = hash(rom)
            let snapshotHash = hash(snapshotData)
            guard romHash == "d55daa439b673b0e3f5897f99ac37ecb45f974d1862b4dadb85dec34af99cb42",
                  snapshotHash == "803e4197989c73408cfc5113f8f30c81ac0269958aa9e105b474b6f52437203c",
                  let snapshot = try? Z80Snapshot.load(from: snapshotData),
                  snapshot.ram128Banks == nil, snapshot.ram48.count == 49_152 else {
                throw VerificationError.invalidInput
            }
            let replayData = try Data(contentsOf: URL(fileURLWithPath: args[3]))
            guard replayData.count <= 8_000_000 else {
                throw VerificationError.invalidReplay
            }
            let replay = try JSONDecoder().decode(Replay.self, from: replayData)
            guard replay.snapshotSHA256 == snapshotHash,
                  replay.romSHA256 == romHash,
                  replay.frameBoundaryMode == "reference-relative",
                  replay.input == "schedule",
                  (1...1800).contains(replay.frames.count),
                  !replay.schedule.isEmpty else {
                throw VerificationError.invalidReplay
            }
            var previousEnd = 0
            for interval in replay.schedule {
                guard interval.startFrame >= previousEnd,
                      interval.endFrame > interval.startFrame,
                      interval.endFrame <= replay.frames.count else {
                    throw VerificationError.invalidReplay
                }
                _ = try inputKey(interval.key)
                previousEnd = interval.endFrame
            }

            let menuSnapshot: Z80Snapshot?
            let expectedMenuFrame: Int?
            let menuAfterFrame: Int
            if args.count >= 7 {
                let after = args.count == 8 ? Int(args[6]) : 0
                let expected = Int(args[args.count - 1])
                guard let after, let expected,
                      (0..<expected).contains(after),
                      (1...replay.frames.count).contains(expected) else {
                    throw VerificationError.invalidReplay
                }
                let menuData = try Data(contentsOf: URL(fileURLWithPath: args[5]))
                guard hash(menuData) == "34d98ec3dc55d60755a7d9ceebe45c3a7e345ce5961692d25d2d6718bcdc20ea",
                      let menu = try? Z80Snapshot.load(from: menuData),
                      menu.ram128Banks == nil, menu.ram48.count == 49_152 else {
                    throw VerificationError.invalidInput
                }
                menuSnapshot = menu
                expectedMenuFrame = expected
                menuAfterFrame = after
            } else {
                menuSnapshot = nil
                expectedMenuFrame = nil
                menuAfterFrame = 0
            }
            let savedOutput = dup(STDOUT_FILENO)
            guard savedOutput >= 0 else { throw VerificationError.invalidInput }
            fflush(stdout)
            guard dup2(STDERR_FILENO, STDOUT_FILENO) >= 0 else {
                close(savedOutput)
                throw VerificationError.invalidInput
            }
            let emulator = Speccy48Emulator(rom: [UInt8](rom))
            let menuEmulator = menuSnapshot.map { _ in
                Speccy48Emulator(rom: [UInt8](rom))
            }
            fflush(stdout)
            guard dup2(savedOutput, STDOUT_FILENO) >= 0 else {
                close(savedOutput)
                throw VerificationError.invalidInput
            }
            close(savedOutput)
            emulator.apply(snapshot: snapshot)
            if let menuSnapshot { menuEmulator?.apply(snapshot: menuSnapshot) }
            let menuPixels = menuEmulator.map {
                ULA.render(mem: $0.mem, flashOn: false)
            }
            var pressed: KeyboardMatrix.Key?
            var firstMenuFrame: Int?
            for (offset, frame) in replay.frames.enumerated() {
                guard frame.index == offset + 1 else {
                    throw VerificationError.invalidReplay
                }
                let next = try replay.schedule.first(where: {
                    $0.startFrame <= offset && offset < $0.endFrame
                }).map { try inputKey($0.key) }
                if next != pressed {
                    if let pressed { emulator.keyboard.release(pressed) }
                    if let next { emulator.keyboard.press(next) }
                    pressed = next
                }
                emulator.stepFrame()
                guard emulator.unimplementedCount == 0 else {
                    throw VerificationError.unimplemented
                }
                let ram = emulator.mem.exportRam48K()
                guard frame.ramSHA256 == hash(Data(ram)),
                      frame.screenSHA256 == hash(Data(ram.prefix(6912))) else {
                    throw VerificationError.frameMismatch(index: frame.index)
                }
                if let menuPixels, firstMenuFrame == nil,
                   frame.index > menuAfterFrame {
                    let current = ULA.render(mem: emulator.mem, flashOn: false)
                    let matches = (72..<88).allSatisfy { row in
                        (48..<208).allSatisfy { column in
                            let offset = (row * 256 + column) * 4
                            return current[offset] == menuPixels[offset]
                                && current[offset + 1] == menuPixels[offset + 1]
                                && current[offset + 2] == menuPixels[offset + 2]
                        }
                    }
                    if matches { firstMenuFrame = frame.index }
                }
            }
            if let expectedMenuFrame, firstMenuFrame != expectedMenuFrame {
                throw VerificationError.menuMismatch(
                    expected: expectedMenuFrame, actual: firstMenuFrame
                )
            }
            print("Verified \(replay.frames.count)/\(replay.frames.count) RAM and screen hashes against the unmodified emulator")
            if let firstMenuFrame {
                print("First 2560/2560 matching menu-text RGB pixels after frame \(menuAfterFrame) at frame \(firstMenuFrame)")
            }
        } catch {
            fputs("VerifyReferenceReplay: \(error)\n", stderr)
            exit(1)
        }
    }
}
