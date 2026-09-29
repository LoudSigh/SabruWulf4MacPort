import CryptoKit
import Darwin
import Foundation

private enum DivergenceError: Error, CustomStringConvertible {
    case usage
    case invalidSchedule
    case unsupportedOverlapSchedule
    case invalidInput
    case missingWorld
    case noActiveEnemyUpdates
    case noEnemyExpiryEvents
    case unfinishedEnemyExpiry
    case stepBudget
    case attributeWriteBudget
    case unimplemented
    case ramMismatch(matching: Int, total: Int)
    case contactMismatch(frame: Int, predicted: Bool, actual: Bool)
    case injuryMismatch(frame: Int)
    case menuSequenceMismatch
    case enemyDirectionMismatch(frame: Int)
    case enemyStateMismatch(frame: Int, expected: [Int], actual: [Int])
    case enemyExpiryMismatch(frame: Int)
    case rngStepMismatch(frame: Int)
    case scoreMismatch(frame: Int)

    var description: String {
        switch self {
        case .usage:
            "Usage: SnapshotDivergence <48k.rom> <gameplay.z80> <schedule.json> <frames: 1...1800> [--trace] [--trace-overlap-actor (100-frame W source path)] [--watch-actor-state] [--watch-player-state] [--watch-entity-state] [--watch-menu-routines] [--watch-score-entries] [--watch-overlap-attributes|--watch-overlap-registers (100-frame W source path)] [--reference-timing] [--require-ram-parity] [--require-contact-parity] [--require-first-injury-parity] [--require-menu-sequence] [--require-enemy-direction-parity] [--require-entity-phase-parity (SABRE_PRIVATE_WORLD required)] [--require-enemy-expiry-parity] [--require-rng-step-parity] [--require-score-parity] [--coverage] | --self-test"
        case .invalidSchedule:
            "Schedule intervals must be sorted, nonoverlapping and within the frame count"
        case .unsupportedOverlapSchedule:
            "The overlap attribute probe requires only W held in frames 20 through 39 of the 100-frame replay"
        case .invalidInput:
            "Expected a verified 48K ROM and gameplay snapshot"
        case .missingWorld:
            "Set SABRE_PRIVATE_WORLD to the ignored, verified version-2 world JSON"
        case .noActiveEnemyUpdates:
            "The entity-phase parity gate found no eligible moving slot-12 updates"
        case .noEnemyExpiryEvents:
            "The enemy-expiry parity gate found no eligible slot-12 timer expiries"
        case .unfinishedEnemyExpiry:
            "A slot-12 timer-expiry branch did not return within the observed frames"
        case .stepBudget:
            "Manual CPU run exceeded 100000 instructions in one frame"
        case .attributeWriteBudget:
            "Attribute-write probe exceeded its bounded 4096-event window"
        case .unimplemented:
            "The reference CPU did not implement an instruction in this replay"
        case .ramMismatch(let matching, let total):
            "Only \(matching) of \(total) RAM frames match the unmodified emulator"
        case .contactMismatch(let frame, let predicted, let actual):
            "Source contact return at frame \(frame): predicted \(predicted), observed \(actual)"
        case .injuryMismatch(let frame):
            "Captured one-life injury transition differs from the source at frame \(frame)"
        case .menuSequenceMismatch:
            "The bounded zero-life menu setup did not follow the verified second-contact timing"
        case .enemyDirectionMismatch(let frame):
            "The measured slot-12 RNG direction choice differs from source frame \(frame)"
        case .enemyStateMismatch(let frame, let expected, let actual):
            "Slot-12 state differs at frame \(frame): predicted \(expected), source \(actual)"
        case .enemyExpiryMismatch(let frame):
            "The measured slot-12 timer-expiry result differs at source frame \(frame)"
        case .rngStepMismatch(let frame):
            "A supplied-operand RNG update differs at source frame \(frame)"
        case .scoreMismatch(let frame):
            "The measured packed-BCD score write differs at source frame \(frame)"
        }
    }
}

private struct Segment: Decodable {
    let key: String
    let startFrame: Int
    let endFrame: Int
}

private struct Difference: Encodable {
    let frame: Int
    let manual: [Int]
    let fullEmulator: [Int]
}

private struct EntityMarker: Encodable {
    let kind: Int
    let roomID: Int
    let x: Int
    let y: Int

    init(_ memory: Memory, slot: Int = 12) {
        let base = UInt16(0x9702 + slot * 12)
        kind = Int(memory.read(base))
        roomID = Int(memory.read(base &+ 1))
        x = Int(memory.read(base &+ 3))
        y = Int(memory.read(base &+ 4))
    }
}

private struct ActorMarker: Encodable {
    let roomID: Int
    let x: Int
    let y: Int

    init(_ memory: Memory) {
        let base: UInt16 = 0x9702
        roomID = Int(memory.read(base &+ 1))
        x = Int(memory.read(base &+ 3))
        y = Int(memory.read(base &+ 4))
    }
}

private struct TraceFrame: Encodable {
    let index: Int
    let manualEntity: EntityMarker
    let fullEmulatorEntity: EntityMarker
    let manualPlayer: ActorMarker
    let fullEmulatorPlayer: ActorMarker
}

private struct ActorStateWrite: Encodable {
    let frame: Int
    let instructionAddress: Int
    let actorAddress: Int
    let previous: Int
    let value: Int
    let rngValue: Int
}

private struct EntityStateWrite: Encodable {
    let frame: Int
    let instructionAddress: Int
    let cycle: Int
    let address: Int
    let previous: Int
    let value: Int
}

private struct OverlapRegisterContext: Encodable {
    let ix: Int
    let iy: Int
    let hl: Int
    let matchingActorRecordOffsets: [Int]
}

private struct CPURegisterTriplet {
    let ix: UInt16
    let iy: UInt16
    let hl: UInt16
}

