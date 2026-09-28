import Foundation
import XCTest
@testable import GameCore

final class WorldReferenceTests: XCTestCase {
    private func fixture(
        layout: [Int] = Array(repeating: 0, count: 256),
        rooms: [[String: Any]]? = nil,
        sha: String = WorldReference.supportedSnapshotSHA256,
        version: Int = 1
    ) throws -> Data {
        let templates = rooms ?? (0..<48).map { _ in
            ["placements": [["graphicAddress": 0x70BC, "x": 0, "y": 16]]]
        }
        return try JSONSerialization.data(withJSONObject: [
            "schemaVersion": version,
            "snapshotSha256": sha,
            "width": 16,
            "height": 16,
            "layout": layout,
            "rooms": templates,
        ])
    }

    func testRoomTypesAndAdjacencyUseFullWorldBounds() throws {
        var layout = Array(repeating: 0, count: 256)
        layout[15] = 47
        layout[16] = 1
        let world = try WorldReference.load(from: fixture(layout: layout))
        XCTAssertEqual(world.roomType(at: RoomID(15, 0)), 47)
        XCTAssertEqual(world.roomType(at: RoomID(0, 1)), 1)
        XCTAssertNil(world.roomType(at: RoomID(16, 0)))
        XCTAssertEqual(world.adjacent(to: RoomID(14, 0), direction: .east), RoomID(15, 0))
        XCTAssertNil(world.adjacent(to: RoomID(15, 0), direction: .east))
        XCTAssertNil(world.adjacent(to: RoomID(0, 0), direction: .north))
        XCTAssertEqual(WorldReference.capturedGameplayRoom, RoomID(8, 10))
        XCTAssertEqual(WorldReference.capturedPlayerPosition, GridPoint(57, 112))
    }

    func testRejectsForeignSnapshotAndMalformedWorld() throws {
        XCTAssertThrowsError(try WorldReference.load(from: fixture(sha: String(repeating: "0", count: 64))))
        XCTAssertThrowsError(try WorldReference.load(from: fixture(layout: Array(repeating: 0, count: 255))))
        var invalid = Array(repeating: 0, count: 256)
        invalid[42] = 48
        XCTAssertThrowsError(try WorldReference.load(from: fixture(layout: invalid)))
        XCTAssertThrowsError(try WorldReference.load(from: Data("not-json".utf8)))
    }

    func testRejectsBadGraphicAddressAndEmptyTemplate() throws {
        var rooms: [[String: Any]] = (0..<48).map { _ in
            ["placements": [["graphicAddress": 0x70BC, "x": 0, "y": 16]]]
        }
        rooms[4] = ["placements": []]
        XCTAssertThrowsError(try WorldReference.load(from: fixture(rooms: rooms)))
        rooms[4] = ["placements": [["graphicAddress": 0, "x": 0, "y": 16]]]
        XCTAssertThrowsError(try WorldReference.load(from: fixture(rooms: rooms)))
        rooms[4] = ["placements": [["graphicAddress": 0x70BC, "x": 256, "y": 16]]]
        XCTAssertThrowsError(try WorldReference.load(from: fixture(rooms: rooms)))
        XCTAssertThrowsError(
            try WorldReference.load(from: Data(repeating: 0, count: 2_000_001))
        )
    }

