// swift-tools-version: 6.0

import PackageDescription

// The concrete local storage for training events, kept out of the domain.
//
// `layering.md` rule 3 says TrainingDomain must not depend on a storage
// implementation, and a JSON Lines file store sitting beside the scorer, the
// player model and the planner was exactly that. The protocol
// `TrainingEventStore` stays in the domain package; this package is the only
// thing that knows there is a file.
//
// It is a package rather than a folder in the app target because its tests are
// about real concurrency — interleaved appends from two live stores, a stale
// store refusing to overwrite a file that was corrupted underneath it, ordering
// under equal timestamps. Those tests run unchanged here. Rewriting them as
// XCTest to fit them into the app bundle would have been a rewrite of the
// concurrency coverage during a move, which is how coverage quietly gets
// weaker.
let package = Package(
    name: "TrainingPersistence",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "TrainingPersistence", targets: ["TrainingPersistence"]),
    ],
    dependencies: [
        .package(path: "../PokerCore"),
        .package(path: "../TrainingDomain"),
    ],
    targets: [
        .target(
            name: "TrainingPersistence",
            dependencies: [
                .product(name: "TrainingDomain", package: "TrainingDomain"),
            ],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "TrainingPersistenceTests",
            dependencies: [
                "TrainingPersistence",
                // The event fixture builds a real `TrainingEvent`, whose
                // submission and grade are PokerCore values.
                .product(name: "PokerCore", package: "PokerCore"),
                .product(name: "TrainingDomain", package: "TrainingDomain"),
            ],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
    ]
)
