import Foundation
import XCTest
@testable import GameCore

private struct ContactArmingReport: Decodable {
    struct Contact: Decodable {
        let positiveFrames: [Int]
    }
    struct Write: Decodable {
        let frame: Int
        let instructionAddress: Int
        let address: Int
        let previous: Int
        let value: Int
    }

    let matchingRAMFrames: Int
    let contactComparison: Contact?
    let playerStateWrites: [Write]?
}

final class CapturedContactArmingTests: XCTestCase {
    func testBoundedPositiveContactArmsTimer() throws {
        for (kind, life, room, vx, expected) in [
            (UInt8(27), UInt8(1), RoomID(8, 9), 0, UInt8(1)),
            (UInt8(16), UInt8(1), RoomID(8, 9), 0, UInt8(1)),
            (UInt8(19), UInt8(4), RoomID(8, 10), -29, UInt8(1)),
            (UInt8(17), UInt8(3), RoomID(8, 10), 0, UInt8(1)),
            (UInt8(17), UInt8(2), RoomID(8, 10), 0, UInt8(1)),
            (UInt8(17), UInt8(1), RoomID(8, 10), 0, UInt8(2)),
        ] {
            XCTAssertEqual(try CapturedContactArming.timerAfterContact(
                contact: true, kind: kind, timer: 0,
                lifeByte: life, room: room, velocityX: vx
            ), expected)
            XCTAssertThrowsError(try CapturedContactArming.timerAfterContact(
                contact: false, kind: kind, timer: 0,
                lifeByte: life, room: room, velocityX: vx
            ))
        }
    }

    func testRejectsOtherPlayerStates() throws {
        XCTAssertThrowsError(try CapturedContactArming.timerAfterContact(
            contact: true, kind: 27, timer: 1,
            lifeByte: 1, room: RoomID(8, 9), velocityX: 0
        ))
        XCTAssertThrowsError(try CapturedContactArming.timerAfterContact(
            contact: true, kind: 19, timer: 0,
            lifeByte: 1, room: RoomID(8, 10), velocityX: -29
        ))
    }

    func testObservedFourLifeStepsComposeWhenExternallyScheduled() throws {
        let armed = try CapturedContactArming.timerAfterContact(
            contact: true, kind: 19, timer: 0,
            lifeByte: 4, room: RoomID(8, 10), velocityX: -29
        )
        let injury = try CapturedInjuryStart.advance(
            kind: 19, timer: armed, lifeByte: 4,
            room: RoomID(8, 10), velocityX: -29
        )
        let knockback = try CapturedNewGameInjuryTick.advance(
            kind: injury.kind, room: RoomID(8, 10),
            x: 56, y: 112, timer: injury.timer,
            lifeByte: 4, velocityX: injury.velocityX
        )
        XCTAssertEqual(knockback, CapturedNewGameInjuryStep(x: 59, timer: 33))
    }

    func testPrivatePositiveContactArmingWhenProvided() throws {
        guard let directory = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_INJURY_START_DIR"
        ] else { throw XCTSkip("Set the ignored contact/player-write directory") }
        let base = URL(fileURLWithPath: directory)
        for (contactName, writeName, contactFrame, armedFrame, kind, life, room, vx) in [
            ("menu-sequence-no-fire-encounter-800.json",
             "player-onset-no-fire-encounter-190.json", 162, 163, 27, 1, 152, 0),
            ("menu-sequence-unrelated-a-control-800.json",
             "player-onset-unrelated-a-control-190.json", 169, 169, 27, 1, 152, 0),
            ("menu-sequence-fire-before-contact-800.json",
             "player-onset-fire-before-contact-250.json", 228, 228, 16, 1, 152, 0),
            ("restart-ready-reverse-contact-900.json",
             "restart-ready-w-q-player-writes-v2-900.json", 868, 868, 19, 4, 168, -29),
        ] {
            let contacts = try JSONDecoder().decode(
                ContactArmingReport.self,
                from: Data(contentsOf: base.appendingPathComponent(contactName))
            )
            let writes = try JSONDecoder().decode(
                ContactArmingReport.self,
                from: Data(contentsOf: base.appendingPathComponent(writeName))
            )
            XCTAssertTrue(contacts.matchingRAMFrames >= writes.matchingRAMFrames)
            XCTAssertTrue(try XCTUnwrap(contacts.contactComparison)
                .positiveFrames.contains(contactFrame))
            let arming = try XCTUnwrap(try XCTUnwrap(writes.playerStateWrites).first {
                $0.frame == armedFrame && $0.address == 38660
                    && $0.instructionAddress == 43877
            })
            XCTAssertEqual(arming.previous, 0)
            XCTAssertEqual(try CapturedContactArming.timerAfterContact(
                contact: true, kind: UInt8(kind), timer: UInt8(arming.previous),
                lifeByte: UInt8(life), room: RoomID(room % 16, room / 16),
                velocityX: vx
            ), UInt8(arming.value))
        }
    }

    func testPrivateLaterContactArmingWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment[
            "SABRE_PRIVATE_LONG_WQ_CONTACT"
        ] else { throw XCTSkip("Set the ignored 1800-frame W/Q contact report") }
        let report = try JSONDecoder().decode(
            ContactArmingReport.self, from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        XCTAssertEqual(report.matchingRAMFrames, 1800)
        let contacts = try XCTUnwrap(report.contactComparison)
        let writes = try XCTUnwrap(report.playerStateWrites)
        XCTAssertEqual(
            contacts.positiveFrames, [162, 298, 868, 1063, 1250, 1385, 1528]
        )
        for (frame, life, armedTimer) in [
            (1063, UInt8(3), UInt8(1)),
            (1250, UInt8(2), UInt8(1)),
            (1385, UInt8(1), UInt8(2)),
        ] {
            XCTAssertTrue(contacts.positiveFrames.contains(frame))
            let arming = try XCTUnwrap(writes.first {
                $0.frame == frame && $0.address == 38660
                    && $0.instructionAddress == 43877
            })
            XCTAssertEqual(arming.previous, 0)
            XCTAssertEqual(arming.value, Int(armedTimer))
            XCTAssertEqual(try CapturedContactArming.timerAfterContact(
                contact: true, kind: 17, timer: 0,
                lifeByte: life, room: RoomID(8, 10), velocityX: 0
            ), armedTimer)
        }
    }
}
