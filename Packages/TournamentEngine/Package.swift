// swift-tools-version: 6.0

import PackageDescription

// TournamentEngine depends on PokerCore and nothing else, deliberately.
//
// This slice is pure integer tournament structure: a blind schedule that steps
// by hand index and an effective-depth calculation. It borrows PokerCore's
// vocabulary (cards, positions) for later slices, but it must never see
// StrategyContent, TrainingDomain or SessionSimulation — the tournament rules
// are facts about the structure, not about what a player should do, and the
// moment this package can see teaching content the temptation is to fold the
// answer into the structure.
//
// This dependency list is the enforcement point. Adding to it is the specific
// failure the layering gate exists to prevent.
let package = Package(
    name: "TournamentEngine",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "TournamentEngine", targets: ["TournamentEngine"]),
    ],
    dependencies: [
        .package(path: "../PokerCore"),
    ],
    targets: [
        .target(
            name: "TournamentEngine",
            dependencies: [
                .product(name: "PokerCore", package: "PokerCore"),
            ],
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors", "-strict-concurrency=complete"]),
            ]
        ),
        .testTarget(
            name: "TournamentEngineTests",
            dependencies: [
                "TournamentEngine",
                .product(name: "PokerCore", package: "PokerCore"),
            ],
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors", "-strict-concurrency=complete"]),
            ]
        ),
    ]
)
