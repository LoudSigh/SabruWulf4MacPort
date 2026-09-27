// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GameCore",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        .library(name: "GameCore", targets: ["GameCore"]),
        .executable(name: "TapeInventory", targets: ["TapeInventory"])
    ],
    targets: [
        .target(name: "GameCore", path: "Sources/GameCore"),
        .executableTarget(name: "TapeInventory", path: "Tools"),
        .testTarget(name: "GameCoreTests", dependencies: ["GameCore"], path: "Tests/GameCoreTests")
    ]
)
