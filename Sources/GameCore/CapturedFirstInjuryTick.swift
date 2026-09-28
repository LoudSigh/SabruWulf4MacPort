import Foundation

public enum CapturedInjuryError: Error, LocalizedError {
    case unsupportedState

    public var errorDescription: String? {
        "This injury transition is verified only for captured kind-65 countdowns with one through four life bytes."
    }
}

public struct CapturedInjuryStep: Equatable, Sendable {
    public let kind: UInt8
    public let timer: UInt8
    public let lifeByte: UInt8
}

enum CapturedInjuryCountdownRule {
    static func advance(
        kind: UInt8, timer: UInt8, lifeByte: UInt8, terminalKind: UInt8
    ) -> CapturedInjuryStep {
        if timer == 1 {
            return CapturedInjuryStep(
                kind: terminalKind, timer: 0, lifeByte: lifeByte - 1
            )
        }
        return CapturedInjuryStep(
            kind: kind, timer: timer - 1, lifeByte: lifeByte
        )
    }
}

/// One source actor update, not one display frame or an enemy-damage event.
public enum CapturedFirstInjuryTick {
    public static func advance(
        kind: UInt8, timer: UInt8, lifeByte: UInt8
    ) throws -> CapturedInjuryStep {
        guard kind == 65, (1...63).contains(Int(timer)),
              (1...4).contains(Int(lifeByte)) else {
            throw CapturedInjuryError.unsupportedState
        }
        return CapturedInjuryCountdownRule.advance(
            kind: kind, timer: timer, lifeByte: lifeByte, terminalKind: 17
        )
    }
}
