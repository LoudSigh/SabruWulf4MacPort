/// Keyboard actions observed for the ZX Spectrum 48K one-player keyboard option.
/// The port maps platform input onto these actions; it does not use Spectrum key codes at runtime.
public enum OriginalAction: String, Sendable, CaseIterable {
    case left
    case right
    case down
    case up
    case fire

    public static func fromSpectrumKey(_ character: Character) -> Self? {
        switch character.lowercased() {
        case "q": .left
        case "w": .right
        case "e": .up
        case "r": .down
        case "t": .fire
        default: nil
        }
    }
}
