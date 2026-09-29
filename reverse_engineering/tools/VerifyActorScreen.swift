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
            "Usage: VerifyActorScreen <48k.rom> <gameplay.z80> <private-sprite-atlas.json> <q|w|e|r|t> [--diagnose|--diagnose-bits]"
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

private struct BitDifference {
    let point: GridPoint
    let playerOn: Bool
    let sourceOn: Bool
}

private struct BitReport: Encodable {
    let report: Report
    let bitmapDifferencesAllFrames: Int
    let bitmapDifferencesMismatchFrames: Int
    let bitmapDifferencesOnOtherActorMasks: Int
    let otherActorMaskPixelsInsidePlayer: Int
    let bitmapXorMismatchPixels: Int
    let playerOffSourceOn: Int
    let playerOnSourceOff: Int
    let playerOffSourceOnOnOtherActorMask: Int
    let playerOnSourceOffOnOtherActorMask: Int
    let bitmapXorSourceFrames: Int
    let matchingBitmapXorPixels: Int
    let checkedBitmapXorPixels: Int
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
            let diagnose = args.count == 6 && args[5] == "--diagnose"
            let diagnoseBits = args.count == 6 && args[5] == "--diagnose-bits"
            if args.count == 6 && !diagnose && !diagnoseBits {
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
            var bitmapDifferencesAllFrames = 0
            var bitmapDifferencesMismatchFrames = 0
            var bitmapDifferencesOnOtherActorMasks = 0
            var otherActorMaskPixelsInsidePlayer = 0
            var bitmapXorMismatchPixels = 0
            var playerOffSourceOn = 0
            var playerOnSourceOff = 0
            var playerOffSourceOnOnOtherActorMask = 0
            var playerOnSourceOffOnOtherActorMask = 0
            var bitmapXorSourceFrames = 0
            var matchingBitmapXorPixels = 0
            var checkedBitmapXorPixels = 0
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
                var projectedXor: [Bool]?
                if diagnoseBits && args[4] == "w" && (43...53).contains(frame + 1) {
                    let otherBase: UInt16 = 0x9702 + 18 * 12
                    let otherKind = Int(memory.read(otherBase))
                    guard memory.read(otherBase &+ 1) == 168,
                          otherKind > 0, otherKind < SpriteAtlas.spriteCount,
                          let otherMask = try atlas.mask(at: otherKind) else {
                        throw ActorScreenError.mismatch
                    }
                    let other = CapturedActorSprite(
                        mask: otherMask,
                        actorAt: GridPoint(
                            Int(memory.read(otherBase &+ 3)),
                            Int(memory.read(otherBase &+ 4))
                        )
                    )
                    projectedXor = CapturedOverlapBitmap.xorPlayerRectangle(
                        player: sprite, overlapping: other
                    )
                    bitmapXorSourceFrames += 1
                }
                var frameMatching = 0
                var frameTotal = 0
                var mismatches: [GridPoint] = []
                var bitmapDifferences: [BitDifference] = []
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
                        if let projectedXor {
                            checkedBitmapXorPixels += 1
                            if projectedXor[row * mask.width + column] == on {
                                matchingBitmapXorPixels += 1
                            }
                        }
                        let attribute = memory.read(UInt16(
                            0x5800 + (screenY / 8) * 32 + screenX / 8
                        ))
                        let paletteIndex = SpectrumAttribute(attribute)
                            .paletteIndex(pixelOn: on)
                        let color = SpectrumPalette.colors[Int(paletteIndex)]
                        let white = color.red >= 0xD7
                            && color.red == color.green && color.red == color.blue
                        let playerOn = pixels[row * mask.width + column]
                        if playerOn != on {
                            bitmapDifferences.append(BitDifference(
                                point: GridPoint(screenX, screenY),
                                playerOn: playerOn, sourceOn: on
                            ))
                        }
                        if playerOn == white {
                            frameMatching += 1
                        } else {
                            mismatches.append(GridPoint(screenX, screenY))
                        }
                        frameTotal += 1
                    }
                }
                bitmapDifferencesAllFrames += bitmapDifferences.count
                if frameMatching == frameTotal {
                    exact += 1
                } else {
                    nonmatching.append(frame + 1)
                    var overlapping: [Int] = []
                    var coveredBounds = Set<GridPoint>()
                    var coveredMasks = Set<GridPoint>()
                    var coveredAttributeCells = Set<GridPoint>()
                    var coveredBitmapDifferences = Set<GridPoint>()
                    var otherMaskInsidePlayer = Set<GridPoint>()
                    bitmapDifferencesMismatchFrames += bitmapDifferences.count
                    playerOffSourceOn += bitmapDifferences.filter {
                        !$0.playerOn && $0.sourceOn
                    }.count
                    playerOnSourceOff += bitmapDifferences.filter {
                        $0.playerOn && !$0.sourceOn
                    }.count
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
                                    let point = GridPoint(otherX + column, otherTop + row)
                                    actorAttributeCells.insert(GridPoint(
                                        point.x / 8, point.y / 8
                                    ))
                                    if (x..<(x + mask.width)).contains(point.x),
                                       (sprite.topLeft.y...y).contains(point.y) {
                                        otherMaskInsidePlayer.insert(point)
                                    }
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
                            for difference in bitmapDifferences {
                                let column = difference.point.x - otherX
                                let row = difference.point.y - otherTop
                                if (0..<actorMask.width).contains(column),
                                   (0..<actorMask.height).contains(row),
                                   otherPixels[row * actorMask.width + column] {
                                    coveredBitmapDifferences.insert(difference.point)
                                }
                            }
                        }
                    }
                    bitmapDifferencesOnOtherActorMasks += coveredBitmapDifferences.count
                    otherActorMaskPixelsInsidePlayer += otherMaskInsidePlayer.count
                    bitmapXorMismatchPixels += Set(bitmapDifferences.map(\.point))
                        .symmetricDifference(otherMaskInsidePlayer).count
                    playerOffSourceOnOnOtherActorMask += bitmapDifferences.filter {
                        !$0.playerOn && $0.sourceOn
                            && coveredBitmapDifferences.contains($0.point)
                    }.count
                    playerOnSourceOffOnOtherActorMask += bitmapDifferences.filter {
                        $0.playerOn && !$0.sourceOn
                            && coveredBitmapDifferences.contains($0.point)
                    }.count
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
            if diagnoseBits && args[4] == "w" {
                guard bitmapXorSourceFrames == 11,
                      matchingBitmapXorPixels == checkedBitmapXorPixels else {
                    throw ActorScreenError.mismatch
                }
            }
            let report = Report(
                key: args[4], frames: 100, exactColorFrames: exact,
                matchingColorPixels: matching, totalPlayerPixels: total,
                nonmatchingFrames: nonmatching
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let output: Data
            if diagnose {
                output = try encoder.encode(DiagnosticReport(
                    report: report, mismatchDetails: details
                ))
            } else if diagnoseBits {
                output = try encoder.encode(BitReport(
                    report: report,
                    bitmapDifferencesAllFrames: bitmapDifferencesAllFrames,
                    bitmapDifferencesMismatchFrames: bitmapDifferencesMismatchFrames,
                    bitmapDifferencesOnOtherActorMasks: bitmapDifferencesOnOtherActorMasks,
                    otherActorMaskPixelsInsidePlayer: otherActorMaskPixelsInsidePlayer,
                    bitmapXorMismatchPixels: bitmapXorMismatchPixels,
                    playerOffSourceOn: playerOffSourceOn,
                    playerOnSourceOff: playerOnSourceOff,
                    playerOffSourceOnOnOtherActorMask: playerOffSourceOnOnOtherActorMask,
                    playerOnSourceOffOnOtherActorMask: playerOnSourceOffOnOtherActorMask,
                    bitmapXorSourceFrames: bitmapXorSourceFrames,
                    matchingBitmapXorPixels: matchingBitmapXorPixels,
                    checkedBitmapXorPixels: checkedBitmapXorPixels
                ))
            } else {
                output = try encoder.encode(report)
            }
            FileHandle.standardOutput.write(output)
            FileHandle.standardOutput.write(Data([0x0A]))
        } catch {
            fputs("VerifyActorScreen: \(error)\n", stderr)
            exit(1)
        }
    }
}
