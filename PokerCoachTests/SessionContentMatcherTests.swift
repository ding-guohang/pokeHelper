import Foundation
import PokerCore
import SessionSimulation
import StrategyContent
import XCTest
@testable import PokerCoach

/// Which session spots installed content is allowed to be shown against.
///
/// A false match costs one irrelevant comparison on a review screen and nothing
/// in the ability profile — session hands produce no events either way. That is
/// not a reason to be loose about it: a comparison drawn from a different spot
/// teaches the wrong thing more effectively than no comparison at all.
///
/// The key is the *situation* — street, seat, aggression faced, stack bucket —
/// and not the hero's cards. A scenario's `heroCards` are the example its
/// training screen shows; its range table covers the whole range. Keying on the
/// example made coverage all but unreachable, and the hero's real cards are not
/// discarded by dropping them from the key: they are looked up second, in the
/// covering scenario's range table.
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
        let matcher = SessionContentMatcher(scenarios: [try scenario(covering: coveredSpot)])

        XCTAssertEqual(matcher.scenarioID(matching: coveredSpot), "covered")
    }

    /// The defect this key exists to fix. A scenario teaches a whole range and
    /// shows one hand as its example; a session spot with the same street,
    /// seat, aggression and stack depth is the same situation whatever the hero
    /// happens to be holding.
    @MainActor
    func testAnyHandInTheSameSituationIsCovered() throws {
        let matcher = SessionContentMatcher(
            scenarios: [try scenario(covering: coveredSpot, exampleHand: [
                Card(rank: .ace, suit: .diamonds),
                Card(rank: .king, suit: .clubs),
            ])]
        )

        // The example hand really is not the one being looked up, so a pass
        // cannot be explained by the two coinciding.
        let dealt = try XCTUnwrap(HandClass(notation: "72o"))
        XCTAssertNotEqual(dealt, coveredSpot.handClass)

        let differentHand = SpotSignature(
            street: coveredSpot.street,
            heroSeatOffsetFromButton: coveredSpot.heroSeatOffsetFromButton,
            handClass: dealt,
            facing: coveredSpot.facing,
            stackBucket: coveredSpot.stackBucket
        )
        XCTAssertNotEqual(differentHand, coveredSpot, "两个签名本就相同，测不出手牌是否参与覆盖")

        XCTAssertEqual(matcher.scenarioID(matching: differentHand), "covered")
        XCTAssertEqual(matcher.scenarioID(matching: coveredSpot), "covered")
    }

    // GIVEN 街道、位置、面对的行动类别与手牌类别都相同，只有有效筹码落在相邻分桶
    // WHEN 判定等同
    // THEN 判定为不等同
    @MainActor
    func testAnAdjacentStackBucketIsNotTheSameSpot() throws {
        let matcher = SessionContentMatcher(scenarios: [try scenario(covering: coveredSpot)])
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

        // The fixture differs in exactly one component of the coverage key, so
        // a nil answer cannot be explained by the spot being unrelated.
        XCTAssertEqual(oneBucketShallower.handClass, coveredSpot.handClass)
        XCTAssertEqual(oneBucketDeeper.facing, coveredSpot.facing)
        XCTAssertEqual(
            oneBucketShallower.heroSeatOffsetFromButton,
            coveredSpot.heroSeatOffsetFromButton
        )

        XCTAssertNil(matcher.scenarioID(matching: oneBucketShallower))
        XCTAssertNil(matcher.scenarioID(matching: oneBucketDeeper))
    }

    /// The other two components, asserted for the same reason: dropping the
    /// hand class from the key must not have dropped anything with it.
    @MainActor
    func testADifferentSeatOrFacingIsNotTheSameSpot() throws {
        let matcher = SessionContentMatcher(scenarios: [try scenario(covering: coveredSpot)])
        let elsewhere = SpotSignature(
            street: coveredSpot.street,
            heroSeatOffsetFromButton: coveredSpot.heroSeatOffsetFromButton + 1,
            handClass: coveredSpot.handClass,
            facing: coveredSpot.facing,
            stackBucket: coveredSpot.stackBucket
        )
        let facingMore = SpotSignature(
            street: coveredSpot.street,
            heroSeatOffsetFromButton: coveredSpot.heroSeatOffsetFromButton,
            handClass: coveredSpot.handClass,
            facing: .reraise,
            stackBucket: coveredSpot.stackBucket
        )

        XCTAssertNotNil(matcher.scenarioID(matching: coveredSpot))
        XCTAssertNil(matcher.scenarioID(matching: elsewhere))
        XCTAssertNil(matcher.scenarioID(matching: facingMore))
    }

    // GIVEN 一手打到翻牌之后，其翻前部分与某已安装场景等同
    // WHEN 判定等同
    // THEN 只有翻前决策点被标记为可对照
    @MainActor
    func testAPostflopSpotNeverMatchesPreflopContent() throws {
        let matcher = SessionContentMatcher(scenarios: [try scenario(covering: coveredSpot)])
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

    /// Coverage is the first question; the hero's cards are the second. Once a
    /// scenario covers the situation, the class the hero actually held is read
    /// out of that scenario's range table, and the weight of the line they took
    /// is what the key-hand scorer calls a deviation.
    @MainActor
    func testTheHeroActionWeightComesFromTheCoveringScenariosRangeTable() throws {
        let matcher = SessionContentMatcher(
            scenarios: [try scenario(
                covering: coveredSpot,
                rangeCells: [
                    RangeCell(handClass: "AKo", actionWeightsBasisPoints: ["raise": 10_000]),
                    RangeCell(
                        handClass: "T9s",
                        actionWeightsBasisPoints: ["raise": 3_000, "fold": 7_000]
                    ),
                ]
            )]
        )
        let raiseTo = BBAmount(centiBB: 250)

        XCTAssertEqual(
            matcher.heroActionWeightBasisPoints(forSpot: coveredSpot, action: .raise(to: raiseTo)),
            10_000
        )
        XCTAssertEqual(
            matcher.heroActionWeightBasisPoints(forSpot: coveredSpot, action: .fold),
            0
        )

        let mixed = spot(holding: "T9s")
        XCTAssertEqual(
            matcher.heroActionWeightBasisPoints(forSpot: mixed, action: .raise(to: raiseTo)),
            3_000
        )
        XCTAssertEqual(matcher.heroActionWeightBasisPoints(forSpot: mixed, action: .fold), 7_000)

        // A class the table omits is one the range folds every time — a
        // comparable answer, not a gap.
        let unlisted = spot(holding: "72o")
        XCTAssertEqual(matcher.heroActionWeightBasisPoints(forSpot: unlisted, action: .fold), 10_000)
        XCTAssertEqual(
            matcher.heroActionWeightBasisPoints(forSpot: unlisted, action: .raise(to: raiseTo)),
            0
        )

        // Nothing covers a flop spot, so there is no weight rather than a zero.
        let onTheFlop = SpotSignature(
            street: .flop,
            heroSeatOffsetFromButton: coveredSpot.heroSeatOffsetFromButton,
            handClass: coveredSpot.handClass,
            facing: coveredSpot.facing,
            stackBucket: coveredSpot.stackBucket
        )
        XCTAssertNil(matcher.heroActionWeightBasisPoints(forSpot: onTheFlop, action: .fold))
    }

    /// A hand the hero acted on twice in covered spots reports the biggest
    /// departure it contains, not the first one and not the average. Review is
    /// meant to open on the thing worth looking at.
    ///
    /// Real hands against the shipped pack, because the case only exists at all
    /// thanks to a fact about that pack: it covers the cutoff twice, opening
    /// and answering a 3-bet. The seventh hand of seed 49 opens A4s from the
    /// cutoff — which `rfi-co` raises 100% of the time — and then calls the
    /// 3-bet, which `vs3bet-co-vs-btn` never does with A4s. The departure is
    /// the second decision, so a "first covered spot wins" rule would report
    /// 10,000 here.
    @MainActor
    func testAHandWithTwoCoveredSpotsReportsItsLargestDeparture() throws {
        let installed = try BundledContentLoader(bundle: .main).loadPreferredPack()
        let matcher = SessionContentMatcher(scenarios: installed.pack.scenarios)
        let hands = Self.session(seed: 49, handCount: 30)
        let hand = try XCTUnwrap(hands.first { $0.handIndex == 7 })

        let matches = matcher.matches(in: hand)
        XCTAssertEqual(matches.count, 2, "夹具这一手命中的不是两个局面：\(matches.map(\.scenarioID))")
        XCTAssertEqual(matches.map(\.scenarioID), ["rfi-co", "vs3bet-co-vs-btn"])
        XCTAssertEqual(
            matches.map(\.heroActionWeightBasisPoints),
            [10_000, 0],
            "夹具这一手的两个权重不是「先照做、后偏离」，测不出取的是哪一个"
        )

        XCTAssertEqual(matcher.heroActionWeightsBasisPoints(in: [hand])[7], 0)
    }

    /// Uncovered hands are absent from the dictionary rather than present with
    /// a zero. The two are opposite claims — "nothing to say" against "the
    /// range never does that" — and the scorer reads only the second as a
    /// deviation.
    @MainActor
    func testUncoveredHandsAreAbsentRatherThanZero() throws {
        let installed = try BundledContentLoader(bundle: .main).loadPreferredPack()
        let matcher = SessionContentMatcher(scenarios: installed.pack.scenarios)
        let hands = Self.session(seed: 49, handCount: 30)
        let weights = matcher.heroActionWeightsBasisPoints(in: hands)

        let uncovered = hands.filter { matcher.matches(in: $0).isEmpty }
        let covered = hands.filter { !matcher.matches(in: $0).isEmpty }
        // Both kinds occur in this session, otherwise one half of the claim is
        // being made about nothing.
        XCTAssertFalse(uncovered.isEmpty, "这局每手都被覆盖，测不出「未覆盖」")
        XCTAssertFalse(covered.isEmpty, "这局没有一手被覆盖，测不出「覆盖但权重为 0」")

        for hand in uncovered {
            XCTAssertNil(weights[hand.handIndex], "未覆盖的第 \(hand.handIndex) 手出现在权重表里")
        }
        XCTAssertEqual(weights.count, covered.count)

        // And at least one covered hand really does sit at zero, which is the
        // value that would be indistinguishable from absence if the two were
        // merged.
        XCTAssertTrue(
            weights.values.contains(0),
            "这局没有一手的权重是 0，「0 不等于缺席」没有被检验到"
        )
    }

    /// The app path's policy: the hero plays the baseline, the five opponents
    /// play the profiles the seed seated them with.
    private static func session(seed: UInt64, handCount: Int) -> [SessionHandRecord] {
        let record = SessionRecord(id: UUID(), seed: seed, handCount: handCount)
        return SessionRunner(seed: seed, policy: record.policy(heroPolicy: BaselineActionPolicy()))
            .run(handCount: handCount)
            .hands
            .map(SessionHandRecord.init)
    }

    private func spot(holding notation: String) -> SpotSignature {
        SpotSignature(
            street: coveredSpot.street,
            heroSeatOffsetFromButton: coveredSpot.heroSeatOffsetFromButton,
            handClass: HandClass(notation: notation)!,
            facing: coveredSpot.facing,
            stackBucket: coveredSpot.stackBucket
        )
    }

    /// A scenario covering the given situation. Only the fields the coverage
    /// key and the range lookup read are set from the caller; the rest comes
    /// from a fixture, because none of it participates.
    @MainActor
    private func scenario(
        covering signature: SpotSignature,
        exampleHand: [Card]? = nil,
        rangeCells: [RangeCell] = []
    ) throws -> DecisionScenario {
        let template = try DecisionSessionFixture.makePack().scenarios[0]
        let built = DecisionScenario(
            id: "covered",
            title: "对照场景",
            abilityDimension: template.abilityDimension,
            curriculumNodeID: template.curriculumNodeID,
            heroSeatOffsetFromButton: signature.heroSeatOffsetFromButton,
            facing: signature.facing,
            heroCards: exampleHand ?? [
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
            rangeCells: rangeCells,
            assumptions: template.assumptions,
            explanation: template.explanation
        )
        XCTAssertEqual(
            built.spotCoverageKey,
            signature.coverageKey,
            "夹具场景的覆盖键不是要覆盖的那个局面"
        )
        return built
    }
}
