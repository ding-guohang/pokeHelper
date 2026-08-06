// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TrainingDomain",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "TrainingDomain", targets: ["TrainingDomain"]),
    ],
    dependencies: [
        .package(path: "../PokerCore"),
        .package(path: "../StrategyContent"),
    ],
    targets: [
        .target(
            name: "TrainingDomain",
            dependencies: ["PokerCore", "StrategyContent"]
        ),
        .testTarget(name: "TrainingDomainTests", dependencies: ["TrainingDomain"]),
    ]
)
