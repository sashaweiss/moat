// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MoatKit",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "MoatKit", targets: ["MoatKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.5.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "1.0.1"),
    ],
    targets: [
        .target(name: "CMoatKit"),
        .target(
            name: "MoatKit",
            dependencies: [
                "CMoatKit",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Subprocess", package: "swift-subprocess"),
                // Apple platforms have System in the SDK.
                .product(
                    name: "SystemPackage",
                    package: "swift-system",
                    condition: .when(platforms: [.linux]),
                ),
            ],
        ),
        .testTarget(
            name: "MoatKitTests",
            dependencies: [
                "MoatKit",
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(
                    name: "SystemPackage",
                    package: "swift-system",
                    condition: .when(platforms: [.linux]),
                ),
            ],
        ),
    ],
)
