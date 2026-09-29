import Foundation
import XCTest
@testable import GameCore

final class CapturedSlot12KindSequenceTests: XCTestCase {
    func testBoundedKindSequenceAndRejections() throws {
        var kind: UInt8 = 109
        for expected: UInt8 in [8, 9, 10, 11, 12, 13, 0] {
            kind = try CapturedSlot12KindSequence.next(
                kind: kind, room: RoomID(8, 9),
                position: GridPoint(53, 135), timer: 254
            )
            XCTAssertEqual(kind, expected)
        }
        for (kind, room, position, timer) in [
            (UInt8(0), RoomID(8, 9), GridPoint(53, 135), UInt8(254)),
            (110, RoomID(8, 9), GridPoint(53, 135), 254),
            (109, RoomID(8, 10), GridPoint(53, 135), 254),
            (109, RoomID(8, 9), GridPoint(54, 135), 254),
            (109, RoomID(8, 9), GridPoint(53, 135), 255),
        ] {
            XCTAssertThrowsError(try CapturedSlot12KindSequence.next(
                kind: kind, room: room, position: position, timer: timer
            ))
        }
    }

    func testPrivateSourceSequenceWhenProvided() throws {
        guard let directory = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_ENTITY_TRACE_DIR"
        ] else { throw XCTSkip("Set the ignored 250-frame slot-12 source traces") }
        struct Write: Decodable {
            let frame: Int
            let address: Int
            let previous: Int
            let value: Int
        }
        struct Report: Decodable {
            let matchingRAMFrames: Int
            let entityStateWrites: [Write]
        }
        let base = URL(fileURLWithPath: directory)
        let report = try JSONDecoder().decode(
            Report.self, from: Data(contentsOf:
                base.appendingPathComponent("entity-writes-fire-before-contact-250.json")
            )
        )
        let trace = try ReferenceEntityTrace.load(from: Data(contentsOf:
            base.appendingPathComponent("trace-fire-before-contact-250.json")
        ))
        let replay = try ReferenceReplay.load(from: Data(contentsOf:
            base.appendingPathComponent("replay-fire-before-contact-250.json")
        ))
        try trace.validate(replay: replay)
        XCTAssertEqual(report.matchingRAMFrames, 250)
        XCTAssertEqual(trace.observedSlot, 12)
        let changes = report.entityStateWrites.filter {
            $0.address == 38802 && (231...250).contains($0.frame)
        }
        XCTAssertEqual(report.entityStateWrites.filter {
            (231...250).contains($0.frame)
        }.count, 7)
        XCTAssertEqual(changes.map(\.frame), [235, 238, 240, 243, 245, 248, 250])
        XCTAssertEqual(changes.map(\.value), [8, 9, 10, 11, 12, 13, 0])
        var kind: UInt8 = 109
        for frame in 231...250 {
            let source = trace.trace[frame - 1]
            XCTAssertEqual(source.manualEntity.kind, source.fullEmulatorEntity.kind)
            XCTAssertEqual(source.manualEntity.x, source.fullEmulatorEntity.x)
            XCTAssertEqual(source.manualEntity.y, source.fullEmulatorEntity.y)
            XCTAssertEqual(source.manualEntity.roomID, 152)
            XCTAssertEqual(source.manualEntity.x, 53)
            XCTAssertEqual(source.manualEntity.y, 135)
            for write in changes where write.frame == frame {
                XCTAssertEqual(Int(kind), write.previous)
                kind = try CapturedSlot12KindSequence.next(
                    kind: kind, room: RoomID(8, 9),
                    position: GridPoint(53, 135), timer: 254
                )
                XCTAssertEqual(Int(kind), write.value)
            }
            XCTAssertEqual(Int(kind), source.fullEmulatorEntity.kind)
        }
    }
}
