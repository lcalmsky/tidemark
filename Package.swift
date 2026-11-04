// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "tidemark",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "tidemark", targets: ["tidemark"]),
    ],
    targets: [
        .target(name: "TidemarkCore", path: "Sources/TidemarkCore"),
        .executableTarget(
            name: "tidemark",
            dependencies: ["TidemarkCore"],
            path: "Sources/tidemark"
        ),
        .testTarget(
            name: "TidemarkCoreTests",
            dependencies: ["TidemarkCore"],
            path: "Tests/TidemarkCoreTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
