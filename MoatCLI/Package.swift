// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MoatCLI",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "moat", targets: ["MoatCLI"]),
    ],
    dependencies: [
        .package(path: "../MoatKit"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(name: "VersionGenerator"),
        .plugin(
            name: "VersionPlugin",
            capability: .buildTool(),
            dependencies: ["VersionGenerator"],
        ),
        .executableTarget(
            name: "MoatCLI",
            dependencies: [
                .product(name: "MoatKit", package: "MoatKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                // Apple platforms have System in the SDK.
                .product(
                    name: "SystemPackage",
                    package: "swift-system",
                    condition: .when(platforms: [.linux]),
                ),
            ],
            plugins: ["VersionPlugin"],
        ),
        .testTarget(name: "MoatCLITests", dependencies: ["MoatCLI"]),
    ],
)
