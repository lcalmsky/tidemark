// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "tidemark",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "tidemark", targets: ["tidemark"]),
    ],
    targets: [
        .executableTarget(name: "tidemark", path: "Sources/tidemark"),
    ],
    swiftLanguageModes: [.v5]
)
