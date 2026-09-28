import Foundation

public enum CapturedInjuryError: Error, LocalizedError {
    case unsupportedState

    public var errorDescription: String? {
        "This injury transition is verified only for the captured one-life, kind-65 countdown."
    }
}

public struct CapturedInjuryStep: Equatable, Sendable {
    public let kind: UInt8
    public let timer: UInt8
    public let lifeByte: UInt8
}

/// One source actor update, not one display frame or an enemy-damage event.
public enum CapturedFirstInjuryTick {
    public static func advance(
        kind: UInt8, timer: UInt8, lifeByte: UInt8
    ) throws -> CapturedInjuryStep {
        guard kind == 65, (1...63).contains(Int(timer)), lifeByte == 1 else {
            throw CapturedInjuryError.unsupportedState
        }
        if timer == 1 {
            return CapturedInjuryStep(kind: 17, timer: 0, lifeByte: 0)
        }
        return CapturedInjuryStep(kind: 65, timer: timer - 1, lifeByte: 1)
    }
}
