// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mem",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "MemCore", targets: ["MemCore"]),
        .executable(name: "mem", targets: ["mem"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MemCore",
            path: "Sources/MemCore"
        ),
        .executableTarget(
            name: "mem",
            dependencies: ["MemCore"],
            path: "Sources/mem"
        ),
        .testTarget(
            name: "MemTests",
            dependencies: ["MemCore"],
            path: "Tests/MemTests"
        )
    ]
)
