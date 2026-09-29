import CryptoKit
import Darwin
import Foundation

private enum ActorScreenError: Error, CustomStringConvertible {
    case usage
    case invalidInput
    case unimplemented
    case mismatch

    var description: String {
        switch self {
        case .usage:
            "Usage: VerifyActorScreen <48k.rom> <gameplay.z80> <private-sprite-atlas.json> <q|w|e|r|t> [--diagnose]"
        case .invalidInput:
            "Expected the verified 48K ROM, gameplay snapshot and private sprite atlas"
        case .unimplemented:
            "The reference emulator encountered an unsupported CPU instruction"
        case .mismatch:
            "Player bitmap, position or observed color counts differ from the verified reference"
        }
    }
}

private struct Report: Encodable {
    let key: String
    let frames: Int
    let exactColorFrames: Int
    let matchingColorPixels: Int
    let totalPlayerPixels: Int
    let nonmatchingFrames: [Int]
}

private struct MismatchDetail: Encodable {
    let frame: Int
    let pixelCount: Int
    let xBounds: [Int]
    let yBounds: [Int]
    let overlappingActorSlots: [Int]
    let pixelsInsideOverlappingActorBounds: Int
    let pixelsOnOverlappingActorMasks: Int
    let pixelsInOverlappingActorAttributeCells: Int
}

private struct DiagnosticReport: Encodable {
    let report: Report
    let mismatchDetails: [MismatchDetail]
}

private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

