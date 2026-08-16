// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DotJSON",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DotJSONCore", targets: ["DotJSONCore"]),
        .executable(name: "DotJSON", targets: ["DotJSON"]),
    ],
    targets: [
        .target(
            name: "DotJSONCore",
            path: "Sources/DotJSONCore"
        ),
        .executableTarget(
            name: "DotJSON",
            dependencies: ["DotJSONCore"],
            path: "Sources/DotJSON",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "DotJSONTests",
            dependencies: ["DotJSON", "DotJSONCore"],
            path: "Tests/DotJSONTests"
        ),
        .testTarget(
            name: "DotJSONCoreTests",
            dependencies: ["DotJSONCore"],
            path: "Tests/DotJSONCoreTests"
        ),
        .testTarget(
            name: "DotJSONCLITests",
            dependencies: ["DotJSON", "DotJSONCore"],
            path: "Tests/DotJSONCLITests"
        ),
    ]
)
