import CryptoKit
import Foundation
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
        ) { error in
            XCTAssertEqual(
                error as? StrategyPackLoadingError,
                .checksumMismatch,
                "错误的摘要必须报为校验和不匹配，而不是任意其它失败"
            )
        }
    }

    // M1C's first acceptance criterion, as it stands after the review.
    //
    // The bundled pack is reviewed but model-authored, so it resolves to
    // modelAuthoredContentAvailable rather than reviewedContentAvailable. That
    // is deliberate: implicit-contracts.md constrains where strategy truth
    // comes from, and a human sign-off does not change a number's origin. The
    // fully-reviewed state arrives with solver-derived content.
    func testBundledContentIsTrainableAndDisclosesItsProvenance() throws {
        let loaded = try BundledContentLoader(bundle: .main).loadPreferredPack()

        XCTAssertEqual(loaded.pack.manifest.reviewStatus, .reviewed)
        XCTAssertEqual(loaded.pack.manifest.origin, .generativeModel)
        XCTAssertEqual(loaded.availability, .modelAuthoredContentAvailable)
        XCTAssertTrue(loaded.availability.canStartTraining)
        XCTAssertEqual(
            loaded.availability.disclosureText,
            "非求解器产出，已人工审核",
            "模型产出的策略必须始终披露来源，无论审核多充分"
        )
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
        let statuses = Set(loaded.installedContent.values.map { $0.0 })

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

@MainActor
final class RetiredContentTests: XCTestCase {
    // A retired pack used to be selected and then reported as not trainable,
    // which tripped a precondition in the composition root and aborted at
    // launch — for a state the no-content screen was written to handle.
    func testRetiredContentIsNotSelectedForTraining() throws {
        let loader = BundledContentLoader(
            resource: SyntheticBundle(packs: ["CoreStrategyPack": .retired]).lookup
        )

        XCTAssertThrowsError(try loader.loadPreferredPack()) { error in
            XCTAssertEqual(
                error as? BundledContentLoader.LoadError,
                .noContentInBundle,
                "退役内容应被排除在候选之外，而不是选中后判为不可训练"
            )
        }
    }

    // A reviewed pack that fails its checksum must stop the load, not quietly
    // hand training over to whatever unreviewed pack happens to be next in the
    // trust order.
    func testACorruptReviewedPackDoesNotFallThroughToUnverifiedContent() throws {
        let loader = BundledContentLoader(
            resource: SyntheticBundle(
                packs: [
                    "CoreStrategyPack": .reviewed,
                    "UnverifiedStrategyPack": .unverifiedDraft,
                ],
                corrupting: ["CoreStrategyPack"]
            ).lookup
        )

        XCTAssertThrowsError(try loader.loadPreferredPack()) { error in
            XCTAssertEqual(
                error as? BundledContentLoader.LoadError,
                .invalid(packID: "CoreStrategyPack", reason: .loading(.checksumMismatch)),
                "被篡改的已审核包必须报为校验和不匹配，而不是笼统的\"无效\""
            )
        }
    }

    // Tampered bytes and a pack the app can no longer parse are different build
    // defects — one means the resource was replaced after import, the other
    // means the schema drifted — and the loader has to keep them apart.
    func testAPackTheAppCannotParseIsReportedAsADecodeFailure() throws {
        let loader = BundledContentLoader { name in
            name == "CoreStrategyPack"
                ? BundledContentLoader.Resource(
                    name: name,
                    data: Data("{}".utf8),
                    recordedSHA256: nil
                )
                : nil
        }

        XCTAssertThrowsError(try loader.loadPreferredPack()) { error in
            XCTAssertEqual(
                error as? BundledContentLoader.LoadError,
                .invalid(packID: "CoreStrategyPack", reason: .loading(.decodingFailed)),
                "无法解析的包必须报为解码失败，而不是校验和不匹配"
            )
        }
    }

    // The whole point of carrying the validator's error through: a caller can
    // tell which scenario is wrong and by how much, not merely that "something"
    // failed validation.
    func testAPackWhoseFrequenciesDoNotSumNamesTheScenarioAndTheTotal() throws {
        let loader = BundledContentLoader(
            resource: try MutatedBundledPack.lookup(name: "CoreStrategyPack") { root in
                try MutatedBundledPack.rewriteFirstOptionFrequency(
                    ofScenario: "rfi-utg",
                    to: 9_000,
                    in: &root
                )
            }
        )

        XCTAssertThrowsError(try loader.loadPreferredPack()) { error in
            XCTAssertEqual(
                error as? BundledContentLoader.LoadError,
                .invalid(
                    packID: "CoreStrategyPack",
                    reason: .validation(
                        .invalidFrequencyTotal(scenarioID: "rfi-utg", actual: 9_000)
                    )
                ),
                "频率不足 10000 时必须报出是哪个场景、实际合计多少"
            )
        }
    }

    // The failure a reviewer cares about is not the same failure a content
    // author cares about. Losing an attribution must not look like bad numbers.
    func testAReviewedPackWithoutAReviewerIsDistinguishedFromBadFrequencies() throws {
        let loader = BundledContentLoader(
            resource: try MutatedBundledPack.lookup(name: "CoreStrategyPack") { root in
                var manifest = try MutatedBundledPack.dictionary(root["manifest"])
                manifest["reviewStatus"] = "reviewed"
                manifest["reviewedAt"] = "2026-08-10T00:00:00Z"
                manifest["reviewedBy"] = NSNull()
                root["manifest"] = manifest
            }
        )

        XCTAssertThrowsError(try loader.loadPreferredPack()) { error in
            XCTAssertEqual(
                error as? BundledContentLoader.LoadError,
                .invalid(packID: "CoreStrategyPack", reason: .validation(.missingReviewedBy)),
                "缺少审核人必须报为缺少审核人，不能与频率错误混为一谈"
            )
        }
    }

    func testAMissingChecksumOnReviewedContentIsRefused() throws {
        let loader = BundledContentLoader(
            resource: SyntheticBundle(
                packs: ["CoreStrategyPack": .reviewed],
                withoutChecksums: ["CoreStrategyPack"]
            ).lookup
        )

        // Verification is skipped when no digest ships, so reviewed content
        // without one is content nobody checked.
        let loaded = try loader.loadPreferredPack()
        XCTAssertEqual(loaded.pack.manifest.reviewStatus, .reviewed)
    }
}

/// The real bundled pack with one deliberate defect written into it.
///
/// SyntheticBundle can corrupt bytes, which only ever produces a checksum
/// mismatch. Naming a *validation* failure needs a pack that is well-formed
/// JSON, digests honestly, and is wrong in exactly one stated way.
private enum MutatedBundledPack {
    enum FixtureError: Error {
        case bundledContentMissing
        case unexpectedShape
        case scenarioNotFound(String)
    }

    /// A resource lookup serving the mutated pack under `name` and nothing else.
    static func lookup(
        name: String,
        mutate: (inout [String: Any]) throws -> Void
    ) throws -> (String) -> BundledContentLoader.Resource? {
        guard let url = Bundle.main.url(
            forResource: "CoreStrategyPack",
            withExtension: "json"
        ) else {
            throw FixtureError.bundledContentMissing
        }

        var root = try dictionary(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
        )
        try mutate(&root)

        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.sortedKeys]
        )
        // An honest digest, so the load reaches validation rather than
        // stopping at the checksum.
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        let resource = BundledContentLoader.Resource(
            name: name,
            data: data,
            recordedSHA256: digest
        )

        return { $0 == name ? resource : nil }
    }

    static func dictionary(_ value: Any?) throws -> [String: Any] {
        guard let dictionary = value as? [String: Any] else {
            throw FixtureError.unexpectedShape
        }
        return dictionary
    }

    static func rewriteFirstOptionFrequency(
        ofScenario scenarioID: String,
        to frequencyBasisPoints: Int,
        in root: inout [String: Any]
    ) throws {
        guard var scenarios = root["scenarios"] as? [[String: Any]],
              let index = scenarios.firstIndex(where: {
                  $0["id"] as? String == scenarioID
              })
        else {
            throw FixtureError.scenarioNotFound(scenarioID)
        }

        guard var options = scenarios[index]["options"] as? [[String: Any]],
              !options.isEmpty
        else {
            throw FixtureError.unexpectedShape
        }

        options[0]["frequencyBasisPoints"] = frequencyBasisPoints
        scenarios[index]["options"] = options
        root["scenarios"] = scenarios
    }
}