private struct ScoreEntry: Encodable {
    let frame: Int
    let activePlayer: Int
    let pointsUpper: Int
    let pointsLower: Int
    let firstScore: [Int]
    let secondScore: [Int]
}

private struct PendingScore {
    let frame: Int
    let activePlayer: UInt8
    let expected: CapturedScoreState
    var writes = 0
}

private struct ScoreComparison: Encodable {
    let calls: Int
    let matchingCalls: Int
    let firstPlayerCalls: Int
    let secondPlayerCalls: Int
    let frames: [Int]
}

private struct RNGWrite: Encodable {
    let frame: Int
    let instructionAddress: Int
    let previous: Int
    let value: Int
}

private struct ContactComparison: Encodable {
    let calls: Int
    let matchingCalls: Int
    let positiveFrames: [Int]
}

private struct PendingContact {
    let returnAddress: UInt16
    let frame: Int
    let predicted: Bool
}

private struct InjuryComparison: Encodable {
    let sourceUpdates: Int
    let matchingUpdates: Int
    let lifeDecrementFrames: [Int]
}

private struct MenuSequenceComparison: Encodable {
    let secondContactFrame: Int
    let menuSetupFrame: Int
    let menuReturnRoutineFrame: Int
}

private struct MenuRoutineComparison: Encodable {
    let setupFrames: [Int]
    let returnFrames: [Int]
}

private struct EnemyDirectionComparison: Encodable {
    let calls: Int
    let matchingCalls: Int
    let frames: [Int]
}

private struct ActiveEnemyComparison: Encodable {
    let sourceUpdates: Int
    let matchingUpdates: Int
    let countdownOnlyUpdates: Int
    let updateFrames: [Int]
}

private struct EnemyExpiryComparison: Encodable {
    let calls: Int
    let matchingCalls: Int
    let stoppedFrames: [Int]
    let resumedFrames: [Int]
}

private struct RNGStepComparison: Encodable {
    let refreshCalls: Int
    let clockCalls: Int
    let matchingWrites: Int
}

private struct PendingRNGStep {
    let writer: UInt16
    let predicted: UInt8
    let frame: Int
}

private struct PendingEnemyExpiry {
    let frame: Int
    let kind: UInt8
    let room: RoomID
    let velocityX: Int
    let velocityY: Int
    let rng: UInt8
    let clock: UInt8
}

private struct ActiveEnemyFrame {
    let kind: UInt8
    let timer: UInt8
    let room: RoomID
    let position: GridPoint
    let velocityX: Int
    let velocityY: Int

    init(_ memory: Memory) {
        let base: UInt16 = 0x9702 + 12 * 12
        kind = memory.read(base)
        timer = memory.read(base &+ 2)
        let roomID = Int(memory.read(base &+ 1))
        room = RoomID(roomID % 16, roomID / 16)
        position = GridPoint(
            Int(memory.read(base &+ 3)), Int(memory.read(base &+ 4))
        )
        velocityX = Int(Int8(bitPattern: memory.read(base &+ 6)))
        velocityY = Int(Int8(bitPattern: memory.read(base &+ 7)))
    }
}

private struct CodeCoverage: Encodable {
    let distinctROMInstructionStarts: Int
    let distinctRAMInstructionStarts: Int
    let ramInstructionStartSHA256: String
    let ramStartsByPage: [String: Int]
    let ramInstructionStarts: [Int]
}

private struct PendingEnemyDirection {
    let frame: Int
    let kind: UInt8
    let rng: UInt8
    let clock: UInt8
}

private struct PendingInjury {
    let expected: CapturedInjuryStep
    let frame: Int

    var isTerminal: Bool { expected.timer == 0 }
}

private struct Report: Encodable {
    let schemaVersion = 1
    let snapshotSHA256: String
    let romSHA256: String
    let framesCompared: Int
    let frameBoundaryMode: String
    let matchingRAMFrames: Int
    let firstRNGDifference: Difference?
    let firstMovingEntityDifference: Difference?
    let firstPlayerStateDifference: Difference?
    let firstPlayerPositionDifference: Difference?
    let trace: [TraceFrame]?
    let entitySlot: Int?
    let actorStateWrites: [ActorStateWrite]?
    let entityStateWrites: [EntityStateWrite]?
    let playerStateWrites: [EntityStateWrite]?
    let overlapAttributeWrites: [EntityStateWrite]?
    let overlapRegisterContext: [OverlapRegisterContext]?
    let scoreEntries: [ScoreEntry]?
    let scoreComparison: ScoreComparison?
    let rngFrames: [Int]?
    let rngWrites: [RNGWrite]?
    let contactComparison: ContactComparison?
    let injuryComparison: InjuryComparison?
    let menuSequence: MenuSequenceComparison?
    let menuRoutineFrames: MenuRoutineComparison?
    let enemyDirectionComparison: EnemyDirectionComparison?
    let activeEnemyComparison: ActiveEnemyComparison?
    let enemyExpiryComparison: EnemyExpiryComparison?
    let rngStepComparison: RNGStepComparison?
    let codeCoverage: CodeCoverage?
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
    default: throw DivergenceError.invalidSchedule
    }
}

private func schedule(_ data: Data, frames: Int) throws -> [Segment] {
    guard data.count <= 64_000 else { throw DivergenceError.invalidSchedule }
    let entries = try JSONDecoder().decode([Segment].self, from: data)
    guard !entries.isEmpty else { throw DivergenceError.invalidSchedule }
    var end = 0
    for entry in entries {
        guard entry.startFrame >= end, entry.endFrame > entry.startFrame,
              entry.endFrame <= frames else {
            throw DivergenceError.invalidSchedule
        }
        _ = try key(entry.key)
        end = entry.endFrame
    }
    return entries
}

private func playerState(_ memory: Memory) -> [Int] {
    let base: UInt16 = 0x9702
    return [0, 2, 5, 6, 7].map { Int(memory.read(base &+ UInt16($0))) }
}

