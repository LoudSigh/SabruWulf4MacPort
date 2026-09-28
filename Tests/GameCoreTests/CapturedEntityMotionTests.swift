import Foundation
import XCTest
@testable import GameCore

final class CapturedEntityMotionTests: XCTestCase {
    private func world() throws -> WorldReference {
        let rooms: [[String: Any]] = (0..<48).map { _ in
            ["placements": [[
                "graphicAddress": 0x70BC, "x": 80, "y": 136,
                "widthPixels": 80, "heightPixels": 8,
            ]]]
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 2,
            "snapshotSha256": WorldReference.supportedSnapshotSHA256,
            "width": 16, "height": 16,
            "layout": Array(repeating: 0, count: 256),
            "rooms": rooms,
        ])
        return try WorldReference.load(from: data, verifySource: false)
    }

    func testSourceVelocityAndStaticYBlockAreIndependentOfDirection() throws {
        let world = try world()
        for (kind, velocity, expectedX) in [
            (UInt8(110), 96, 98), (UInt8(111), 48, 95),
            (UInt8(108), -48, 89),
        ] {
            let first = try CapturedEntityMotion.advanceOnSourceUpdate(
                kind: kind, room: RoomID(8, 9), from: GridPoint(92, 130),
                velocityX: velocity, velocityY: 80, world: world
            )
            XCTAssertEqual(first, GridPoint(expectedX, 135))
            let second = try CapturedEntityMotion.advanceOnSourceUpdate(
                kind: kind, room: RoomID(8, 9), from: first,
                velocityX: velocity, velocityY: 80, world: world
            )
            XCTAssertEqual(second, GridPoint(expectedX + velocity / 16, 135))
        }
    }

    func testRejectsUnobservedEntityMotion() throws {
        let source = try world()
        for (kind, room, velocityX, velocityY) in [
            (UInt8(8), RoomID(8, 9), 96, 80),
            (UInt8(108), RoomID(8, 10), 96, 80),
            (UInt8(108), RoomID(8, 9), 64, 80),
            (UInt8(108), RoomID(8, 9), 96, 64),
        ] {
            XCTAssertThrowsError(try CapturedEntityMotion.advanceOnSourceUpdate(
                kind: kind, room: room, from: GridPoint(92, 130),
                velocityX: velocityX, velocityY: velocityY, world: source
            )) { error in
                guard case CapturedEntityMotionError.unsupportedState = error else {
                    return XCTFail("Unexpected entity-motion error: \(error)")
                }
            }
        }
    }

    func testPrivateEnemyMovesAgainstReferenceWhenProvided() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let worldPath = environment["SABRE_PRIVATE_WORLD"],
              let directory = environment["SABRE_PRIVATE_ENTITY_TRACE_DIR"] else {
            throw XCTSkip("Set private world and reference encounter traces")
        }
        let source = try WorldReference.load(
            from: Data(contentsOf: URL(fileURLWithPath: worldPath))
        )
        var checked = 0
        for (scenario, velocity) in [
            ("no-fire-encounter", 96),
            ("unrelated-a-control", 48),
            ("fire-before-contact", -48),
        ] {
            let base = URL(fileURLWithPath: directory)
            let trace = try ReferenceEntityTrace.load(from: Data(contentsOf:
                base.appendingPathComponent("trace-\(scenario)-190.json")
            ))
            let replay = try ReferenceReplay.load(from: Data(contentsOf:
                base.appendingPathComponent("replay-\(scenario)-190.json")
            ))
            try trace.validate(replay: replay)
            for pair in zip(trace.trace, trace.trace.dropFirst()) {
                let old = pair.0.fullEmulatorEntity
                let current = pair.1.fullEmulatorEntity
                guard (108...111).contains(old.kind),
                      (108...111).contains(current.kind),
                      old.roomID == 152, current.roomID == 152,
                      old.x != current.x || old.y != current.y else {
                    continue
                }
                let next = try CapturedEntityMotion.advanceOnSourceUpdate(
                    kind: UInt8(old.kind), room: RoomID(8, 9),
                    from: GridPoint(old.x, old.y),
                    velocityX: velocity, velocityY: 80, world: source
                )
                XCTAssertEqual(
                    next, GridPoint(current.x, current.y),
                    "\(scenario) enemy at frame \(pair.1.index)"
                )
                checked += 1
            }
        }
        XCTAssertEqual(checked, 14)
    }
}
