// swift-tools-version: 6.0

import PackageDescription

// Entitlements depends on nothing, deliberately.
//
// This package is the pure-domain mechanism for premium access: an entitlement
// status with time-based validity and a resolver that gates feature keys by a
// policy. It must never see StoreKit, the network, persistence, or any other
// package — where an entitlement comes from is an infrastructure concern, and
// *which* features are premium is a product decision carried in the policy data,
// not baked into this mechanism. The empty allow-list in the layering gate is
// the enforcement point.
let package = Package(
    name: "Entitlements",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "Entitlements", targets: ["Entitlements"]),
    ],
    targets: [
        .target(
            name: "Entitlements",
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors", "-strict-concurrency=complete"]),
            ]
        ),
        .testTarget(
            name: "EntitlementsTests",
            dependencies: ["Entitlements"],
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors", "-strict-concurrency=complete"]),
            ]
        ),
    ]
)
