// swift-tools-version: 6.0

import PackageDescription

// SessionSimulation depends on PokerCore and nothing else, deliberately.
//
// The engine deals cards, runs a betting round and settles a pot. It does not
// know that teaching content exists, and it must not learn: the moment it can
// see `StrategyContent`, the cheapest way to answer "is this decision point
// worth comparing against content?" is to look the answer up here, and the
// answer to that question stops being a fact about the hand. Session hands
// carry a `SpotSignature` (defined in PokerCore) and the app layer — the only
// layer that can see both sides — does the comparing.
//
// `TrainingDomain` is excluded for the same reason from the other direction:
// it would close a cycle, because the engine would then have to ask the
// training layer questions while advancing a hand.
//
// This dependency list is the enforcement point. Adding to it is the specific
// failure the design exists to prevent.
let package = Package(
    name: "SessionSimulation",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "SessionSimulation", targets: ["SessionSimulation"]),
    ],
    dependencies: [
        .package(path: "../PokerCore"),
    ],
    targets: [
        .target(
            name: "SessionSimulation",
            dependencies: [
                .product(name: "PokerCore", package: "PokerCore"),
            ],
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors", "-strict-concurrency=complete"]),
            ]
        ),
        // Exists so a test can run dealing in a process that is not the test
        // process. Cross-process determinism is the only property here that
        // cannot be observed from inside a single process: per-process hash
        // seeding and `SystemRandomNumberGenerator` are both stable within one
        // launch, so calling a function twice in one process proves nothing
        // about either.
        .executableTarget(
            name: "session-transcript",
            dependencies: [
                "SessionSimulation",
                .product(name: "PokerCore", package: "PokerCore"),
            ],
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors", "-strict-concurrency=complete"]),
            ]
        ),
        .testTarget(
            name: "SessionSimulationTests",
            dependencies: [
                "SessionSimulation",
                // A dependency rather than a convention, so `swift test` is
                // guaranteed to have built the binary the determinism test
                // shells out to.
                "session-transcript",
                .product(name: "PokerCore", package: "PokerCore"),
            ],
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors", "-strict-concurrency=complete"]),
            ]
        ),
    ]
)
