// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mem-usage",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "MemAppsCore", targets: ["MemAppsCore"]),
        .executable(name: "memapps", targets: ["memapps"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MemAppsCore",
            path: "Sources/MemAppsCore"
        ),
        .executableTarget(
            name: "memapps",
            dependencies: ["MemAppsCore"],
            path: "Sources/memapps"
        ),
        .testTarget(
            name: "MemAppsCoreTests",
            dependencies: ["MemAppsCore"],
            path: "Tests/MemAppsCoreTests"
        )
    ]
)
