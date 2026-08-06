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
            dependencies: ["PokerCore"]
        ),
        .testTarget(name: "StrategyContentTests", dependencies: ["StrategyContent"]),
    ]
)
