import CryptoKit
import Foundation
import StrategyContent
import XCTest
@testable import PokerCoach

@MainActor
final class ContentUpdateCoordinatorTests: XCTestCase {
    // The positive path is written first. Without it, a coordinator whose
    // checkForUpdate body is `return .noCandidate` satisfies every rejection
    // case below.
    func testAdoptsAVerifiedHigherVersion() async throws {
        let coordinator = makeCoordinator(
            currentVersion: "2026.08.06",
            offering: try offer(contentVersion: "2026.09.01")
        )

        let outcome = try await coordinator.checkForUpdate()

        XCTAssertEqual(outcome, .adopted(contentVersion: "2026.09.01"))
        XCTAssertEqual(coordinator.currentPack.manifest.contentVersion, "2026.09.01")
    }

    func testRejectsAPackWhoseChecksumDoesNotMatch() async throws {
        let coordinator = makeCoordinator(
            currentVersion: "2026.08.06",
            offering: try offer(contentVersion: "2026.09.01", corruptChecksum: true)
        )

        let outcome = try await coordinator.checkForUpdate()

        XCTAssertEqual(outcome, .rejected(.checksumMismatch))
        XCTAssertEqual(coordinator.currentPack.manifest.contentVersion, "2026.08.06")
    }

    func testIgnoresAnEqualVersion() async throws {
        let coordinator = makeCoordinator(
            currentVersion: "2026.08.06",
            offering: try offer(contentVersion: "2026.08.06")
        )

        let outcome = try await coordinator.checkForUpdate()

        XCTAssertEqual(outcome, .ignored(.notNewer))
        XCTAssertEqual(coordinator.currentPack.manifest.contentVersion, "2026.08.06")
    }

    func testIgnoresAnOlderVersion() async throws {
        let coordinator = makeCoordinator(
            currentVersion: "2026.09.01",
            offering: try offer(contentVersion: "2026.08.06")
        )

        let outcome = try await coordinator.checkForUpdate()

        XCTAssertEqual(outcome, .ignored(.notNewer))
        XCTAssertEqual(coordinator.currentPack.manifest.contentVersion, "2026.09.01")
    }

    // 拒绝更新不能退化成「没有内容」——训练必须继续可用。
    func testKeepsTrainingAvailableAfterARejectedUpdate() async throws {
        let coordinator = makeCoordinator(
            currentVersion: "2026.08.06",
            offering: try offer(contentVersion: "2026.09.01", corruptChecksum: true)
        )

        _ = try await coordinator.checkForUpdate()

        XCTAssertTrue(coordinator.availability.canStartTraining)
    }

    func testReportsNoCandidateWhenTheSourceOffersNothing() async throws {
        let coordinator = ContentUpdateCoordinator(
            current: try ContentUpdateFixture.pack(contentVersion: "2026.08.06"),
            availability: .unverifiedContentAvailable,
            source: StubContentUpdateSource(offer: nil)
        )

        let outcome = try await coordinator.checkForUpdate()

        XCTAssertEqual(outcome, .noCandidate)
    }

    // Version comparison must be numeric. "2026.10.01" sorts before "2026.9.01"
    // as text, so a string comparison would refuse a genuinely newer pack every
    // October.
    func testComparesVersionsNumericallyNotAsText() throws {
        let october = try XCTUnwrap(ContentVersion("2026.10.01"))
        let september = try XCTUnwrap(ContentVersion("2026.9.01"))

        XCTAssertTrue(september < october)
        XCTAssertFalse(october < september)
        XCTAssertTrue("2026.10.01" < "2026.9.01", "前提：字符串比较确实是反的")
    }

    func testTreatsPaddedAndUnpaddedComponentsAsEqual() throws {
        XCTAssertEqual(ContentVersion("2026.09.01"), ContentVersion("2026.9.1"))
    }

    func testRejectsAnUnparseableVersionRatherThanGuessing() async throws {
        let coordinator = makeCoordinator(
            currentVersion: "2026.08.06",
            offering: try offer(contentVersion: "next")
        )

        let outcome = try await coordinator.checkForUpdate()

        XCTAssertEqual(outcome, .rejected(.unparseableVersion))
    }

    // MARK: - Harness

    private func makeCoordinator(
        currentVersion: String,
        offering offer: ContentUpdateOffer
    ) -> ContentUpdateCoordinator {
        ContentUpdateCoordinator(
            current: try! ContentUpdateFixture.pack(contentVersion: currentVersion),
            availability: .unverifiedContentAvailable,
            source: StubContentUpdateSource(offer: offer)
        )
    }

    private func offer(
        contentVersion: String,
        corruptChecksum: Bool = false
    ) throws -> ContentUpdateOffer {
        let data = try ContentUpdateFixture.encodedPack(contentVersion: contentVersion)
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()

        return ContentUpdateOffer(
            data: data,
            declaredSHA256: corruptChecksum ? String(repeating: "0", count: 64) : digest,
            contentVersion: contentVersion
        )
    }
}

private struct StubContentUpdateSource: ContentUpdateSource {
    let offer: ContentUpdateOffer?

    func fetchCandidate() async throws -> ContentUpdateOffer? { offer }
}

@MainActor
final class ContentUpdateReachabilityTests: XCTestCase {
    // The coordinator previously had zero production callers: 130 lines and
    // nine green tests describing behaviour no build could reach. These assert
    // the path from the composition root exists.
    func testDependenciesInstallTheCoordinator() throws {
        let dependencies = AppDependencies.availableContent(
            eventStore: InMemoryTrainingEventStore(events: []),
            strategyPack: try ContentUpdateFixture.pack(contentVersion: "2026.08.10"),
            strategyContentAvailability: .reviewedContentAvailable
        )

        XCTAssertNotNil(
            dependencies.contentUpdate,
            "内容更新没有接进依赖组装，能力在 App 里不可达"
        )
    }

    func testCheckingForUpdatesReportsNoCandidateWithTheBundledOnlySource() async throws {
        let dependencies = AppDependencies.availableContent(
            eventStore: InMemoryTrainingEventStore(events: []),
            strategyPack: try ContentUpdateFixture.pack(contentVersion: "2026.08.10"),
            strategyContentAvailability: .reviewedContentAvailable
        )

        let outcome = await dependencies.checkForContentUpdate()

        XCTAssertEqual(outcome, .noCandidate)
    }

    // Availability must follow the adopted pack. It was asserted only on the
    // rejection path, where the code is guaranteed not to touch it, so the
    // whole mapping could have been a constant.
    func testAdoptingAnUnverifiedPackDowngradesAvailability() async throws {
        let coordinator = ContentUpdateCoordinator(
            current: try ContentUpdateFixture.pack(contentVersion: "2026.08.06"),
            availability: .reviewedContentAvailable,
            source: StubUpdateSource(
                offer: try ContentUpdateFixture.unverifiedOffer(
                    contentVersion: "2026.09.01"
                )
            )
        )

        let outcome = try await coordinator.checkForUpdate()

        XCTAssertEqual(outcome, .adopted(contentVersion: "2026.09.01"))
        XCTAssertEqual(coordinator.availability, .unverifiedContentAvailable)
    }
}

private struct StubUpdateSource: ContentUpdateSource {
    let offer: ContentUpdateOffer?
    func fetchCandidate() async throws -> ContentUpdateOffer? { offer }
}
