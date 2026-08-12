import Foundation
import HandHistory
import PokerCore
import StrategyContent
import XCTest
@testable import PokerCoach

/// Which imported hero decisions installed content is allowed to be shown
/// against, and the range weight it gives the line the hero took.
///
/// The key is the situation — street, seat, aggression faced, stack bucket —
/// and the hero's cards are asked second, in the covering scenario's range
/// table. A covered spot reports the table's own weight for the line the hero
/// took, never a fabricated one; an uncovered spot reports nothing.
final class ImportedHandContentMatchTests: XCTestCase {
    /// Appendix A's four hero decisions, preflop first.
    @MainActor
    private func appendixASignatures() throws -> [HeroDecisionSignature] {
        let hand = try ObservedHand.parsed(HandImportFixtureText.appendixA)
        let signatures = hand.heroDecisionSignatures()
        XCTAssertFalse(signatures.isEmpty, "附录 A 应产出英雄决策签名")
        XCTAssertEqual(signatures.first?.signature.street, .preflop)
        return signatures
    }

    // GIVEN 装入覆盖附录 A 翻前局面的内容
    // WHEN 判定翻前决策
    // THEN covered，且权重等于对该场景查表所得（非编造）
    @MainActor
    func testPreflopNodeIsCoveredWithTheRangeTableWeight() throws {
        let signatures = try appendixASignatures()
        let preflop = try XCTUnwrap(signatures.first)

        // A non-round weight, so a constant-covered stub that always answers
        // 10,000 cannot pass.
        let scenario = try HandLabContentFixture.scenario(
            id: "covers-btn-open",
            covering: preflop.signature.coverageKey,
            handClass: preflop.signature.handClass,
            actionKey: RangeBaseline.raiseKey,
            weightBasisPoints: 6_234
        )
        let matcher = ImportedHandContentMatcher(scenarios: [scenario])

        // The weight is the covering scenario's own table lookup, not a number
        // the matcher invented.
        let expected = scenario.rangeWeightBasisPoints(
            forHandClass: preflop.signature.handClass,
            action: .raise(to: BBAmount(centiBB: 300))
        )
        XCTAssertEqual(expected, 6_234)
        XCTAssertEqual(matcher.classify(preflop), .covered(scenarioID: "covers-btn-open", weightBasisPoints: 6_234))
    }

    // GIVEN 只装入覆盖翻前的内容
    // WHEN 判定翻后决策
    // THEN 翻牌/转牌/河牌节点都是 uncovered，不编造权重
    @MainActor
    func testPostflopNodesAreUncovered() throws {
        let signatures = try appendixASignatures()
        let preflop = try XCTUnwrap(signatures.first)
        let scenario = try HandLabContentFixture.scenario(
            id: "covers-btn-open",
            covering: preflop.signature.coverageKey,
            handClass: preflop.signature.handClass,
            actionKey: RangeBaseline.raiseKey,
            weightBasisPoints: 6_234
        )
        let matcher = ImportedHandContentMatcher(scenarios: [scenario])

        let postflop = signatures.filter { $0.signature.street != .preflop }
        XCTAssertFalse(postflop.isEmpty, "附录 A 应有翻后决策，否则测不到未覆盖")
        for node in postflop {
            XCTAssertEqual(matcher.classify(node), .uncovered, "翻后节点 \(node.signature.street) 不应被编造覆盖")
        }
    }

    // GIVEN 内容为空
    // WHEN 判定翻前决策
    // THEN uncovered（与命中成对，排除恒 covered/恒 uncovered）
    @MainActor
    func testEmptyContentLeavesThePreflopNodeUncovered() throws {
        let signatures = try appendixASignatures()
        let preflop = try XCTUnwrap(signatures.first)
        let matcher = ImportedHandContentMatcher(scenarios: [])

        XCTAssertEqual(matcher.classify(preflop), .uncovered)
    }
}
