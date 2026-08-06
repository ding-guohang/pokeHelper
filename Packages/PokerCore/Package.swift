// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PokerCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "PokerCore", targets: ["PokerCore"]),
    ],
    targets: [
        .target(
            name: "PokerCore",
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "PokerCoreTests",
            dependencies: ["PokerCore"],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
    ]
)
