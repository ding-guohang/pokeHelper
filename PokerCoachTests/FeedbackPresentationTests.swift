import SwiftUI
import XCTest
@testable import PokerCoach

final class FeedbackPresentationTests: XCTestCase {
    func testMixedStrategyKeepsEveryAvailableActionVisible() throws {
        let fixture = FeedbackFixture.mixedStrategy()
        let presentation = FeedbackPresentation(
            scenario: fixture.scenario,
            submission: fixture.submission,
            grade: fixture.grade
        )
        XCTAssertEqual(presentation.frequencyRows.count, 3)
        XCTAssertEqual(presentation.evLossText, "−0.020 BB")
        XCTAssertEqual(presentation.qualityText, "可接受")
        XCTAssertTrue(presentation.assumptions.contains("100BB"))
    }

    func testDevelopmentFixtureIsAlwaysDisclosed() throws {
        let presentation = FeedbackFixture.developmentPresentation()
        XCTAssertEqual(presentation.provenanceBadge, "开发演示数据")
    }

    func testProfessionalHierarchyRetainsRawStrategyEvidence() {
        let fixture = FeedbackFixture.mixedStrategy()
        let presentation = FeedbackPresentation(
            scenario: fixture.scenario,
            submission: fixture.submission,
            grade: fixture.grade,
            manifest: fixture.manifest
        )

        XCTAssertEqual(presentation.scoreText, "94 / 100")
        XCTAssertEqual(presentation.confidenceText, "信心：不确定")
        XCTAssertEqual(presentation.selectedActionText, "所选：下注到 2.17 BB")
        XCTAssertEqual(presentation.selectedEVText, "0.980 BB")
        XCTAssertEqual(presentation.bestEVText, "1.000 BB")
        XCTAssertEqual(presentation.frequencyRows[1].frequencyText, "35.0%")
        XCTAssertEqual(presentation.frequencyRows[1].evText, "0.980 BB")
        XCTAssertEqual(
            presentation.conclusion,
            "本节点保留过牌与两种下注频率。"
        )
        XCTAssertEqual(presentation.rangeCells.count, 1)
        XCTAssertEqual(presentation.rangeCells[0].handClass, "AKo")
        XCTAssertEqual(presentation.rangeCells[0].actionWeights.count, 3)
        XCTAssertEqual(presentation.reasoningSections.count, 4)
        XCTAssertEqual(
            presentation.gtoBaseline,
            "基线保留三个行动的混合策略。"
        )
        XCTAssertEqual(presentation.stackText, "100 BB")
        XCTAssertEqual(presentation.rakeText, "5% capped")
        XCTAssertEqual(presentation.betSizeTreeText, "2.17BB, 4.88BB")
        XCTAssertEqual(presentation.generatedSource, "feedback-unit-test")
        XCTAssertEqual(presentation.contentVersion, "1.2.3")
        XCTAssertEqual(presentation.reviewStatusText, "开发演示")
    }

    func testExploitAdjustmentRequiresAnExplicitCondition() {
        XCTAssertNil(FeedbackFixture.developmentPresentation().exploitAdjustment)
        XCTAssertEqual(
            FeedbackFixture.exploitPresentation().exploitAdjustment,
            "仅当对手过度弃牌时提高下注频率。"
        )
    }

    func testReviewedContentShowsItsVersion() {
        XCTAssertEqual(
            FeedbackFixture.reviewedPresentation().provenanceBadge,
            "已审核 · 2.0.0"
        )
    }

    func testFeedbackLayoutTracksHorizontalSizeClass() {
        XCTAssertEqual(
            ProfessionalFeedbackLayout(horizontalSizeClass: .compact),
            .singleColumn
        )
        XCTAssertEqual(
            ProfessionalFeedbackLayout(horizontalSizeClass: .regular),
            .splitColumns
        )
    }
}
