// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Fling",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Fling"),
        .testTarget(name: "FlingTests", dependencies: ["Fling"]),
    ]
)
