import CryptoKit
import Darwin
import Foundation

private enum ScreenError: Error, CustomStringConvertible {
    case usage
    case invalidInput
    case mismatchedPixels(matching: Int, covered: Int)

    var description: String {
        switch self {
        case .usage:
            "Usage: VerifyBackgroundScreen <48k.rom> <gameplay.z80> <private-world.json> <private-background-atlas.json>"
        case .invalidInput:
            "Expected the verified 48K ROM and gameplay snapshot"
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
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

@main
private struct VerifyBackgroundScreen {
    static func main() {
        do {
            let args = CommandLine.arguments
            guard args.count == 5 else { throw ScreenError.usage }
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
            let room = WorldReference.capturedGameplayRoom
            guard let roomType = world.roomType(at: room) else {
                throw ScreenError.invalidInput
            }

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
            let screen = ULA.render(mem: emulator.mem, flashOn: false)
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
            guard count == 29_056, matches == count else {
                throw ScreenError.mismatchedPixels(matching: matches, covered: count)
            }
            let report = Report(
                snapshotSHA256: sha256(source), roomID: 168, roomTemplate: roomType,
                placements: placements.count, coveredPixels: count,
                matchingRGBPixels: matches, uncoveredPixels: area - count
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
