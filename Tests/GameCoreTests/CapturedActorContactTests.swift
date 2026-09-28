import XCTest
@testable import GameCore

final class CapturedActorContactTests: XCTestCase {
    private func contact(
        kind: UInt8 = 27, playerRoom: UInt8 = 152, x: UInt8 = 121, y: UInt8 = 126,
        byte5: UInt8 = 0x47, suppression: UInt8 = 0,
        otherRoom: UInt8 = 152, otherX: UInt8 = 104, otherY: UInt8 = 135,
        right: UInt8 = 19, above: UInt8 = 19
    ) -> Bool {
        CapturedActorContact.overlaps(
            playerKind: kind, playerRoom: playerRoom, playerX: x, playerY: y,
            playerByte5: byte5, suppressionFlag: suppression,
            otherRoom: otherRoom, otherX: otherX, otherY: otherY,
            playerRightReach: right, playerAboveReach: above
        )
    }

    func testObservedEnemyContactAndStrictThresholds() {
        XCTAssertTrue(contact())
        XCTAssertFalse(contact(otherX: 102))
        XCTAssertFalse(contact(otherY: 107))
        XCTAssertTrue(contact(otherY: 112))
        XCTAssertFalse(contact(otherY: 145))
        XCTAssertTrue(contact(otherY: 144))
        XCTAssertFalse(contact(right: 17))
        XCTAssertTrue(contact(right: 18))
        XCTAssertFalse(contact(above: 9))
        XCTAssertTrue(contact(above: 10))
    }

    func testAsymmetricLeftReachChangesWithPlayerKind() {
        XCTAssertFalse(contact(otherX: 133))
        XCTAssertTrue(contact(otherX: 132))
        XCTAssertTrue(contact(kind: 36, otherX: 133))
        XCTAssertFalse(contact(kind: 36, otherX: 149))
        XCTAssertTrue(contact(kind: 36, otherX: 148))
    }

    func testGatesByRoomStateAndSuppression() {
        XCTAssertFalse(contact(playerRoom: 151))
        XCTAssertFalse(contact(byte5: 0x46))
        XCTAssertFalse(contact(suppression: 1))
        XCTAssertFalse(contact(kind: 15))
        XCTAssertFalse(contact(kind: 48))
        XCTAssertTrue(contact(kind: 16))
        XCTAssertTrue(contact(kind: 47))
    }
}
