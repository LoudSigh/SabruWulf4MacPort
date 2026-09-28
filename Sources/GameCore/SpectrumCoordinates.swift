/// Source gameplay Y increases upward; SwiftUI's room canvas Y increases downward.
public enum SpectrumCoordinates {
    public static let screenHeight = 192

    public static func screenY(forSourceY sourceY: Int) -> Int {
        screenHeight - sourceY
    }

    public static func backgroundTop(sourceY: Int, height: Int) -> Int {
        screenY(forSourceY: sourceY) - height
    }
}
