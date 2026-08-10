import StrategyContent
import XCTest
@testable import PokerCoach

final class StrategyContentDisclosureTests: XCTestCase {
    // GIVEN testFixture 内容
    // THEN 显示「开发演示数据」
    func testDevelopmentFixtureIsLabelledAsDemonstrationData() {
        XCTAssertEqual(
            StrategyContentAvailability.developmentFixtureAvailable.disclosureText,
            "开发演示数据"
        )
    }

    // GIVEN unverifiedDraft 内容
    // THEN 显示「未经策略审核」，且与开发数据的文案不同
    func testUnverifiedDraftIsLabelledAsUnreviewed() {
        let unverified = StrategyContentAvailability
            .unverifiedContentAvailable.disclosureText

        XCTAssertEqual(unverified, "未经策略审核")
        // The two strings have to differ. A single reused banner would satisfy
        // "a disclosure is shown" while telling the user the wrong thing about
        // which kind of content they are training against.
        XCTAssertNotEqual(
            unverified,
            StrategyContentAvailability.developmentFixtureAvailable.disclosureText
        )
    }

    // 未审核内容不阻断训练——dogfooding 的整个意义在此。
    func testUnverifiedContentStillAllowsTraining() {
        XCTAssertTrue(
            StrategyContentAvailability.unverifiedContentAvailable.canStartTraining
        )
    }

    func testOnlyMissingReviewedContentBlocksTraining() {
        XCTAssertFalse(
            StrategyContentAvailability.reviewedContentUnavailable.canStartTraining
        )
        XCTAssertTrue(
            StrategyContentAvailability.reviewedContentAvailable.canStartTraining
        )
    }

    // 披露由审核状态决定，不由 pack ID 决定。
    func testDisclosureIsDerivedFromReviewStatus() {
        XCTAssertEqual(
            StrategyContentMetadata.disclosure(forReviewStatus: .testFixture, origin: .fixture),
            "开发演示数据"
        )
        XCTAssertEqual(
            StrategyContentMetadata.disclosure(forReviewStatus: .unverifiedDraft, origin: .fixture),
            "未经策略审核"
        )
        XCTAssertEqual(
            StrategyContentMetadata.disclosure(forReviewStatus: .retired, origin: .fixture),
            "已停用内容"
        )
        XCTAssertNil(
            StrategyContentMetadata.disclosure(forReviewStatus: .reviewed, origin: .fixture)
        )
    }

    // Human review does not silence provenance: model-authored strategy is
    // disclosed however thoroughly it was checked, because review says someone
    // looked, not that the numbers came from a solver.
    func testModelAuthoredContentIsDisclosedEvenWhenReviewed() {
        XCTAssertEqual(
            StrategyContentMetadata.disclosure(
                forReviewStatus: .reviewed,
                origin: .generativeModel
            ),
            "非求解器产出，已人工审核"
        )
        XCTAssertNil(
            StrategyContentMetadata.disclosure(
                forReviewStatus: .reviewed,
                origin: .solver
            )
        )
    }

    // Every unreviewed status must produce a distinct string, so a reader can
    // tell demonstration data from unverified strategy from retired content.
    func testEveryUnreviewedStatusHasItsOwnWording() {
        let disclosures = [ReviewStatus.testFixture, .unverifiedDraft, .retired]
            .compactMap {
                StrategyContentMetadata.disclosure(forReviewStatus: $0, origin: .fixture)
            }

        XCTAssertEqual(disclosures.count, 3)
        XCTAssertEqual(Set(disclosures).count, 3, "两种未审核状态共用了同一条文案")
    }
}