    func testMeasuredBoundsPreserveBackgroundAndActorEdges() throws {
        let rooms: [[String: Any]] = (0..<48).map { _ in
            ["placements": [[
                "graphicAddress": 0x70BC, "x": 32, "y": 112,
                "widthPixels": 24, "heightPixels": 24,
            ], [
                "graphicAddress": 0x70BD, "x": 48, "y": 40,
                "widthPixels": 16, "heightPixels": 24,
            ]]]
        }
        let world = try WorldReference.load(from: fixture(rooms: rooms, version: 2))
        let room = WorldReference.capturedGameplayRoom
        XCTAssertFalse(try world.overlapsBackgroundBounds(
            in: room, actorAt: GridPoint(57, 112), width: 14, height: 22
        ))
        XCTAssertFalse(try world.overlapsBackgroundBounds(
            in: room, actorAt: GridPoint(56, 112), width: 14, height: 22
        ))
        XCTAssertFalse(try world.overlapsBackgroundBounds(
            in: room, actorAt: GridPoint(57, 87), width: 14, height: 22
        ))
        XCTAssertTrue(try world.overlapsBackgroundBounds(
            in: room, actorAt: GridPoint(57, 85), width: 14, height: 22
        ))
        XCTAssertFalse(try world.overlapsBackgroundBounds(
            in: room, actorAt: GridPoint(57, 86), width: 14, height: 22
        ))
        XCTAssertTrue(try world.overlapsBackgroundBounds(
            in: room, actorAt: GridPoint(55, 112), width: 14, height: 22
        ))
        XCTAssertTrue(try world.overlapsBackgroundBounds(
            in: room, actorAt: GridPoint(18, 112), width: 14, height: 22
        ))
        XCTAssertFalse(try world.overlapsBackgroundBounds(
            in: room, actorAt: GridPoint(17, 112), width: 14, height: 22
        ))
        XCTAssertTrue(try world.overlapsBackgroundBounds(
            in: room, actorAt: GridPoint(40, 157), width: 14, height: 22
        ))
        XCTAssertFalse(try world.overlapsBackgroundBounds(
            in: room, actorAt: GridPoint(40, 158), width: 14, height: 22
        ))
        XCTAssertFalse(try world.overlapsBackgroundBounds(
            in: room, actorAt: GridPoint(40, 111), width: 14, height: 22
        ))
        XCTAssertEqual(
            try world.resolveBackgroundBounds(
                in: room, from: GridPoint(57, 112), to: GridPoint(55, 112),
                width: 14, height: 22
            ), GridPoint(57, 112)
        )
        XCTAssertEqual(
            try world.resolveBackgroundBounds(
                in: room, from: GridPoint(57, 87), to: GridPoint(57, 85),
                width: 14, height: 22
            ), GridPoint(57, 87)
        )
        XCTAssertEqual(
            try world.resolveBackgroundBounds(
                in: room, from: GridPoint(57, 112), to: GridPoint(55, 113),
                width: 14, height: 22
            ), GridPoint(57, 113)
        )
        XCTAssertEqual(
            try world.resolveBackgroundBounds(
                in: room, from: GridPoint(57, 87), to: GridPoint(58, 85),
                width: 14, height: 22
            ), GridPoint(58, 87)
        )
        XCTAssertEqual(
            try world.resolveBackgroundBounds(
                in: room, from: GridPoint(57, 111), to: GridPoint(55, 112),
                width: 14, height: 22
            ), GridPoint(55, 112)
        )
        XCTAssertThrowsError(try world.overlapsBackgroundBounds(
            in: room, actorAt: GridPoint(55, 112), width: 0, height: 22
        ))
        XCTAssertThrowsError(try world.overlapsBackgroundBounds(
            in: room, actorAt: GridPoint(-1, 112), width: 14, height: 22
        ))
        XCTAssertThrowsError(try world.resolveBackgroundBounds(
            in: room, from: GridPoint(-1, 112), to: GridPoint(55, 112),
            width: 14, height: 22
        ))
        XCTAssertThrowsError(try world.overlapsBackgroundBounds(
            in: RoomID(16, 0), actorAt: GridPoint(55, 112), width: 14, height: 22
        ))
        var malformed = rooms
        malformed[0] = ["placements": [[
            "graphicAddress": 0x70BC, "x": 32, "y": 112, "heightPixels": 24,
        ]]]
        XCTAssertThrowsError(try WorldReference.load(from: fixture(rooms: malformed, version: 2)))
        let old = try WorldReference.load(from: fixture())
        XCTAssertThrowsError(try old.overlapsBackgroundBounds(
            in: room, actorAt: GridPoint(55, 112), width: 14, height: 22
        ))
    }

    func testMeasuredBoundsRetainEightBitWraparound() throws {
        let rooms: [[String: Any]] = (0..<48).map { _ in
            ["placements": [[
                "graphicAddress": 0x70BC, "x": 200, "y": 112,
                "widthPixels": 72, "heightPixels": 24,
            ]]]
        }
        let world = try WorldReference.load(from: fixture(rooms: rooms, version: 2))
        XCTAssertTrue(try world.overlapsBackgroundBounds(
            in: RoomID(8, 10), actorAt: GridPoint(0, 112), width: 14, height: 22
        ))
        XCTAssertFalse(try world.overlapsBackgroundBounds(
            in: RoomID(8, 10), actorAt: GridPoint(0, 87), width: 14, height: 22
        ))
    }
}
