// swift-tools-version: 6.0

import PackageDescription

// Local authoring tools. Deliberately not referenced from project.yml: these
// targets exist to produce and check content on a developer machine and must
// never link into the shipped app.
let package = Package(
    name: "StrategyTooling",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "strategy-import", targets: ["strategy-import"]),
    ],
    dependencies: [
        .package(path: "../PokerCore"),
        .package(path: "../StrategyContent"),
        .package(path: "../TrainingDomain"),
    ],
    targets: [
        .target(
            name: "StrategyToolingCore",
            dependencies: [
                .product(name: "PokerCore", package: "PokerCore"),
                .product(name: "StrategyContent", package: "StrategyContent"),
                .product(name: "TrainingDomain", package: "TrainingDomain"),
            ],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
        .executableTarget(
            name: "strategy-import",
            dependencies: ["StrategyToolingCore"],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "StrategyToolingTests",
            dependencies: ["StrategyToolingCore"],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
    ]
)