private func playerPosition(_ memory: Memory) -> [Int] {
    let base: UInt16 = 0x9702
    return [1, 3, 4].map { Int(memory.read(base &+ UInt16($0))) }
}

private func movingEntity(_ memory: Memory) -> [Int] {
    let base: UInt16 = 0x9702 + 12 * 12
    return [0, 1, 3, 4].map { Int(memory.read(base &+ UInt16($0))) }
}

private func frameBoundary(currentCycle: Int, frame: Int, referenceTiming: Bool) -> Int {
    referenceTiming ? currentCycle + 69_888 : (frame + 1) * 69_888
}

@main
private struct SnapshotDivergence {
    static func main() {
        do {
            let arguments = CommandLine.arguments
            if arguments == [arguments[0], "--self-test"] {
                let valid = Data("""
                    [{"key":"w","startFrame":20,"endFrame":30},
                     {"key":"e","startFrame":30,"endFrame":100}]
                    """.utf8)
                guard try schedule(valid, frames: 100).count == 2 else {
                    throw DivergenceError.invalidSchedule
                }
                do {
                    _ = try schedule(valid, frames: 99)
                    throw DivergenceError.invalidSchedule
                } catch DivergenceError.invalidSchedule {}
                guard frameBoundary(currentCycle: 69_900, frame: 1, referenceTiming: true)
                        == 139_788,
                      frameBoundary(currentCycle: 69_900, frame: 1, referenceTiming: false)
                        == 139_776 else {
                    throw DivergenceError.invalidInput
                }
                print("SnapshotDivergence self-test passed")
                return
            }
            let options = Array(arguments.dropFirst(5))
            guard (5...25).contains(arguments.count),
                  options.allSatisfy({
                      ["--trace", "--trace-overlap-actor",
                       "--watch-actor-state", "--watch-entity-state",
                       "--watch-player-state", "--watch-menu-routines",
                       "--watch-score-entries", "--watch-overlap-attributes",
                       "--watch-overlap-registers",
                       "--reference-timing",
                       "--require-ram-parity", "--require-contact-parity",
                       "--require-first-injury-parity", "--require-menu-sequence",
                       "--coverage", "--require-entity-phase-parity",
                       "--require-enemy-expiry-parity",
                       "--require-rng-step-parity",
                       "--require-score-parity",
                       "--require-enemy-direction-parity"].contains($0)
                  }),
                  Set(options).count == options.count,
                  let count = Int(arguments[4]), (1...1800).contains(count),
                  !options.contains("--require-contact-parity")
                    || (options.contains("--reference-timing")
                        && options.contains("--require-ram-parity")),
                  !options.contains("--require-first-injury-parity")
                    || (options.contains("--reference-timing")
                        && options.contains("--require-ram-parity")),
                  !options.contains("--require-menu-sequence")
                    || (count >= 800 && options.contains("--reference-timing")
                        && options.contains("--require-ram-parity")
                        && options.contains("--require-contact-parity")),
                  !options.contains("--require-enemy-direction-parity")
                    || (options.contains("--reference-timing")
                        && options.contains("--require-ram-parity")),
                  !options.contains("--coverage")
                    || (options.contains("--reference-timing")
                        && options.contains("--require-ram-parity")),
                  !options.contains("--require-entity-phase-parity")
                    || (options.contains("--reference-timing")
                        && options.contains("--require-ram-parity")),
                  !options.contains("--require-enemy-expiry-parity")
                    || (options.contains("--reference-timing")
                        && options.contains("--require-ram-parity")),
                  !options.contains("--require-rng-step-parity")
                    || (options.contains("--reference-timing")
                        && options.contains("--require-ram-parity")),
                  !options.contains("--require-score-parity")
                    || (options.contains("--reference-timing")
                        && options.contains("--require-ram-parity")),
                  (!options.contains("--watch-overlap-attributes")
                    && !options.contains("--watch-overlap-registers"))
                    || (count == 100 && options.contains("--reference-timing")
                        && options.contains("--require-ram-parity")),
                  !options.contains("--trace-overlap-actor")
                    || (count == 100 && options.contains("--trace")
                        && options.contains("--reference-timing")
                        && options.contains("--require-ram-parity")) else {
                throw DivergenceError.usage
            }
            let includeTrace = options.contains("--trace")
            let traceOverlapActor = options.contains("--trace-overlap-actor")
            let watchActorState = options.contains("--watch-actor-state")
            let watchEntityState = options.contains("--watch-entity-state")
            let watchPlayerState = options.contains("--watch-player-state")
            let watchScoreEntries = options.contains("--watch-score-entries")
            let watchOverlapRegisters = options.contains("--watch-overlap-registers")
            let watchOverlapAttributes =
                options.contains("--watch-overlap-attributes") || watchOverlapRegisters
            let requireContactParity = options.contains("--require-contact-parity")
            let requireInjuryParity = options.contains("--require-first-injury-parity")
            let requireMenuSequence = options.contains("--require-menu-sequence")
            let watchMenuRoutines = options.contains("--watch-menu-routines")
            let requireEnemyDirectionParity = options.contains("--require-enemy-direction-parity")
            let includeCoverage = options.contains("--coverage")
            let requireEntityPhaseParity = options.contains("--require-entity-phase-parity")
            let requireEnemyExpiryParity = options.contains("--require-enemy-expiry-parity")
            let requireRNGStepParity = options.contains("--require-rng-step-parity")
            let requireScoreParity = options.contains("--require-score-parity")
            let referenceTiming = options.contains("--reference-timing")
            let rom = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
            let source = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
            let segments = try schedule(
                Data(contentsOf: URL(fileURLWithPath: arguments[3])), frames: count
            )
            if watchOverlapAttributes || traceOverlapActor {
                guard segments.count == 1, segments[0].key == "w",
                      segments[0].startFrame == 20,
                      segments[0].endFrame == 40 else {
                    throw DivergenceError.unsupportedOverlapSchedule
                }
            }
            let entityWorld: WorldReference?
            if requireEntityPhaseParity {
                guard let path = ProcessInfo.processInfo.environment["SABRE_PRIVATE_WORLD"]
                else { throw DivergenceError.missingWorld }
                entityWorld = try WorldReference.load(
                    from: Data(contentsOf: URL(fileURLWithPath: path))
                )
            } else {
                entityWorld = nil
            }
            guard hash(rom) == "d55daa439b673b0e3f5897f99ac37ecb45f974d1862b4dadb85dec34af99cb42",
                  hash(source) == "803e4197989c73408cfc5113f8f30c81ac0269958aa9e105b474b6f52437203c",
                  let snapshot = try? Z80Snapshot.load(from: source),
                  snapshot.ram128Banks == nil,
                  snapshot.ram48.count == 49_152 else {
                throw DivergenceError.invalidInput
            }

            let savedOutput = dup(STDOUT_FILENO)
            guard savedOutput >= 0 else { throw DivergenceError.invalidInput }
            fflush(stdout)
            guard dup2(STDERR_FILENO, STDOUT_FILENO) >= 0 else {
                close(savedOutput)
                throw DivergenceError.invalidInput
            }
            let manual = Speccy48Emulator(rom: [UInt8](rom))
            let full = Speccy48Emulator(rom: [UInt8](rom))
            fflush(stdout)
            guard dup2(savedOutput, STDOUT_FILENO) >= 0 else {
                close(savedOutput)
                throw DivergenceError.invalidInput
            }
            close(savedOutput)
            manual.apply(snapshot: snapshot)
            full.apply(snapshot: snapshot)
            var cpu = manual.cpu
            var memory = manual.mem
            var cycles = 0
            var nextInterrupt = 69_888
            var active: KeyboardMatrix.Key?
            var firstRNG: Difference?
            var firstEntity: Difference?
            var firstState: Difference?
            var firstPosition: Difference?
            var trace: [TraceFrame] = []
            var actorStateWrites: [ActorStateWrite] = []
            var entityStateWrites: [EntityStateWrite] = []
            var playerStateWrites: [EntityStateWrite] = []
            var overlapAttributeWrites: [EntityStateWrite] = []
            var overlapRegisterContext: [OverlapRegisterContext] = []
            var overlapAttributeWriteBudgetExceeded = false
            var scoreEntries: [ScoreEntry] = []
            var pendingScore: PendingScore?
            var matchingScoreCalls = 0
            var firstPlayerScoreCalls = 0
            var secondPlayerScoreCalls = 0
            var scoreFrames: [Int] = []
            var rngFrames: [Int] = []
            var rngWrites: [RNGWrite] = []
            var matchingRAMFrames = 0
            var pendingContacts: [PendingContact] = []
            var contactCalls = 0
            var matchingContactCalls = 0
            var positiveContactFrames: [Int] = []
            var pendingInjury: PendingInjury?
            var injuryUpdates = 0
            var matchingInjuryUpdates = 0
            var lifeDecrementFrames: [Int] = []
            var menuSetupFrames: [Int] = []
            var menuReturnFrames: [Int] = []
            var pendingEnemyDirection: PendingEnemyDirection?
            var enemyDirectionCalls = 0
            var enemyDirectionFrames: [Int] = []
            var ramInstructionStarts: Set<UInt16> = []
            var romInstructionStarts: Set<UInt16> = []
            var previousReferenceEnemy = ActiveEnemyFrame(full.mem)
            var activeEnemyUpdates = 0
            var matchingActiveEnemyUpdates = 0
            var countdownOnlyUpdates = 0
            var activeEnemyFrames: [Int] = []
            var pendingEnemyExpiry: PendingEnemyExpiry?
            var enemyExpiryCalls = 0
            var enemyStoppedFrames: [Int] = []
            var enemyResumedFrames: [Int] = []
            var pendingRNGStep: PendingRNGStep?
            var refreshCalls = 0
            var clockCalls = 0

            for frame in 0..<count {
                let pressed = try segments.first(where: {
                    $0.startFrame <= frame && frame < $0.endFrame
                }).map { try key($0.key) }
                if pressed != active {
                    if let active {
                        manual.keyboard.release(active)
                        full.keyboard.release(active)
                    }
                    if let pressed {
                        manual.keyboard.press(pressed)
                        full.keyboard.press(pressed)
                    }
                    active = pressed
                }
                let boundary = frameBoundary(
                    currentCycle: cycles, frame: frame, referenceTiming: referenceTiming
                )
                var steps = 0
                while cycles < boundary {
                    if requireScoreParity, cpu.pc == 0xB5A9 {
                        guard pendingScore == nil else {
                            throw DivergenceError.scoreMismatch(frame: frame + 1)
                        }
                        var expected = CapturedScoreState(
                            first: try CapturedPackedScore(bytes:
                                (0x9698...0x969A).map { memory.read(UInt16($0)) }
                            ),
                            second: try CapturedPackedScore(bytes:
                                (0x969B...0x969D).map { memory.read(UInt16($0)) }
                            )
                        )
                        let active = memory.read(0x969E)
                        try expected.add(
                            activePlayer: active, pointsUpper: cpu.b, pointsLower: cpu.c
                        )
                        pendingScore = PendingScore(
                            frame: frame + 1, activePlayer: active, expected: expected
                        )
                    }
                    if watchScoreEntries, cpu.pc == 0xB5A9 {
                        scoreEntries.append(ScoreEntry(
                            frame: frame + 1,
                            activePlayer: Int(memory.read(0x969E)),
                            pointsUpper: Int(cpu.b), pointsLower: Int(cpu.c),
                            firstScore: (0x9698...0x969A).map {
                                Int(memory.read(UInt16($0)))
                            },
                            secondScore: (0x969B...0x969D).map {
                                Int(memory.read(UInt16($0)))
                            }
                        ))
                    }
                    if requireRNGStepParity {
                        if cpu.pc == 0x99D6 {
                            pendingRNGStep = PendingRNGStep(
                                writer: 0x99D7,
                                predicted: CapturedRNGStep.refresh(
                                    previous: memory.read(0x9695),
                                    refreshOperand: cpu.c, carry: cpu.f & 1 != 0
                                ),
                                frame: frame + 1
                            )
                        } else if cpu.pc == 0x9A24 {
                            pendingRNGStep = PendingRNGStep(
                                writer: 0x9A2D,
                                predicted: CapturedRNGStep.clock(
                                    previous: memory.read(0x9695),
                                    counterLowByte: cpu.l,
                                    clockByte: memory.read(0x5C78)
                                ),
                                frame: frame + 1
                            )
                        }
                    }
                    if requireEnemyExpiryParity, cpu.ix == 0x9792 {
                        if cpu.pc == 0xA56A, memory.read(0x9793) == 152,
                           memory.read(0x9794) == 1,
                           (108...111).contains(Int(memory.read(0x9792))) {
                            let vx = Int(Int8(bitPattern: memory.read(0x9798)))
                            let vy = Int(Int8(bitPattern: memory.read(0x9799)))
                            if (vx == 0 && vy == 0)
                                || ([-80, -48, 48, 96].contains(vx) && vy == 80) {
                                pendingEnemyExpiry = PendingEnemyExpiry(
                                    frame: frame + 1, kind: memory.read(0x9792),
                                    room: RoomID(8, 9), velocityX: vx, velocityY: vy,
                                    rng: memory.read(0x9695), clock: memory.read(0x5C78)
                                )
                            }
                        } else if cpu.pc == 0xA570, let old = pendingEnemyExpiry {
                            pendingEnemyExpiry = nil
                            let predicted = try CapturedEnemyExpiry.resolve(
                                kind: old.kind, timer: 1, room: old.room,
                                velocityX: old.velocityX, velocityY: old.velocityY,
                                rngByte: old.rng, clockByte: old.clock
                            )
                            enemyExpiryCalls += 1
                            guard memory.read(0x9792) == predicted.kind,
                                  memory.read(0x9794) == predicted.timer,
                                  Int(Int8(bitPattern: memory.read(0x9798)))
                                    == predicted.velocityX,
                                  Int(Int8(bitPattern: memory.read(0x9799)))
                                    == predicted.velocityY else {
                                throw DivergenceError.enemyExpiryMismatch(frame: old.frame)
                            }
                            if old.velocityX == 0 && old.velocityY == 0 {
                                enemyResumedFrames.append(old.frame)
                            } else {
                                enemyStoppedFrames.append(old.frame)
                            }
                        }
                    }
                    if requireEnemyDirectionParity {
                        if cpu.pc == 0xA5D5, cpu.ix == 0x9792,
                           memory.read(0x9793) == 152,
                           (108...111).contains(Int(memory.read(0x9792))) {
                            pendingEnemyDirection = PendingEnemyDirection(
                                frame: frame + 1, kind: memory.read(0x9792),
                                rng: memory.read(0x9695), clock: memory.read(0x5C78)
                            )
                        } else if cpu.pc == 0xA5FA, cpu.ix == 0x9792,
                                  let observed = pendingEnemyDirection {
                            pendingEnemyDirection = nil
                            let predicted = try CapturedEnemyDirection.choose(
                                kind: observed.kind, rngByte: observed.rng,
                                clockByte: observed.clock
                            )
                            enemyDirectionCalls += 1
                            guard memory.read(0x9792) == predicted.kind,
                                  Int(Int8(bitPattern: memory.read(0x9798)))
                                    == predicted.velocityX,
                                  Int(Int8(bitPattern: memory.read(0x9799)))
                                    == predicted.velocityY else {
                                throw DivergenceError.enemyDirectionMismatch(
                                    frame: observed.frame
                                )
                            }
                            enemyDirectionFrames.append(observed.frame)
                        }
                    }
                    if requireMenuSequence || watchMenuRoutines {
                        if cpu.pc == 0xAA6A { menuSetupFrames.append(frame + 1) }
                        if cpu.pc == 0xAAAD { menuReturnFrames.append(frame + 1) }
                    }
                    if requireInjuryParity {
                        if cpu.pc == 0xAA10 {
                            let kind = memory.read(0x9702)
                            let life = memory.read(0x96BD)
                            let expected: CapturedInjuryStep?
                            if kind == 65, (1...4).contains(Int(life)) {
                                expected = try CapturedFirstInjuryTick.advance(
                                    kind: kind, timer: memory.read(0x9704),
                                    lifeByte: life
                                )
                            } else if kind == 69, life == 1,
                                      memory.read(0x9703) == 168,
                                      memory.read(0x9705) == 56,
                                      memory.read(0x9706) == 112 {
                                expected = try CapturedFinalInjuryTick.advance(
                                    kind: kind, timer: memory.read(0x9704),
                                    lifeByte: life, room: RoomID(8, 10),
                                    x: 56, y: 112
                                )
                            } else {
                                expected = nil
                            }
                            if let expected {
                                pendingInjury = PendingInjury(
                                    expected: expected, frame: frame + 1
                                )
                            }
                        } else if let injury = pendingInjury,
                                  cpu.pc == (injury.isTerminal ? 0xAA45 : 0xAA57) {
                            pendingInjury = nil
                            injuryUpdates += 1
                            guard memory.read(0x9702) == injury.expected.kind,
                                  memory.read(0x9704) == injury.expected.timer,
                                  memory.read(0x96BD) == injury.expected.lifeByte else {
                                throw DivergenceError.injuryMismatch(frame: injury.frame)
                            }
                            matchingInjuryUpdates += 1
                            if injury.isTerminal {
                                lifeDecrementFrames.append(injury.frame)
                            }
                        }
                    }
                    if requireContactParity {
                        if cpu.pc == 0xAB36 {
                            let other = cpu.ix
                            let returnAddress = UInt16(memory.read(cpu.sp))
                                | (UInt16(memory.read(cpu.sp &+ 1)) << 8)
                            let predicted = CapturedActorContact.overlaps(
                                playerKind: memory.read(0x9702),
                                playerRoom: memory.read(0x9703),
                                playerX: memory.read(0x9705),
                                playerY: memory.read(0x9706),
                                playerByte5: memory.read(0x9707),
                                suppressionFlag: memory.read(0x96B5),
                                otherRoom: memory.read(other &+ 1),
                                otherX: memory.read(other &+ 3),
                                otherY: memory.read(other &+ 4),
                                playerRightReach: cpu.c,
                                playerAboveReach: cpu.b
                            )
                            pendingContacts.append(PendingContact(
                                returnAddress: returnAddress,
                                frame: frame + 1, predicted: predicted
                            ))
                        } else if let contact = pendingContacts.last,
                                  cpu.pc == contact.returnAddress {
                            pendingContacts.removeLast()
                            let actual = cpu.f & 1 != 0
                            contactCalls += 1
                            guard contact.predicted == actual else {
                                throw DivergenceError.contactMismatch(
                                    frame: contact.frame, predicted: contact.predicted,
                                    actual: actual
                                )
                            }
                            matchingContactCalls += 1
                            if actual { positiveContactFrames.append(contact.frame) }
                        }
                    }
                    let instructionAddress = Int(cpu.pc)
                    let writeRegisters: CPURegisterTriplet? =
                        watchOverlapRegisters
                            ? CPURegisterTriplet(
                                ix: cpu.ix, iy: cpu.iy,
                                hl: UInt16(cpu.h) << 8 | UInt16(cpu.l)
                            ) : nil
                    if includeCoverage {
                        if cpu.pc >= 0x4000 {
                            ramInstructionStarts.insert(cpu.pc)
                        } else {
                            romInstructionStarts.insert(cpu.pc)
                        }
                    }
                    let result = cpu.step(
                        read: { memory.read($0) },
                        write: { address, value in
                            if watchActorState && (address == 0x9702 || address == 0x9792) {
                                let previous = memory.read(address)
                                if previous != value {
                                    actorStateWrites.append(ActorStateWrite(
                                        frame: frame + 1,
                                        instructionAddress: instructionAddress,
                                        actorAddress: Int(address),
                                        previous: Int(previous),
                                        value: Int(value),
                                        rngValue: Int(memory.read(0x9695))
                                    ))
                                }
                            }
                            if watchActorState && address == 0x9695 {
                                let previous = memory.read(address)
                                if previous != value {
                                    rngWrites.append(RNGWrite(
                                        frame: frame + 1,
                                        instructionAddress: instructionAddress,
                                        previous: Int(previous),
                                        value: Int(value)
                                    ))
                                }
                            }
                            if watchEntityState && (0x9792...0x9799).contains(address) {
                                let previous = memory.read(address)
                                if previous != value {
                                    entityStateWrites.append(EntityStateWrite(
                                        frame: frame + 1,
                                        instructionAddress: instructionAddress,
                                        cycle: cycles,
                                        address: Int(address),
                                        previous: Int(previous),
                                        value: Int(value)
                                    ))
                                }
                            }
                            if watchPlayerState
                                && ((0x9702...0x9709).contains(address)
                                    || address == 0x96BD) {
                                let previous = memory.read(address)
                                if previous != value {
                                    playerStateWrites.append(EntityStateWrite(
                                        frame: frame + 1,
                                        instructionAddress: instructionAddress,
                                        cycle: cycles,
                                        address: Int(address),
                                        previous: Int(previous),
                                        value: Int(value)
                                    ))
                                }
                            }
                            if watchOverlapAttributes && (40...55).contains(frame + 1),
                               (0x5800...0x5AFF).contains(address) {
                                let offset = Int(address) - 0x5800
                                if (10...12).contains(offset / 32),
                                   (14...17).contains(offset % 32) {
                                    if overlapAttributeWrites.count == 4096 {
                                        overlapAttributeWriteBudgetExceeded = true
                                    } else {
                                        overlapAttributeWrites.append(EntityStateWrite(
                                            frame: frame + 1,
                                            instructionAddress: instructionAddress,
                                            cycle: cycles,
                                            address: Int(address),
                                            previous: Int(memory.read(address)),
                                            value: Int(value)
                                        ))
                                        if let writeRegisters {
                                            let base = writeRegisters.ix
                                            overlapRegisterContext.append(
                                                OverlapRegisterContext(
                                                    ix: Int(base),
                                                    iy: Int(writeRegisters.iy),
                                                    hl: Int(writeRegisters.hl),
                                                    matchingActorRecordOffsets: (0..<12)
                                                        .filter { offset in
                                                            memory.read(base &+ UInt16(offset))
                                                                == value
                                                        }
                                                )
                                            )
                                        }
                                    }
                                }
                            }
                            if requireScoreParity, pendingScore != nil,
                               (0x9698...0x969D).contains(address) {
                                pendingScore?.writes += 1
                            }
                            memory.write(address, value)
                        },
                        ioRead: { port in
                            port & 1 == 0
                                ? manual.keyboard.readPortFE(highByte: UInt8(port >> 8))
                                : 0xFF
                        },
                        ioWrite: { _, _ in }
                    )
                    steps += 1
                    guard steps <= 100_000 else { throw DivergenceError.stepBudget }
                    switch result {
                    case .ok(let cost): cycles += cost
                    case .unimplemented: throw DivergenceError.unimplemented
                    }
                    if overlapAttributeWriteBudgetExceeded {
                        throw DivergenceError.attributeWriteBudget
                    }
                    if requireScoreParity, let pending = pendingScore,
                       pending.writes == 3 {
                        let actual = CapturedScoreState(
                            first: try CapturedPackedScore(bytes:
                                (0x9698...0x969A).map { memory.read(UInt16($0)) }
                            ),
                            second: try CapturedPackedScore(bytes:
                                (0x969B...0x969D).map { memory.read(UInt16($0)) }
                            )
                        )
                        guard actual == pending.expected else {
                            throw DivergenceError.scoreMismatch(frame: pending.frame)
                        }
                        matchingScoreCalls += 1
                        if pending.activePlayer == 0 {
                            firstPlayerScoreCalls += 1
                        } else {
                            secondPlayerScoreCalls += 1
                        }
                        scoreFrames.append(pending.frame)
                        pendingScore = nil
                    }
                    if requireScoreParity, let pendingScore,
                       pendingScore.writes > 3 {
                        throw DivergenceError.scoreMismatch(frame: pendingScore.frame)
                    }
                    if requireRNGStepParity,
                       instructionAddress == 0x99D7 || instructionAddress == 0x9A2D {
                        guard let pending = pendingRNGStep,
                              pending.writer == instructionAddress,
                              memory.read(0x9695) == pending.predicted else {
                            throw DivergenceError.rngStepMismatch(frame: frame + 1)
                        }
                        if instructionAddress == 0x99D7 {
                            refreshCalls += 1
                        } else {
                            clockCalls += 1
                        }
                        pendingRNGStep = nil
                    }
                    while cycles >= nextInterrupt {
                        cycles += cpu.acceptMaskableInterrupt(
                            read: { memory.read($0) },
                            write: { memory.write($0, $1) }
                        )
                        nextInterrupt += 69_888
                    }
                }
                full.stepFrame()
                guard full.unimplementedCount == 0 else {
                    throw DivergenceError.unimplemented
                }
                let index = frame + 1
                let reference = full.mem
                if let entityWorld {
                    let current = ActiveEnemyFrame(reference)
                    let old = previousReferenceEnemy
                    if (108...111).contains(Int(old.kind)),
                       (108...111).contains(Int(current.kind)),
                       old.room == RoomID(8, 9), current.room == old.room,
                       (2...15).contains(Int(old.timer)),
                       [-80, -48, 48, 96].contains(old.velocityX),
                       old.velocityY == 80 {
                        var predicted = try CapturedActiveEnemyState(
                            kind: old.kind, timer: old.timer, room: old.room,
                            position: old.position,
                            velocityX: old.velocityX, velocityY: old.velocityY
                        )
                        let moved = old.position != current.position
                        let countdown = old.timer != current.timer
                        if moved || countdown || old.kind != current.kind {
                            if moved {
                                try predicted.advanceOnSourceUpdate(
                                    world: entityWorld, countdownOccurred: countdown
                                )
                            } else if countdown {
                                try predicted.advanceCountdownOnSourceUpdate()
                            }
                            guard predicted.kind == current.kind,
                                  predicted.timer == current.timer,
                                  predicted.position == current.position else {
                                throw DivergenceError.enemyStateMismatch(
                                    frame: index,
                                    expected: [Int(predicted.kind), Int(predicted.timer),
                                               predicted.position.x, predicted.position.y],
                                    actual: [Int(current.kind), Int(current.timer),
                                             current.position.x, current.position.y]
                                )
                            }
                            if moved {
                                activeEnemyUpdates += 1
                                matchingActiveEnemyUpdates += 1
                                activeEnemyFrames.append(index)
                            } else {
                                countdownOnlyUpdates += 1
                            }
                        }
                    }
                    previousReferenceEnemy = current
                }
                if memory.exportRam48K() == reference.exportRam48K() {
                    matchingRAMFrames += 1
                }
                if watchActorState {
                    rngFrames.append(Int(reference.read(0x9695)))
                }
                let manualRNG = [Int(memory.read(0x9695))]
                let fullRNG = [Int(reference.read(0x9695))]
                if firstRNG == nil && manualRNG != fullRNG {
                    firstRNG = Difference(frame: index, manual: manualRNG, fullEmulator: fullRNG)
                }
                let manualEntity = movingEntity(memory)
                let fullEntity = movingEntity(reference)
                if firstEntity == nil && manualEntity != fullEntity {
                    firstEntity = Difference(
                        frame: index, manual: manualEntity, fullEmulator: fullEntity
                    )
                }
                let manualState = playerState(memory)
                let fullState = playerState(reference)
                if firstState == nil && manualState != fullState {
                    firstState = Difference(
                        frame: index, manual: manualState, fullEmulator: fullState
                    )
                }
                let manualPosition = playerPosition(memory)
                let fullPosition = playerPosition(reference)
                if firstPosition == nil && manualPosition != fullPosition {
                    firstPosition = Difference(
                        frame: index, manual: manualPosition, fullEmulator: fullPosition
                    )
                }
                if includeTrace {
                    trace.append(TraceFrame(
                        index: index,
                        manualEntity: EntityMarker(
                            memory, slot: traceOverlapActor ? 18 : 12
                        ),
                        fullEmulatorEntity: EntityMarker(
                            reference, slot: traceOverlapActor ? 18 : 12
                        ),
                        manualPlayer: ActorMarker(memory),
                        fullEmulatorPlayer: ActorMarker(reference)
                    ))
                }
            }
            if options.contains("--require-ram-parity"), matchingRAMFrames != count {
                throw DivergenceError.ramMismatch(matching: matchingRAMFrames, total: count)
            }
            if requireEntityPhaseParity && activeEnemyUpdates == 0 {
                throw DivergenceError.noActiveEnemyUpdates
            }
            if requireEnemyExpiryParity {
                guard pendingEnemyExpiry == nil else {
                    throw DivergenceError.unfinishedEnemyExpiry
                }
                if requireRNGStepParity {
                    guard pendingRNGStep == nil, refreshCalls > 0, clockCalls > 0 else {
                        throw DivergenceError.rngStepMismatch(frame: count)
                    }
                    if requireScoreParity {
                        guard pendingScore == nil, matchingScoreCalls > 0 else {
                            throw DivergenceError.scoreMismatch(frame: count)
                        }
                    }
                }
                guard enemyExpiryCalls > 0 else {
                    throw DivergenceError.noEnemyExpiryEvents
                }
            }
            guard (!requireContactParity || pendingContacts.isEmpty),
                  (!requireInjuryParity || pendingInjury == nil),
                  (!requireEnemyDirectionParity || pendingEnemyDirection == nil) else {
                throw DivergenceError.invalidInput
            }
            if requireMenuSequence {
                guard positiveContactFrames.count == 2,
                      menuSetupFrames == [positiveContactFrames[1] + 68],
                      menuReturnFrames == [positiveContactFrames[1] + 199] else {
                    throw DivergenceError.menuSequenceMismatch
                }
            }
            let coverage: CodeCoverage?
            if includeCoverage {
                let starts = ramInstructionStarts.sorted().map(Int.init)
                var addressBytes = Data()
                var byPage: [String: Int] = [:]
                for address in starts {
                    addressBytes.append(UInt8(truncatingIfNeeded: address))
                    addressBytes.append(UInt8(truncatingIfNeeded: address >> 8))
                    byPage[String(format: "0x%02X", address >> 8), default: 0] += 1
                }
                coverage = CodeCoverage(
                    distinctROMInstructionStarts: romInstructionStarts.count,
                    distinctRAMInstructionStarts: starts.count,
                    ramInstructionStartSHA256: hash(addressBytes),
                    ramStartsByPage: byPage,
                    ramInstructionStarts: starts
                )
            } else {
                coverage = nil
            }
            let report = Report(
                snapshotSHA256: hash(source),
                romSHA256: hash(rom),
                framesCompared: count,
                frameBoundaryMode: referenceTiming ? "reference-relative" : "absolute",
                matchingRAMFrames: matchingRAMFrames,
                firstRNGDifference: firstRNG,
                firstMovingEntityDifference: firstEntity,
                firstPlayerStateDifference: firstState,
                firstPlayerPositionDifference: firstPosition,
                trace: includeTrace ? trace : nil,
                entitySlot: traceOverlapActor ? 18 : nil,
                actorStateWrites: watchActorState ? actorStateWrites : nil,
                entityStateWrites: watchEntityState ? entityStateWrites : nil,
                playerStateWrites: watchPlayerState ? playerStateWrites : nil,
                overlapAttributeWrites: watchOverlapAttributes
                    ? overlapAttributeWrites : nil,
                overlapRegisterContext: watchOverlapRegisters
                    ? overlapRegisterContext : nil,
                scoreEntries: watchScoreEntries ? scoreEntries : nil,
                scoreComparison: requireScoreParity
                    ? ScoreComparison(
                        calls: matchingScoreCalls, matchingCalls: matchingScoreCalls,
                        firstPlayerCalls: firstPlayerScoreCalls,
                        secondPlayerCalls: secondPlayerScoreCalls,
                        frames: scoreFrames
                    ) : nil,
                rngFrames: watchActorState ? rngFrames : nil,
                rngWrites: watchActorState ? rngWrites : nil,
                contactComparison: requireContactParity
                    ? ContactComparison(
                        calls: contactCalls, matchingCalls: matchingContactCalls,
                        positiveFrames: positiveContactFrames
                    ) : nil,
                injuryComparison: requireInjuryParity
                    ? InjuryComparison(
                        sourceUpdates: injuryUpdates,
                        matchingUpdates: matchingInjuryUpdates,
                        lifeDecrementFrames: lifeDecrementFrames
                    ) : nil,
                menuSequence: requireMenuSequence
                    ? MenuSequenceComparison(
                        secondContactFrame: positiveContactFrames[1],
                        menuSetupFrame: menuSetupFrames[0],
                        menuReturnRoutineFrame: menuReturnFrames[0]
                    ) : nil,
                menuRoutineFrames: watchMenuRoutines
                    ? MenuRoutineComparison(
                        setupFrames: menuSetupFrames,
                        returnFrames: menuReturnFrames
                    ) : nil,
                enemyDirectionComparison: requireEnemyDirectionParity
                    ? EnemyDirectionComparison(
                        calls: enemyDirectionCalls, matchingCalls: enemyDirectionCalls,
                        frames: enemyDirectionFrames
                    ) : nil,
                activeEnemyComparison: requireEntityPhaseParity
                    ? ActiveEnemyComparison(
                        sourceUpdates: activeEnemyUpdates,
                        matchingUpdates: matchingActiveEnemyUpdates,
                        countdownOnlyUpdates: countdownOnlyUpdates,
                        updateFrames: activeEnemyFrames
                    ) : nil,
                enemyExpiryComparison: requireEnemyExpiryParity
                    ? EnemyExpiryComparison(
                        calls: enemyExpiryCalls, matchingCalls: enemyExpiryCalls,
                        stoppedFrames: enemyStoppedFrames,
                        resumedFrames: enemyResumedFrames
                    ) : nil,
                rngStepComparison: requireRNGStepParity
                    ? RNGStepComparison(
                        refreshCalls: refreshCalls, clockCalls: clockCalls,
                        matchingWrites: refreshCalls + clockCalls
                    ) : nil,
                codeCoverage: coverage
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(report))
            FileHandle.standardOutput.write(Data([0x0A]))
        } catch {
            fputs("SnapshotDivergence: \(error)\n", stderr)
            exit(1)
        }
    }
}
