// swift-tools-version:5.9
import PackageDescription

// Only the pure logic is a package target, so `swift test` runs without AppKit, a display or a lid.
// The app itself is compiled by build.sh from the same Sources/LidFoldCore files plus the app shell in Sources/.
let package = Package(
    name: "LidFold",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LidFoldCore", path: "Sources/LidFoldCore"),
        .testTarget(name: "LidFoldCoreTests", dependencies: ["LidFoldCore"], path: "Tests/LidFoldCoreTests"),
    ]
)
