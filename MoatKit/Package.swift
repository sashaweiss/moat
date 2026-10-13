// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "moat",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "MoatKit", targets: ["MoatKit"]),
        .executable(name: "moat", targets: ["MoatCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0"),
    ],
    targets: [
        .target(
            name: "MoatKit",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
            ],
        ),
        .executableTarget(
            name: "MoatCLI",
            dependencies: [
                "MoatKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
        ),
        .testTarget(
            name: "MoatKitTests",
            dependencies: ["MoatKit"],
        ),
    ],
)