@main
private struct VerifyActorScreen {
    static func main() {
        do {
            let args = CommandLine.arguments
            guard args.count == 5 || args.count == 6 else {
                throw ActorScreenError.usage
            }
            let diagnose = args.count == 6
            if diagnose && args[5] != "--diagnose" {
                throw ActorScreenError.usage
            }
            let key: KeyboardMatrix.Key
            switch args[4] {
            case "q": key = .q
            case "w": key = .w
            case "e": key = .e
            case "r": key = .r
            case "t": key = .t
            default: throw ActorScreenError.usage
            }
            let rom = try Data(contentsOf: URL(fileURLWithPath: args[1]))
            let source = try Data(contentsOf: URL(fileURLWithPath: args[2]))
            guard digest(rom) == "d55daa439b673b0e3f5897f99ac37ecb45f974d1862b4dadb85dec34af99cb42",
                  digest(source) == WorldReference.supportedSnapshotSHA256,
                  let snapshot = try? Z80Snapshot.load(from: source),
                  snapshot.ram128Banks == nil, snapshot.ram48.count == 49_152 else {
                throw ActorScreenError.invalidInput
            }
            let atlas = try SpriteAtlas.load(
                from: Data(contentsOf: URL(fileURLWithPath: args[3]))
            )
            let savedOutput = dup(STDOUT_FILENO)
            guard savedOutput >= 0 else { throw ActorScreenError.invalidInput }
            fflush(stdout)
            guard dup2(STDERR_FILENO, STDOUT_FILENO) >= 0 else {
                close(savedOutput)
                throw ActorScreenError.invalidInput
            }
            let emulator = Speccy48Emulator(rom: [UInt8](rom))
            fflush(stdout)
            guard dup2(savedOutput, STDOUT_FILENO) >= 0 else {
                close(savedOutput)
                throw ActorScreenError.invalidInput
            }
            close(savedOutput)
            emulator.apply(snapshot: snapshot)
            var exact = 0
            var matching = 0
            var total = 0
            var nonmatching: [Int] = []
            var details: [MismatchDetail] = []
            for frame in 0..<100 {
                if frame == 20 { emulator.keyboard.press(key) }
                if frame == 40 { emulator.keyboard.release(key) }
                emulator.stepFrame()
                guard emulator.unimplementedCount == 0 else {
                    throw ActorScreenError.unimplemented
                }
                let memory = emulator.mem
                let kind = Int(memory.read(0x9702))
                let x = Int(memory.read(0x9705))
                let y = Int(memory.read(0x9706))
                guard memory.read(0x9703) == 168,
                      let mask = try atlas.mask(at: kind) else {
                    throw ActorScreenError.mismatch
                }
                let sprite = CapturedActorSprite(
                    mask: mask, actorAt: GridPoint(x, y)
                )
                let pixels = sprite.screenPixels()
                var frameMatching = 0
                var frameTotal = 0
                var mismatches: [GridPoint] = []
                for row in 0..<mask.height {
                    let screenY = sprite.topLeft.y + row
                    for column in 0..<mask.width {
                        let screenX = x + column
                        guard (0..<256).contains(screenX),
                              (0..<192).contains(screenY) else { continue }
                        let bitmapAddress = 0x4000 + ((screenY & 0xC0) << 5)
                            + ((screenY & 7) << 8)
                            + ((screenY & 0x38) << 2) + screenX / 8
                        let on = memory.read(UInt16(bitmapAddress))
                            & (0x80 >> (screenX & 7)) != 0
                        let attribute = memory.read(UInt16(
                            0x5800 + (screenY / 8) * 32 + screenX / 8
                        ))
                        let paletteIndex = SpectrumAttribute(attribute)
                            .paletteIndex(pixelOn: on)
                        let color = SpectrumPalette.colors[Int(paletteIndex)]
                        let white = color.red >= 0xD7
                            && color.red == color.green && color.red == color.blue
                        if pixels[row * mask.width + column] == white {
                            frameMatching += 1
                        } else {
                            mismatches.append(GridPoint(screenX, screenY))
                        }
                        frameTotal += 1
                    }
                }
                if frameMatching == frameTotal {
                    exact += 1
                } else {
                    nonmatching.append(frame + 1)
                    var overlapping: [Int] = []
                    var coveredBounds = Set<GridPoint>()
                    var coveredMasks = Set<GridPoint>()
                    var coveredAttributeCells = Set<GridPoint>()
                    for slot in 1..<25 {
                        let base = UInt16(0x9702 + slot * 12)
                        let actorKind = Int(memory.read(base))
                        guard actorKind > 0, actorKind < SpriteAtlas.spriteCount,
                              memory.read(base &+ 1) == 168,
                              let actorMask = try atlas.mask(at: actorKind) else {
                            continue
                        }
                        let otherX = Int(memory.read(base &+ 3))
                        let otherY = Int(memory.read(base &+ 4))
                        let otherTop = otherY - actorMask.height + 1
                        if otherX < x + mask.width, x < otherX + actorMask.width,
                           otherTop <= y, sprite.topLeft.y <= otherY {
                            overlapping.append(slot)
                            let otherSprite = CapturedActorSprite(
                                mask: actorMask, actorAt: GridPoint(otherX, otherY)
                            )
                            let otherPixels = otherSprite.screenPixels()
                            var actorAttributeCells = Set<GridPoint>()
                            for row in 0..<actorMask.height {
                                for column in 0..<actorMask.width
                                where otherPixels[row * actorMask.width + column] {
                                    actorAttributeCells.insert(
                                        GridPoint((otherX + column) / 8, (otherTop + row) / 8)
                                    )
                                }
                            }
                            for point in mismatches {
                                if actorAttributeCells.contains(GridPoint(point.x / 8, point.y / 8)) {
                                    coveredAttributeCells.insert(point)
                                }
                                let column = point.x - otherX
                                let row = point.y - otherTop
                                guard (0..<actorMask.width).contains(column),
                                      (0..<actorMask.height).contains(row) else {
                                    continue
                                }
                                coveredBounds.insert(point)
                                if otherPixels[row * actorMask.width + column] {
                                    coveredMasks.insert(point)
                                }
                            }
                        }
                    }
                    guard let minX = mismatches.map(\.x).min(),
                          let maxX = mismatches.map(\.x).max(),
                          let minY = mismatches.map(\.y).min(),
                          let maxY = mismatches.map(\.y).max() else {
                        throw ActorScreenError.mismatch
                    }
                    details.append(MismatchDetail(
                        frame: frame + 1, pixelCount: mismatches.count,
                        xBounds: [minX, maxX],
                        yBounds: [minY, maxY],
                        overlappingActorSlots: overlapping,
                        pixelsInsideOverlappingActorBounds: coveredBounds.count,
                        pixelsOnOverlappingActorMasks: coveredMasks.count,
                        pixelsInOverlappingActorAttributeCells: coveredAttributeCells.count
                    ))
                }
                matching += frameMatching
                total += frameTotal
            }
            let expected = switch args[4] {
            case "q", "e", "r": 33_952
            case "w": 34_336
            default: 37_280
            }
            guard total == expected,
                  exact == (args[4] == "w" ? 89 : 100),
                  matching == (args[4] == "w" ? 34_212 : expected),
                  nonmatching == (args[4] == "w" ? Array(43...53) : []) else {
                throw ActorScreenError.mismatch
            }
            let report = Report(
                key: args[4], frames: 100, exactColorFrames: exact,
                matchingColorPixels: matching, totalPlayerPixels: total,
                nonmatchingFrames: nonmatching
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let output = try diagnose
                ? encoder.encode(DiagnosticReport(report: report, mismatchDetails: details))
                : encoder.encode(report)
            FileHandle.standardOutput.write(output)
            FileHandle.standardOutput.write(Data([0x0A]))
        } catch {
            fputs("VerifyActorScreen: \(error)\n", stderr)
            exit(1)
        }
    }
}
