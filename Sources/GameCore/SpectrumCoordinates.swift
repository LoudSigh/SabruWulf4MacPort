/// Source room and actor Y coordinates map directly to the downward screen Y axis.
public enum SpectrumCoordinates {
    public static let screenHeight = 192

    public static func screenY(forSourceY sourceY: Int) -> Int {
        sourceY
    }

    public static func backgroundTop(sourceY: Int) -> Int {
        sourceY
    }
}
