import Foundation
import HandHistory
import PokerCore
import StrategyContent
import XCTest
@testable import PokerCoach

/// Each hero decision in a replayed hand is compared to installed content the
/// same way analysis and played sessions are: a covered node reports the
/// covering range's own table weight and the scenario a drill would run; an
/// uncovered node reports nothing. Never a fabricated frequency, never a grade.
final class HandReplayCounterfactualTests: XCTestCase {
    /// The hero's preflop decision in appendix A: a BTN open of AKo, 100BB deep,
    /// unopened — the node a `rfi-btn`-shaped scenario covers.
    @MainActor
    private func appendixAPreflopSignature() throws -> HeroDecisionSignature {
        let signatures = try ObservedHand.parsed(HandImportFixtureText.appendixA)
            .heroDecisionSignatures()
        return try XCTUnwrap(
            signatures.first { $0.signature.street == .preflop },
            "附录 A 应有一个翻前英雄决策"
        )
    }

    // GIVEN 装入覆盖附录 A 翻前节点的内容，权重 6234
    // WHEN 逐节点求反事实
    // THEN 翻前节点 covered，权重==6234==对该场景查表所得，且暴露补救 scenarioID
    @MainActor
    func testCoveredPreflopNodeExposesTableWeightAndRemediationID() throws {
        let hand = try ObservedHand.parsed(HandImportFixtureText.appendixA)
        let preflop = try appendixAPreflopSignature()

        // A non-round weight so a constant-`covered` stub answering 10,000 cannot
        // pass.
        let scenario = try HandLabContentFixture.scenario(
            id: "covers-appendixA-preflop",
            covering: preflop.signature.coverageKey,
            handClass: preflop.signature.handClass,
            actionKey: RangeBaseline.raiseKey,
            weightBasisPoints: 6_234
        )
        let matcher = ImportedHandContentMatcher(scenarios: [scenario])

        let counterfactuals = heroNodeCounterfactuals(of: hand, matcher: matcher)
        let node = try XCTUnwrap(
            counterfactuals.first { $0.signature.signature.street == .preflop },
            "回放应产出翻前节点"
        )

        // The weight is the covering scenario's own table lookup, not a number
        // the presentation invented.
        let expected = scenario.rangeWeightBasisPoints(
            forHandClass: preflop.signature.handClass,
            action: .raise(to: BBAmount(centiBB: 300))
        )
        XCTAssertEqual(expected, 6_234)
        XCTAssertEqual(node.weightBasisPoints, 6_234)
        XCTAssertEqual(node.remediationScenarioID, "covers-appendixA-preflop")
        XCTAssertEqual(
            node.coverage,
            .covered(scenarioID: "covers-appendixA-preflop", weightBasisPoints: 6_234)
        )

        // Postflop hero nodes are uncovered against preflop-only content — no
        // weight, no remediation — so a covered preflop node and an uncovered
        // postflop one appear paired rather than everything being covered.
        let postflop = counterfactuals.filter { $0.signature.signature.street != .preflop }
        XCTAssertFalse(postflop.isEmpty, "附录 A 应有翻后英雄决策")
        for node in postflop {
            XCTAssertEqual(node.coverage, .uncovered)
            XCTAssertNil(node.weightBasisPoints)
            XCTAssertNil(node.remediationScenarioID)
        }
    }

    // GIVEN 内容为空
    // WHEN 逐节点求反事实
    // THEN 所有节点 uncovered（与命中成对，排除恒 covered）
    @MainActor
    func testEmptyContentLeavesEveryNodeUncovered() throws {
        let hand = try ObservedHand.parsed(HandImportFixtureText.appendixA)
        let matcher = ImportedHandContentMatcher(scenarios: [])

        let counterfactuals = heroNodeCounterfactuals(of: hand, matcher: matcher)
        XCTAssertFalse(counterfactuals.isEmpty, "附录 A 应有英雄决策")
        for node in counterfactuals {
            XCTAssertEqual(node.coverage, .uncovered)
            XCTAssertNil(node.weightBasisPoints)
        }
    }
}
