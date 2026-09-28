import CryptoKit
import Darwin
import Foundation

private enum DivergenceError: Error, CustomStringConvertible {
    case usage
    case invalidSchedule
    case invalidInput
    case missingWorld
    case noActiveEnemyUpdates
    case stepBudget
    case unimplemented
    case ramMismatch(matching: Int, total: Int)
    case contactMismatch(frame: Int, predicted: Bool, actual: Bool)
    case injuryMismatch(frame: Int)
    case menuSequenceMismatch
    case enemyDirectionMismatch(frame: Int)
    case enemyStateMismatch(frame: Int, expected: [Int], actual: [Int])

    var description: String {
        switch self {
        case .usage:
            "Usage: SnapshotDivergence <48k.rom> <gameplay.z80> <schedule.json> <frames: 1...900> [--trace] [--watch-actor-state] [--reference-timing] [--require-ram-parity] [--require-contact-parity] [--require-first-injury-parity] [--require-menu-sequence] [--require-enemy-direction-parity] [--require-entity-phase-parity (SABRE_PRIVATE_WORLD required)] [--coverage] | --self-test"
        case .invalidSchedule:
            "Schedule intervals must be sorted, nonoverlapping and within the frame count"
        case .invalidInput:
            "Expected a verified 48K ROM and gameplay snapshot"
        case .missingWorld:
            "Set SABRE_PRIVATE_WORLD to the ignored, verified version-2 world JSON"
        case .noActiveEnemyUpdates:
            "The entity-phase parity gate found no eligible moving slot-12 updates"
        case .stepBudget:
            "Manual CPU run exceeded 100000 instructions in one frame"
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

    init(_ memory: Memory) {
        let base: UInt16 = 0x9702 + 12 * 12
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
    let actorStateWrites: [ActorStateWrite]?
    let rngFrames: [Int]?
    let rngWrites: [RNGWrite]?
    let contactComparison: ContactComparison?
    let injuryComparison: InjuryComparison?
    let menuSequence: MenuSequenceComparison?
    let enemyDirectionComparison: EnemyDirectionComparison?
    let activeEnemyComparison: ActiveEnemyComparison?
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
            guard (5...15).contains(arguments.count),
                  options.allSatisfy({
                      ["--trace", "--watch-actor-state", "--reference-timing",
                       "--require-ram-parity", "--require-contact-parity",
                       "--require-first-injury-parity", "--require-menu-sequence",
                       "--coverage", "--require-entity-phase-parity",
                       "--require-enemy-direction-parity"].contains($0)
                  }),
                  Set(options).count == options.count,
                  let count = Int(arguments[4]), (1...900).contains(count),
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
                        && options.contains("--require-ram-parity")) else {
                throw DivergenceError.usage
            }
            let includeTrace = options.contains("--trace")
            let watchActorState = options.contains("--watch-actor-state")
            let requireContactParity = options.contains("--require-contact-parity")
            let requireInjuryParity = options.contains("--require-first-injury-parity")
            let requireMenuSequence = options.contains("--require-menu-sequence")
            let requireEnemyDirectionParity = options.contains("--require-enemy-direction-parity")
            let includeCoverage = options.contains("--coverage")
            let requireEntityPhaseParity = options.contains("--require-entity-phase-parity")
            let referenceTiming = options.contains("--reference-timing")
            let rom = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
            let source = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
            let segments = try schedule(
                Data(contentsOf: URL(fileURLWithPath: arguments[3])), frames: count
            )
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
                    if requireMenuSequence {
                        if cpu.pc == 0xAA6A { menuSetupFrames.append(frame + 1) }
                        if cpu.pc == 0xAAAD { menuReturnFrames.append(frame + 1) }
                    }
                    if requireInjuryParity {
                        if cpu.pc == 0xAA10,
                           memory.read(0x9702) == 65,
                           memory.read(0x96BD) == 1 {
                            let expected = try CapturedFirstInjuryTick.advance(
                                kind: memory.read(0x9702),
                                timer: memory.read(0x9704),
                                lifeByte: memory.read(0x96BD)
                            )
                            pendingInjury = PendingInjury(
                                expected: expected, frame: frame + 1
                            )
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
                        manualEntity: EntityMarker(memory),
                        fullEmulatorEntity: EntityMarker(reference),
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
                actorStateWrites: watchActorState ? actorStateWrites : nil,
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
