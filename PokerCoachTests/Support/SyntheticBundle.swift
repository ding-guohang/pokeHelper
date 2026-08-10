import CryptoKit
import Foundation
import StrategyContent
@testable import PokerCoach

/// A resource lookup built in memory, so the loader can be driven against
/// bundles that cannot be produced by a build: retired content, a corrupt
/// pack, a missing digest.
struct SyntheticBundle {
    let packs: [String: ReviewStatus]
    var corrupting: Set<String> = []
    var withoutChecksums: Set<String> = []

    func lookup(_ name: String) -> BundledContentLoader.Resource? {
        guard let status = packs[name] else { return nil }

        var data = (try? ContentUpdateFixture.encodedPack(
            contentVersion: "2026.08.10",
            reviewStatus: status.rawValue
        )) ?? Data()

        let honestDigest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()

        if corrupting.contains(name) {
            // Change the bytes and keep the digest, which is what a tampered
            // resource in a repackaged build looks like.
            data.append(contentsOf: " ".utf8)
        }

        return BundledContentLoader.Resource(
            name: name,
            data: data,
            recordedSHA256: withoutChecksums.contains(name) ? nil : honestDigest
        )
    }
}
