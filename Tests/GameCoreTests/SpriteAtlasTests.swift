import CryptoKit
import Foundation
import XCTest
@testable import GameCore

final class SpriteAtlasTests: XCTestCase {
    private func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func fixture() throws -> (data: Data, tableHash: String, recordHash: String, bytes: Int) {
        let addresses = [49_420] + (0..<152).map { 49_422 + $0 * 3 }
        let pointers = addresses + Array(repeating: 49_420, count: 196 - addresses.count)
        var table = Data()
        for address in pointers {
            table.append(UInt8(truncatingIfNeeded: address))
            table.append(UInt8(truncatingIfNeeded: address >> 8))
        }
        var payload = Data()
        let records: [[String: Any]] = addresses.enumerated().map { index, address in
            let record = Data(index == 0 ? [0, 0] : [1, 1, 0x80])
            payload.append(record)
            return ["address": address, "bitmap": record.base64EncodedString()]
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "snapshotSHA256": WorldReference.supportedSnapshotSHA256,
            "pointers": pointers,
            "records": records,
        ])
        return (data, hash(table), hash(payload), payload.count)
    }

    func testDecodesPointerAliasesAndExplicitEmptySentinel() throws {
        let source = try fixture()
        let atlas = try SpriteAtlas.load(
            from: source.data, tableHash: source.tableHash,
            recordHash: source.recordHash, expectedBytes: source.bytes
        )
        XCTAssertNil(try atlas.mask(at: 0))
        XCTAssertNil(try atlas.mask(at: 195))
        let mask = try XCTUnwrap(atlas.mask(at: 16))
        XCTAssertEqual(mask.width, 8)
        XCTAssertTrue(try mask.isSet(x: 0, y: 0))
        XCTAssertThrowsError(try atlas.mask(at: 196))
    }

    func testRejectsModifiedPayloadAndMalformedPointerTable() throws {
        let source = try fixture()
        XCTAssertThrowsError(try SpriteAtlas.load(
            from: source.data, tableHash: source.tableHash,
            recordHash: String(repeating: "0", count: 64), expectedBytes: source.bytes
        ))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: source.data) as? [String: Any]
        )
        var pointers = try XCTUnwrap(object["pointers"] as? [Int])
        pointers[5] = 65_535
        object["pointers"] = pointers
        XCTAssertThrowsError(try SpriteAtlas.load(
            from: JSONSerialization.data(withJSONObject: object),
            tableHash: source.tableHash, recordHash: source.recordHash,
            expectedBytes: source.bytes
        ))
        XCTAssertThrowsError(try SpriteAtlas.load(
            from: Data(repeating: 0, count: 100_001)
        ))
    }

    func testPrivateAtlasWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["SABRE_PRIVATE_SPRITE_ATLAS"] else {
            throw XCTSkip("Set SABRE_PRIVATE_SPRITE_ATLAS for local sprite-record validation")
        }
        let atlas = try SpriteAtlas.load(
            from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        let emptyIDs = try (0..<SpriteAtlas.spriteCount).filter {
            try atlas.mask(at: $0) == nil
        }
        XCTAssertEqual(emptyIDs, [0, 7, 14, 15, 90, 91, 94, 95, 124, 125, 126, 127, 150, 151])
        let sample16 = try XCTUnwrap(atlas.mask(at: 16))
        XCTAssertEqual(sample16.width, 16)
        XCTAssertEqual(sample16.height, 21)
        let sample21 = try XCTUnwrap(atlas.mask(at: 21))
        XCTAssertEqual(sample21.width, 16)
        XCTAssertEqual(sample21.height, 22)
        if let replayPath = ProcessInfo.processInfo.environment["SABRE_PRIVATE_FIRE_REPLAY"] {
            let replay = try ReferenceReplay.load(
                from: Data(contentsOf: URL(fileURLWithPath: replayPath))
            )
            for frame in replay.frames {
                let kind = try XCTUnwrap(frame.playerKind)
                XCTAssertNotNil(try atlas.mask(at: kind))
            }
        }
    }
}
