import Foundation
import StrategyContent
import Testing
@testable import TrainingDomain

@Suite("能力弱项排序")
struct AbilityRankingTests {
    /// The comparator has to be a total order, because its input is
    /// `Dictionary.values`. Swift seeds hashing per process, so any pair the
    /// comparator leaves tied comes out in a different place on every launch.
    @Test("完全相同的两项按维度名定序，不受字典顺序影响")
    func breaksTiesOnDimensionName() {
        let profile = PlayerProfile(abilities: [
            "zeta": Self.snapshot(dimension: "zeta"),
            "alpha": Self.snapshot(dimension: "alpha"),
            "mike": Self.snapshot(dimension: "mike"),
            "bravo": Self.snapshot(dimension: "bravo"),
        ])

        #expect(
            profile.abilitiesWeakestFirst.map(\.dimension)
                == ["alpha", "bravo", "mike", "zeta"]
        )
    }

    @Test("分数低的排在前面")
    func ranksLowerScoreFirst() {
        let profile = PlayerProfile(abilities: [
            "strong": Self.snapshot(dimension: "strong", meanScore: 90),
            "weak": Self.snapshot(dimension: "weak", meanScore: 30),
            "middle": Self.snapshot(dimension: "middle", meanScore: 60),
        ])

        #expect(
            profile.abilitiesWeakestFirst.map(\.dimension)
                == ["weak", "middle", "strong"]
        )
    }

    // Each subsequent key must only decide when every earlier key is equal,
    // and must decide in the stated direction. Asserted one key at a time:
    // a comparator that consults them in the wrong order, or compares one of
    // them the wrong way round, still satisfies the score test above.
    @Test("同分时高信心错误多的排在前面")
    func ranksMoreHighConfidenceErrorsFirstAmongEqualScores() {
        let profile = PlayerProfile(abilities: [
            "few": Self.snapshot(dimension: "few", highConfidenceErrorCount: 1),
            "many": Self.snapshot(dimension: "many", highConfidenceErrorCount: 4),
        ])

        #expect(profile.abilitiesWeakestFirst.map(\.dimension) == ["many", "few"])
    }

    @Test("分数与高信心错误都相同时，EV 损失大的排在前面")
    func ranksHigherLossRateFirstWhenEarlierKeysTie() {
        let profile = PlayerProfile(abilities: [
            "small": Self.snapshot(dimension: "small", meanLossRateBasisPoints: 40),
            "large": Self.snapshot(dimension: "large", meanLossRateBasisPoints: 900),
        ])

        #expect(profile.abilitiesWeakestFirst.map(\.dimension) == ["large", "small"])
    }

    /// Score dominates the later keys. Without this, a comparator that led
    /// with the high-confidence-error count would pass every test above.
    @Test("分数优先于高信心错误")
    func scoreOutranksHighConfidenceErrors() {
        let profile = PlayerProfile(abilities: [
            "weakButClean": Self.snapshot(
                dimension: "weakButClean",
                meanScore: 30,
                highConfidenceErrorCount: 0
            ),
            "strongButSloppy": Self.snapshot(
                dimension: "strongButSloppy",
                meanScore: 90,
                highConfidenceErrorCount: 9
            ),
        ])

        #expect(
            profile.abilitiesWeakestFirst.map(\.dimension)
                == ["weakButClean", "strongButSloppy"]
        )
    }

    @Test("空画像返回空列表")
    func handlesAnEmptyProfile() {
        #expect(PlayerProfile(abilities: [:]).abilitiesWeakestFirst.isEmpty)
    }

    private static func snapshot(
        dimension: String,
        meanScore: Int = 50,
        meanLossRateBasisPoints: Int = 100,
        highConfidenceErrorCount: Int = 0
    ) -> AbilitySnapshot {
        AbilitySnapshot(
            dimension: dimension,
            sampleCount: 10,
            meanScore: meanScore,
            meanLossRateBasisPoints: meanLossRateBasisPoints,
            highConfidenceErrorCount: highConfidenceErrorCount,
            lastPracticedAt: nil
        )
    }
}

@Suite("到期复练节点集合")
struct DueNodeIDsTests {
    /// Today built this set inline and Review passed nothing, so the two
    /// screens could name different first items from the same profile and the
    /// same catalog. One definition now serves both.
    @Test("有内容时返回到期节点，与 dueRepetitions 一致")
    func matchesDueRepetitions() {
        let pack = CurriculumFixture.pack(
            scenarios: [("scenario-1", "turn-barrel")],
            nodes: [("turn-barrel", [])]
        )
        // The ladder only starts at the first failure -- a node you have never
        // got wrong has nothing to repeat. A blunder on day 0 puts the node on
        // the bottom rung, one day, so day 5 has it overdue.
        let events = [CurriculumFixture.event(quality: .blunder, daysAfterEpoch: 0)]
        let now = CurriculumFixture.epoch.addingTimeInterval(5 * 86_400)
        let scheduler = RepetitionScheduler()

        let expected = Set(
            scheduler.dueRepetitions(events: events, pack: pack, now: now)
                .map(\.nodeID)
        )

        #expect(!expected.isEmpty, "夹具没有产生到期项，本测试无法证明任何事")
        #expect(
            scheduler.dueNodeIDs(events: events, pack: pack, now: now) == expected
        )
    }

    /// Without a pack there is no curriculum to resolve nodes against, so the
    /// plan ranks without the repetition term rather than guessing at one.
    @Test("无内容时返回空集合而不是猜测")
    func returnsEmptyWithoutAPack() {
        #expect(
            RepetitionScheduler().dueNodeIDs(
                events: [CurriculumFixture.event(daysAfterEpoch: 0)],
                pack: nil,
                now: CurriculumFixture.epoch.addingTimeInterval(5 * 86_400)
            ).isEmpty
        )
    }
}
