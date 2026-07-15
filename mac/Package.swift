// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DotJSON",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DotJSON",
            path: "Sources/DotJSON",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "DotJSONTests",
            dependencies: ["DotJSON"],
            path: "Tests/DotJSONTests"
        ),
    ]
)
