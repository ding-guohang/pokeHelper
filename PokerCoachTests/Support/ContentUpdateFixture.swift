import CryptoKit
import Foundation
import StrategyContent
@testable import PokerCoach

/// Packs for the update tests, built by re-encoding the bundled core content at
/// a different version.
///
/// Reusing real shipped content rather than a hand-written blob keeps these
/// tests honest about what the loader will actually be asked to parse.
enum ContentUpdateFixture {
    enum FixtureError: Error {
        case bundledContentMissing
    }

    static func pack(contentVersion: String) throws -> StrategyPack {
        try StrategyPackLoader().load(
            data: try encodedPack(contentVersion: contentVersion),
            expectedSHA256: nil
        )
    }

    /// An offer whose pack is unverifiedDraft, for checking that availability
    /// follows the pack that was actually adopted.
    static func unverifiedOffer(contentVersion: String) throws -> ContentUpdateOffer {
        let data = try encodedPack(
            contentVersion: contentVersion,
            reviewStatus: "unverifiedDraft"
        )
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return ContentUpdateOffer(
            data: data,
            declaredSHA256: digest,
            contentVersion: contentVersion
        )
    }

    static func encodedPack(
        contentVersion: String,
        reviewStatus: String? = nil
    ) throws -> Data {
        guard let url = Bundle.main.url(
            forResource: "CoreStrategyPack",
            withExtension: "json"
        ) else {
            throw FixtureError.bundledContentMissing
        }

        var root = try JSONSerialization.jsonObject(
            with: try Data(contentsOf: url)
        ) as! [String: Any]
        var manifest = root["manifest"] as! [String: Any]
        manifest["contentVersion"] = contentVersion
        if let reviewStatus {
            manifest["reviewStatus"] = reviewStatus
            if reviewStatus == "reviewed" {
                manifest["reviewedBy"] = "fixture"
                manifest["reviewedAt"] = "2026-08-10T00:00:00Z"
            } else {
                manifest["reviewedBy"] = NSNull()
                manifest["reviewedAt"] = NSNull()
            }
        }
        root["manifest"] = manifest

        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.sortedKeys]
        )
    }
}
