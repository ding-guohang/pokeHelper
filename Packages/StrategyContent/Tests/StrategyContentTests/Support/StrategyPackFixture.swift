import Foundation
import PokerCore
@testable import StrategyContent

/// Builds packs for tests that care about manifest and curriculum shape rather
/// than about scenario content. The scenario body is taken from the checked-in
/// valid pack so these tests stay focused on the field under test and do not
/// duplicate a full hand of poker data.
enum StrategyPackFixture {
    enum FixtureError: Error {
        case missingResource(String)
    }

    static func pack(
        reviewStatus: ReviewStatus = .testFixture,
        reviewedBy: String? = nil,
        reviewedAt: Date? = nil
    ) throws -> StrategyPack {
        let source = try loadedValidPack()
        return StrategyPack(
            manifest: StrategyPackManifest(
                id: source.manifest.id,
                schemaVersion: source.manifest.schemaVersion,
                contentVersion: source.manifest.contentVersion,
                reviewStatus: reviewStatus,
                generatedSource: source.manifest.generatedSource,
                reviewedBy: reviewedBy,
                reviewedAt: reviewedAt
            ),
            scenarios: source.scenarios
        )
    }

    private static func loadedValidPack() throws -> StrategyPack {
        guard let url = Bundle.module.url(
            forResource: "valid-pack",
            withExtension: "json"
        ) else {
            throw FixtureError.missingResource("valid-pack.json")
        }
        return try StrategyPackLoader().load(
            data: Data(contentsOf: url),
            expectedSHA256: nil
        )
    }
}
