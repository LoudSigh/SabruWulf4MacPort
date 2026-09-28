import Foundation

/// Source RNG writes from supplied CPU/clock operands; this does not emulate the Z80 refresh register.
public enum CapturedRNGStep {
    public static func refresh(
        previous: UInt8, refreshOperand: UInt8, carry: Bool
    ) -> UInt8 {
        UInt8(truncatingIfNeeded:
            Int(previous) + Int(refreshOperand) + (carry ? 1 : 0)
        )
    }

    public static func clock(
        previous: UInt8, counterLowByte: UInt8, clockByte: UInt8
    ) -> UInt8 {
        previous &+ counterLowByte &+ clockByte
    }
}
