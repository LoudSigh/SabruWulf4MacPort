import Foundation
import XCTest
@testable import GameCore

final class CapturedPlacementStateTests: XCTestCase {
    private func world() throws -> WorldReference {
        let rooms: [[String: Any]] = (0..<48).map { _ in
            ["placements": [[
                "graphicAddress": 0x70BC, "x": 0, "y": 0,
                "widthPixels": 8, "heightPixels": 8,
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

    private func fixture(
        sha: String = WorldReference.supportedSnapshotSHA256,
        frame: Int = 656,
        records: [[String: Int]]? = nil
    ) throws -> Data {
        let entries = records ?? (0..<4).map { id in
            [
                "id": id, "spriteID": 16 + id, "roomID": id * 17,
                "x": 30 + id, "y": 70 + id,
            ]
        }
        return try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "snapshotSHA256": sha,
            "sourceFrame": frame, "records": entries,
        ])
    }

    func testAcceptsFourUnidentifiedRecordsWithoutQuestClaims() throws {
        let placement = try CapturedPlacementState.load(
            from: fixture(), world: world()
        )
        XCTAssertEqual(placement.sourceFrame, 656)
        XCTAssertEqual(placement.records.map(\.id), [0, 1, 2, 3])
        XCTAssertEqual(placement.records[1].roomID, 17)
    }

    func testRejectsBadProvenanceAndRecords() throws {
        let source = try world()
        XCTAssertThrowsError(try CapturedPlacementState.load(
            from: fixture(sha: String(repeating: "0", count: 64)), world: source
        ))
        XCTAssertThrowsError(try CapturedPlacementState.load(
            from: fixture(frame: 0), world: source
        ))
        let duplicates = (0..<4).map { id in
            [
                "id": id, "spriteID": 16 + id, "roomID": 0,
                "x": 30 + id, "y": 70 + id,
            ]
        }
        XCTAssertThrowsError(try CapturedPlacementState.load(
            from: fixture(records: duplicates), world: source
        ))
        var invalid = duplicates
        invalid[1]["roomID"] = 17
        invalid[2]["roomID"] = 34
        invalid[3]["roomID"] = 51
        invalid[3]["spriteID"] = SpriteAtlas.spriteCount
        XCTAssertThrowsError(try CapturedPlacementState.load(
            from: fixture(records: invalid), world: source
        ))
    }

    func testPrivateFourRecordsWhenProvided() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let placementPath = environment["SABRE_PRIVATE_PLACEMENT"],
              let worldPath = environment["SABRE_PRIVATE_WORLD"],
              let atlasPath = environment["SABRE_PRIVATE_ATLAS"] else {
            throw XCTSkip("Set the ignored placement, world and sprite-atlas paths")
        }
        let world = try WorldReference.load(
            from: Data(contentsOf: URL(fileURLWithPath: worldPath))
        )
        let atlas = try SpriteAtlas.load(
            from: Data(contentsOf: URL(fileURLWithPath: atlasPath))
        )
        let placement = try CapturedPlacementState.load(
            from: Data(contentsOf: URL(fileURLWithPath: placementPath)), world: world
        )
        try placement.validate(spriteAtlas: atlas)
        XCTAssertEqual(placement.sourceFrame, 656)
        XCTAssertEqual(placement.records.map(\.id).sorted(), [0, 1, 2, 3])
        XCTAssertEqual(Set(placement.records.map(\.roomID)).count, 4)
        if let oraclePath = environment["SABRE_PRIVATE_PLACEMENT_ORACLE"] {
            let independentlyMeasured = try CapturedPlacementState.load(
                from: Data(contentsOf: URL(fileURLWithPath: oraclePath)),
                world: world
            )
            try independentlyMeasured.validate(spriteAtlas: atlas)
            XCTAssertEqual(placement.records, independentlyMeasured.records)
        }
    }
}
