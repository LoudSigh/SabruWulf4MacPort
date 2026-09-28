import CryptoKit
import Foundation
import XCTest
@testable import GameCore

final class BackgroundAtlasTests: XCTestCase {
    private func fixture() throws -> (data: Data, digest: String, count: Int) {
        let bitmap = [UInt8]([0x80, 0, 0, 0, 0, 0, 0, 0])
        let record = Data([8, 1] + bitmap + [1, 1, 7])
        let records: [[String: Any]] = (0..<41).map { index in
            ["address": 28_860 + index * record.count,
             "data": record.base64EncodedString()]
        }
        var bytes = Data()
        for _ in 0..<41 { bytes.append(record) }
        let digest = SHA256.hash(data: bytes).map {
            String(format: "%02x", $0)
        }.joined()
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "snapshotSHA256": WorldReference.supportedSnapshotSHA256,
            "records": records,
        ])
        return (data, digest, bytes.count)
    }

    func testDecodesBitmapAndChecksAttributeShape() throws {
        let source = try fixture()
        let atlas = try BackgroundAtlas.load(
            from: source.data, expectedHash: source.digest,
            expectedBytes: source.count
        )
        let mask = try atlas.mask(at: 28_860)
        XCTAssertEqual(mask.width, 8)
        XCTAssertEqual(mask.height, 8)
        XCTAssertEqual(mask.pixels().count, 64)
        XCTAssertTrue(mask.pixels()[0])
        XCTAssertFalse(mask.pixels()[1])
        XCTAssertEqual(mask.paletteIndices()[0], 7)
        XCTAssertEqual(mask.paletteIndices()[1], 0)
        XCTAssertEqual(mask.paletteIndices(invertBitmap: true)[0], 0)
        XCTAssertEqual(mask.paletteIndices(invertBitmap: true)[1], 7)
        XCTAssertThrowsError(try atlas.mask(at: 0))
        let rooms: [[String: Any]] = (0..<48).map { _ in
            ["placements": [[
                "graphicAddress": 28_860, "x": 0, "y": 16,
                "widthPixels": 8, "heightPixels": 8,
            ]]]
        }
        let worldData = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 2,
            "snapshotSha256": WorldReference.supportedSnapshotSHA256,
            "width": 16, "height": 16,
            "layout": Array(repeating: 0, count: 256),
            "rooms": rooms,
        ])
        let world = try WorldReference.load(from: worldData, verifySource: false)
        XCTAssertThrowsError(try atlas.validate(world: world))
    }

    func testRejectsChangedRecordAndBadAttributeDimensions() throws {
        let source = try fixture()
        XCTAssertThrowsError(try BackgroundAtlas.load(
            from: source.data, expectedHash: String(repeating: "0", count: 64),
            expectedBytes: source.count
        ))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: source.data) as? [String: Any]
        )
        var records = try XCTUnwrap(object["records"] as? [[String: Any]])
        var changedBitmap = try XCTUnwrap(
            Data(base64Encoded: try XCTUnwrap(records[0]["data"] as? String))
        )
        changedBitmap[2] ^= 0x40
        records[0]["data"] = changedBitmap.base64EncodedString()
        object["records"] = records
        XCTAssertThrowsError(try BackgroundAtlas.load(
            from: JSONSerialization.data(withJSONObject: object),
            expectedHash: source.digest, expectedBytes: source.count
        )) { error in
            guard case BackgroundAtlasError.integrityMismatch = error else {
                return XCTFail("Expected a source-record integrity mismatch")
            }
        }
        records[0]["data"] = Data([8, 1] + Array(repeating: 0, count: 8) + [2, 1, 7])
            .base64EncodedString()
        object["records"] = records
        XCTAssertThrowsError(try BackgroundAtlas.load(
            from: JSONSerialization.data(withJSONObject: object),
            expectedHash: source.digest, expectedBytes: source.count
        ))
        var misaligned = try XCTUnwrap(
            JSONSerialization.jsonObject(with: source.data) as? [String: Any]
        )
        var shifted = try XCTUnwrap(misaligned["records"] as? [[String: Any]])
        shifted[1]["address"] = 28_874
        misaligned["records"] = shifted
        XCTAssertThrowsError(try BackgroundAtlas.load(
            from: JSONSerialization.data(withJSONObject: misaligned),
            expectedHash: source.digest, expectedBytes: source.count
        )) { error in
            guard case BackgroundAtlasError.invalidRecord = error else {
                return XCTFail("Expected a gap between source records to be rejected")
            }
        }
        XCTAssertThrowsError(try BackgroundAtlas.load(from: Data(repeating: 0, count: 100_001)))
    }

    func testPrivateBackgroundsAgreeWithImportedWorldWhenProvided() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let backgroundPath = environment["SABRE_PRIVATE_BACKGROUND_ATLAS"],
              let worldPath = environment["SABRE_PRIVATE_WORLD"] else {
            throw XCTSkip("Set private background atlas and world paths for local validation")
        }
        let atlas = try BackgroundAtlas.load(
            from: Data(contentsOf: URL(fileURLWithPath: backgroundPath))
        )
        let world = try WorldReference.load(
            from: Data(contentsOf: URL(fileURLWithPath: worldPath))
        )
        XCTAssertNoThrow(try atlas.validate(world: world))
        let graphic = try atlas.mask(at: 28_860)
        XCTAssertEqual(graphic.width, 72)
        XCTAssertEqual(graphic.height, 24)
    }
}
