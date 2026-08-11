import Foundation
import PokerCore
import StrategyContent
import XCTest
@testable import PokerCoach

/// Which session spots installed content is allowed to be shown against.
///
/// A false match costs one irrelevant comparison on a review screen and nothing
/// in the ability profile — session hands produce no events either way. That is
/// not a reason to be loose about it: a comparison drawn from a different spot
/// teaches the wrong thing more effectively than no comparison at all.
final class SessionContentMatcherTests: XCTestCase {
    private let coveredSpot = SpotSignature(
        street: .preflop,
        heroSeatOffsetFromButton: 3,
        handClass: HandClass(notation: "AKo")!,
        facing: .unopened,
        stackBucket: .deep
    )

    @MainActor
    func testMatchesAScenarioWithTheSameSignature() throws {
        let matcher = SessionContentMatcher(scenarios: [try scenario(for: coveredSpot)])

        XCTAssertEqual(matcher.scenarioID(matching: coveredSpot), "covered")
    }

    // GIVEN 街道、位置、面对的行动类别与手牌类别都相同，只有有效筹码落在相邻分桶
    // WHEN 判定等同
    // THEN 判定为不等同
    @MainActor
    func testAnAdjacentStackBucketIsNotTheSameSpot() throws {
        let matcher = SessionContentMatcher(scenarios: [try scenario(for: coveredSpot)])
        let oneBucketShallower = SpotSignature(
            street: coveredSpot.street,
            heroSeatOffsetFromButton: coveredSpot.heroSeatOffsetFromButton,
            handClass: coveredSpot.handClass,
            facing: coveredSpot.facing,
            stackBucket: .medium
        )
        let oneBucketDeeper = SpotSignature(
            street: coveredSpot.street,
            heroSeatOffsetFromButton: coveredSpot.heroSeatOffsetFromButton,
            handClass: coveredSpot.handClass,
            facing: coveredSpot.facing,
            stackBucket: .veryDeep
        )

        // The fixture differs in exactly one component, so a nil answer cannot
        // be explained by the spot being unrelated.
        XCTAssertEqual(oneBucketShallower.handClass, coveredSpot.handClass)
        XCTAssertEqual(oneBucketDeeper.facing, coveredSpot.facing)

        XCTAssertNil(matcher.scenarioID(matching: oneBucketShallower))
        XCTAssertNil(matcher.scenarioID(matching: oneBucketDeeper))
    }

    // GIVEN 一手打到翻牌之后，其翻前部分与某已安装场景等同
    // WHEN 判定等同
    // THEN 只有翻前决策点被标记为可对照
    @MainActor
    func testAPostflopSpotNeverMatchesPreflopContent() throws {
        let matcher = SessionContentMatcher(scenarios: [try scenario(for: coveredSpot)])
        let sameHandOnTheFlop = SpotSignature(
            street: .flop,
            heroSeatOffsetFromButton: coveredSpot.heroSeatOffsetFromButton,
            handClass: coveredSpot.handClass,
            facing: coveredSpot.facing,
            stackBucket: coveredSpot.stackBucket
        )

        XCTAssertNotNil(matcher.scenarioID(matching: coveredSpot))
        XCTAssertNil(matcher.scenarioID(matching: sameHandOnTheFlop))
    }

    @MainActor
    func testNoContentMeansNoMatches() throws {
        XCTAssertNil(SessionContentMatcher(scenarios: []).scenarioID(matching: coveredSpot))
    }

    /// A scenario whose signature is the given spot. Only the five fields the
    /// signature reads are set from it; the rest comes from a fixture, because
    /// none of it participates in the comparison.
    @MainActor
    private func scenario(for signature: SpotSignature) throws -> DecisionScenario {
        let template = try DecisionSessionFixture.makePack().scenarios[0]
        let built = DecisionScenario(
            id: "covered",
            title: "对照场景",
            abilityDimension: template.abilityDimension,
            curriculumNodeID: template.curriculumNodeID,
            heroSeatOffsetFromButton: signature.heroSeatOffsetFromButton,
            facing: signature.facing,
            heroCards: [
                Card(rank: signature.handClass.highRank, suit: .spades),
                Card(rank: signature.handClass.lowRank, suit: .hearts),
            ],
            board: [],
            decision: BettingDecisionContext(
                pot: BBAmount(centiBB: 150),
                effectiveStack: BBAmount(centiBB: 10_000),
                amountToCall: BBAmount(centiBB: 100),
                minimumRaiseTo: BBAmount(centiBB: 200),
                configuredBetSizes: []
            ),
            options: template.options,
            rangeCells: template.rangeCells,
            assumptions: template.assumptions,
            explanation: template.explanation
        )
        XCTAssertEqual(built.spotSignature, signature, "夹具场景的签名不是要覆盖的那个局面")
        return built
    }
}
