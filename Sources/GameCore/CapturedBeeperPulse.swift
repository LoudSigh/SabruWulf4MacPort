import Foundation

public enum CapturedBeeperPulseError: Error, LocalizedError {
    case unsupportedInterruption

    public var errorDescription: String? {
        "Only the measured zero, 895 or 1124 extra T-state cases are supported for one beeper half-wave."
    }
}

/// A source-supplied high half-wave; this does not schedule or synthesize sound events.
public enum CapturedBeeperPulse {
    public static func highDurationTStates(
        delayCounter: UInt8, interruptionTStates: Int
    ) throws -> Int {
        guard [0, 895, 1124].contains(interruptionTStates) else {
            throw CapturedBeeperPulseError.unsupportedInterruption
        }
        let iterations = delayCounter == 0 ? 256 : Int(delayCounter)
        return iterations * 13 + 18 + interruptionTStates
    }
}
