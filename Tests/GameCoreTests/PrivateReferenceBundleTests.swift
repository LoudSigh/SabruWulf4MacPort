import Foundation
import XCTest
@testable import GameCore

final class PrivateReferenceBundleTests: XCTestCase {
    func testRejectsMissingAndOversizedBundleFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: false
        )
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { XCTFail("Could not remove test directory: \(error)") }
        }
        let name = "snapshot-\(WorldReference.supportedSnapshotSHA256.prefix(12))-world-v2.json"
        XCTAssertThrowsError(try PrivateReferenceBundle.load(from: directory)) {
            guard case PrivateReferenceBundleError.missingFile(let file) = $0 else {
                return XCTFail("Expected missing-file error, got \($0)")
            }
            XCTAssertEqual(file, name)
        }
        try Data().write(to: directory.appendingPathComponent(name))
        XCTAssertThrowsError(try PrivateReferenceBundle.load(from: directory)) {
            guard case PrivateReferenceBundleError.emptyFile(let file) = $0 else {
                return XCTFail("Expected empty-file error, got \($0)")
            }
            XCTAssertEqual(file, name)
        }
        try Data(repeating: 0, count: 2_000_001).write(
            to: directory.appendingPathComponent(name)
        )
        XCTAssertThrowsError(try PrivateReferenceBundle.load(from: directory)) {
            guard case PrivateReferenceBundleError.oversizedFile(let file) = $0 else {
                return XCTFail("Expected oversized-file error, got \($0)")
            }
            XCTAssertEqual(file, name)
        }
    }

    func testPrivateBundleWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["SABRE_PRIVATE_REFERENCE_DIR"]
        else { throw XCTSkip("Set the ignored launcher-generated reference directory") }
        let bundle = try PrivateReferenceBundle.load(
            from: URL(fileURLWithPath: path, isDirectory: true)
        )
        XCTAssertEqual(bundle.world.schemaVersion, 2)
        XCTAssertEqual(bundle.world.rooms.count, 48)
        XCTAssertEqual(bundle.placements.records.count, 4)
        XCTAssertEqual(bundle.replay.frames.count, 1050)
        XCTAssertNotNil(try bundle.sprites.mask(at: 16))
        let template = try XCTUnwrap(bundle.world.roomType(
            at: WorldReference.capturedGameplayRoom
        ))
        _ = try BackgroundScene(
            world: bundle.world, atlas: bundle.backgrounds,
            template: template
        )
    }
}
