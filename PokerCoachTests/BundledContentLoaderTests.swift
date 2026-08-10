import StrategyContent
import XCTest
@testable import PokerCoach

final class BundledContentLoaderTests: XCTestCase {
    // GIVEN 设备从未联网、从未拉取内容
    // WHEN 加载随包内容
    // THEN 训练可用，且 pack 来自随包资源
    func testLoadsBundledContentWithoutNetwork() throws {
        let loaded = try BundledContentLoader(bundle: .main).loadPreferredPack()

        XCTAssertTrue(loaded.availability.canStartTraining)
        XCTAssertFalse(loaded.pack.scenarios.isEmpty)
        XCTAssertFalse(loaded.pack.curriculum.isEmpty)
    }

    // Every bundled pack must be readable, not just the preferred one: Review
    // needs each pack's review status to disclose the provenance of history
    // answered under it.
    func testReportsTheReviewStatusOfEveryBundledPack() throws {
        let loaded = try BundledContentLoader(bundle: .main).loadPreferredPack()

        XCTAssertFalse(loaded.installedContent.isEmpty)
        XCTAssertTrue(
            loaded.installedContent.keys.contains(loaded.pack.manifest.id)
        )
    }

    // The core pack ships with a checksum recorded at import time. Loading has
    // to verify it, or the recorded value is decoration.
    func testBundledCoreContentMatchesItsRecordedChecksum() throws {
        let bundle = Bundle.main
        let packURL = try XCTUnwrap(
            bundle.url(forResource: "CoreStrategyPack", withExtension: "json")
        )
        let checksumURL = try XCTUnwrap(
            bundle.url(forResource: "CoreStrategyPack", withExtension: "sha256")
        )
        let recorded = try String(contentsOf: checksumURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Loading with the recorded checksum must succeed, and with a wrong one
        // must not — otherwise the loader is ignoring the argument.
        let data = try Data(contentsOf: packURL)
        XCTAssertNoThrow(
            try StrategyPackLoader().load(data: data, expectedSHA256: recorded)
        )
        XCTAssertThrowsError(
            try StrategyPackLoader().load(
                data: data,
                expectedSHA256: String(repeating: "0", count: 64)
            )
        )
    }

    // M1C's first acceptance criterion. This was a conditional while no
    // reviewed content existed; it is unconditional now that some does, so
    // regressing the core pack to unverifiedDraft fails here rather than
    // quietly shipping a build that cannot reach the App Store.
    func testBundledContentIsReviewedAndTrainable() throws {
        let loaded = try BundledContentLoader(bundle: .main).loadPreferredPack()

        XCTAssertEqual(loaded.pack.manifest.reviewStatus, .reviewed)
        XCTAssertEqual(loaded.availability, .reviewedContentAvailable)
        XCTAssertTrue(loaded.availability.canStartTraining)
    }

    // Reviewed content has to name who reviewed it and when. The validator
    // enforces this on load; asserting it here means a pack that lost its
    // attribution fails as a missing signature rather than as a decode error.
    func testReviewedContentCarriesItsAttribution() throws {
        let loaded = try BundledContentLoader(bundle: .main).loadPreferredPack()
        let manifest = loaded.pack.manifest

        let reviewer = try XCTUnwrap(manifest.reviewedBy)
        XCTAssertFalse(reviewer.trimmingCharacters(in: .whitespaces).isEmpty)
        XCTAssertNotNil(manifest.reviewedAt)
    }

    // The dogfooding build still carries unverified content alongside it, and
    // the trust ordering has to prefer the reviewed pack for training.
    func testPrefersReviewedContentOverUnverifiedWhenBothArePresent() throws {
        let loaded = try BundledContentLoader(bundle: .main).loadPreferredPack()
        let statuses = Set(loaded.installedContent.values)

        if statuses.contains(.unverifiedDraft) {
            XCTAssertEqual(
                loaded.pack.manifest.reviewStatus,
                .reviewed,
                "同时存在两种内容时必须训练已审核的那份"
            )
        }
    }

    // A bundle with nothing in it must say so rather than return a placeholder.
    func testReportsMissingContentRatherThanReturningAnEmptyPack() throws {
        XCTAssertThrowsError(
            try BundledContentLoader(bundle: Bundle(for: XCTestCase.self))
                .loadPreferredPack()
        ) { error in
            XCTAssertEqual(
                error as? BundledContentLoader.LoadError,
                .noContentInBundle
            )
        }
    }
}
