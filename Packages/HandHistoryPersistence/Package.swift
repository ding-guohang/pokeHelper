// swift-tools-version: 6.0

import PackageDescription

// Where an imported hand goes on disk.
//
// Separate from `HandHistory` for the reason `SessionPersistence` is separate
// from `SessionSimulation`: a versioned file store is a storage implementation,
// and the parser that turns text into an `ObservedHand` has no business knowing
// there is a filesystem. The dependency runs persistence -> HandHistory ->
// PokerCore and never back. It deliberately cannot see `TrainingDomain`: the
// path that writes a personal hand cannot reach a `TrainingEvent`, which is the
// structural half of "importing a hand produces no training event".
let package = Package(
    name: "HandHistoryPersistence",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "HandHistoryPersistence", targets: ["HandHistoryPersistence"]),
    ],
    dependencies: [
        .package(path: "../PokerCore"),
        .package(path: "../HandHistory"),
    ],
    targets: [
        .target(
            name: "HandHistoryPersistence",
            dependencies: [
                .product(name: "PokerCore", package: "PokerCore"),
                .product(name: "HandHistory", package: "HandHistory"),
            ],
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors", "-strict-concurrency=complete"]),
            ]
        ),
        .testTarget(
            name: "HandHistoryPersistenceTests",
            dependencies: [
                "HandHistoryPersistence",
                .product(name: "PokerCore", package: "PokerCore"),
                .product(name: "HandHistory", package: "HandHistory"),
            ],
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors", "-strict-concurrency=complete"]),
            ]
        ),
    ]
)
