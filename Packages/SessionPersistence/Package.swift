// swift-tools-version: 6.0

import PackageDescription

// Where a session goes on disk.
//
// Separate from `SessionSimulation` for the reason `TrainingPersistence` is
// separate from `TrainingDomain`: a JSON Lines file store is a storage
// implementation, and the engine that deals cards has no business knowing there
// is a filesystem. The dependency runs persistence -> engine and never back.
//
// It is a package rather than a folder in the app target because of one test.
// "The process terminates at hand 7" has to mean a process that terminates:
// this package's tests spawn `session-record-writer`, let it play seven hands,
// and have it kill itself with SIGKILL. An in-process stand-in — a view model
// that is torn down, an actor that is released — satisfies a weaker reading of
// the same sentence and would not have caught a resume that re-derives the deal
// from index 0. `Process` is unavailable on iOS, so the app's XCTest bundle
// cannot host that test at all.
let package = Package(
    name: "SessionPersistence",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "SessionPersistence", targets: ["SessionPersistence"]),
    ],
    dependencies: [
        .package(path: "../PokerCore"),
        .package(path: "../SessionSimulation"),
    ],
    targets: [
        .target(
            name: "SessionPersistence",
            dependencies: [
                .product(name: "PokerCore", package: "PokerCore"),
                .product(name: "SessionSimulation", package: "SessionSimulation"),
            ],
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors", "-strict-concurrency=complete"]),
            ]
        ),
        // Plays a session in a process that can be killed. See the note above.
        .executableTarget(
            name: "session-record-writer",
            dependencies: [
                "SessionPersistence",
                .product(name: "SessionSimulation", package: "SessionSimulation"),
            ],
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors", "-strict-concurrency=complete"]),
            ]
        ),
        .testTarget(
            name: "SessionPersistenceTests",
            dependencies: [
                "SessionPersistence",
                // A dependency rather than a convention, so `swift test` is
                // guaranteed to have built the binary the resume test kills.
                "session-record-writer",
                .product(name: "PokerCore", package: "PokerCore"),
                .product(name: "SessionSimulation", package: "SessionSimulation"),
            ],
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors", "-strict-concurrency=complete"]),
            ]
        ),
    ]
)
