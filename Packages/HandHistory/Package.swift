// swift-tools-version: 6.0

import PackageDescription

// The parse of a real hand.
//
// `SessionSimulation` deals hands the app itself dealt: fixed six seats, hero in
// seat 0, every hole card known, rake always zero, no raw text. A hand a user
// played online is none of those things, so the observed model lives here and
// is defined from scratch. This package sees only `PokerCore` — `Card`,
// `BBAmount`, `TablePosition`, `Street` — because a text-to-model function has
// no business knowing there is a filesystem, a UI or a training event; those
// live above it and depend on it, never the other way round.
//
// It carries an executable for the same reason `SessionPersistence` does: the
// cross-process determinism test has to be two processes. `hand-model-writer`
// parses a fixture and prints its `canonicalJSON()`; the test runs it twice and
// compares the bytes against each other and against the committed golden.
let package = Package(
    name: "HandHistory",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "HandHistory", targets: ["HandHistory"]),
    ],
    dependencies: [
        .package(path: "../PokerCore"),
    ],
    targets: [
        .target(
            name: "HandHistory",
            dependencies: [
                .product(name: "PokerCore", package: "PokerCore"),
            ],
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors", "-strict-concurrency=complete"]),
            ]
        ),
        // Parses a fixture in a process that can be launched twice. See note above.
        .executableTarget(
            name: "hand-model-writer",
            dependencies: [
                "HandHistory",
            ],
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors", "-strict-concurrency=complete"]),
            ]
        ),
        .testTarget(
            name: "HandHistoryTests",
            dependencies: [
                "HandHistory",
                // A dependency rather than a convention, so `swift test` is
                // guaranteed to have built the binary the determinism test runs.
                "hand-model-writer",
                .product(name: "PokerCore", package: "PokerCore"),
            ],
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors", "-strict-concurrency=complete"]),
            ]
        ),
    ]
)
