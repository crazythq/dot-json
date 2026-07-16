// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DotJSON",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DotJSONCore", targets: ["DotJSONCore"]),
        .executable(name: "DotJSON", targets: ["DotJSON"]),
        .executable(name: "dotjson", targets: ["DotJSONCLI"]),
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
        .executableTarget(
            name: "DotJSONCLI",
            dependencies: ["DotJSONCore"],
            path: "Sources/DotJSONCLI"
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
            dependencies: ["DotJSONCLI", "DotJSONCore"],
            path: "Tests/DotJSONCLITests"
        ),
    ]
)
