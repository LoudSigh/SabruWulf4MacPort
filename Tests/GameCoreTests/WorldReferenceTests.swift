import Foundation
import XCTest
@testable import GameCore

final class WorldReferenceTests: XCTestCase {
    private func fixture(
        layout: [Int] = Array(repeating: 0, count: 256),
        rooms: [[String: Any]]? = nil,
        sha: String = WorldReference.supportedSnapshotSHA256
    ) throws -> Data {
        let templates = rooms ?? (0..<48).map { _ in
            ["placements": [["graphicAddress": 0x70BC, "x": 0, "y": 16]]]
        }
        return try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
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
}
