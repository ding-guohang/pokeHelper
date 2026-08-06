// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StrategyContent",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "StrategyContent", targets: ["StrategyContent"]),
    ],
    dependencies: [
        .package(path: "../PokerCore"),
    ],
    targets: [
        .target(
            name: "StrategyContent",
            dependencies: ["PokerCore"],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "StrategyContentTests",
            dependencies: ["StrategyContent"],
            resources: [.process("Fixtures")],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
    ]
)
