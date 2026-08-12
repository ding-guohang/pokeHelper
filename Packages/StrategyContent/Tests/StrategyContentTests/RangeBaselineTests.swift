import Foundation
import PokerCore
import Testing
@testable import StrategyContent

@Suite("范围表基准")
struct RangeBaselineTests {
    /// The numbers are asserted against the shipped content, not against a
    /// fixture, because the baseline's whole claim is that it describes the
    /// content a user is actually being compared to. They were computed
    /// independently — non-fold combinations over 1,326 — before the code
    /// existed, and they are what the M2A design records.
    @Test("已发布内容的六个基准与设计文档一致")
    func matchesTheBaselinesRecordedInTheDesign() throws {
        let pack = try Self.corePack()
        let baselines = pack.entryBaselines

        let expected: [(offset: Int, facing: FacingAction, basisPoints: Int)] = [
            (3, .unopened, 1_560), // UTG 15.60%
            (4, .unopened, 1_982), // HJ  19.82%
            (5, .unopened, 2_486), // CO  24.86%
            (0, .unopened, 4_122), // BTN 41.22%（2026-08-11 按抽水收紧）
            (1, .unopened, 4_275), // SB  42.75%
            (5, .reraise, 905), //    CO 面对 3bet 9.05%
        ]

        for entry in expected {
            let key = PositionFacing(
                heroSeatOffsetFromButton: entry.offset,
                facing: entry.facing
            )
            #expect(
                baselines[key] == entry.basisPoints,
                "offset \(entry.offset) \(entry.facing) 基准是 \(baselines[key].map(String.init) ?? "缺失")，应为 \(entry.basisPoints)"
            )
        }
        #expect(baselines.count == expected.count)
    }

    /// The cutoff is the reason the key is a pair. Collapsing its two scenarios
    /// onto one key yields a number describing neither, and a user told their
    /// cutoff frequency was off against it would be compared to nothing.
    @Test("同一位置的两种面对情形各有各的基准，不被合并")
    func keepsTheTwoCutoffScenariosApart() throws {
        let baselines = try Self.corePack().entryBaselines
        let unopened = baselines[PositionFacing(heroSeatOffsetFromButton: 5, facing: .unopened)]
        let reraise = baselines[PositionFacing(heroSeatOffsetFromButton: 5, facing: .reraise)]

        #expect(unopened == 2_486)
        #expect(reraise == 905)
        #expect(unopened != reraise, "CO 的两个场景被合并成了一个基准")
    }

    /// Absent, not zero. A 0% baseline for the big blind would read as "never
    /// continue from the big blind", which is the opposite of true.
    @Test("内容未覆盖的位置没有基准，而不是基准为零")
    func omitsPositionsTheContentDoesNotCover() throws {
        let baselines = try Self.corePack().entryBaselines
        let bigBlind = PositionFacing(heroSeatOffsetFromButton: 2, facing: .unopened)

        #expect(baselines[bigBlind] == nil)
        #expect(!baselines.keys.contains(bigBlind))
    }

    /// Weighted by combinations, so a suited cell cannot count as much as an
    /// offsuit one. Asserted with hand-checkable arithmetic rather than against
    /// the shipped pack, so a reader can verify the weighting by eye.
    @Test("按组合数加权，同花与非同花权重不同")
    func weightsCellsByTheirCombinationCount() {
        // AKs is 4 combinations, AKo is 12. Entering with all of both is
        // 16 × 10,000 / 1,326 = 120.66 basis points, which rounds to 121.
        // Spelled out rather than recomputed with the same expression the
        // implementation uses: an expected value that repeats the code under
        // test agrees with it by construction, including when both are wrong.
        let both = RangeBaseline.entryBasisPoints(of: [
            RangeCell(handClass: "AKs", actionWeightsBasisPoints: ["raise": 10_000]),
            RangeCell(handClass: "AKo", actionWeightsBasisPoints: ["raise": 10_000]),
        ])
        #expect(both == 121)

        // The suited cell alone must be worth a quarter of the offsuit one.
        let suitedOnly = RangeBaseline.entryBasisPoints(of: [
            RangeCell(handClass: "AKs", actionWeightsBasisPoints: ["raise": 10_000]),
        ])
        let offsuitOnly = RangeBaseline.entryBasisPoints(of: [
            RangeCell(handClass: "AKo", actionWeightsBasisPoints: ["raise": 10_000]),
        ])
        #expect(offsuitOnly == suitedOnly * 3)
    }

    @Test("混合频率按其非弃牌权重折算")
    func countsMixedCellsAtTheirNonFoldWeight() {
        let half = RangeBaseline.entryBasisPoints(of: [
            RangeCell(handClass: "AKo", actionWeightsBasisPoints: ["raise": 5_000, "fold": 5_000]),
        ])
        let full = RangeBaseline.entryBasisPoints(of: [
            RangeCell(handClass: "AKo", actionWeightsBasisPoints: ["raise": 10_000]),
        ])
        #expect(half * 2 == full)
    }

    /// Every non-fold action counts, not just raising. A table where the range
    /// calls rather than raises still enters the pot.
    @Test("跟注与加注都算入池，只有弃牌不算")
    func countsEveryNonFoldAction() {
        let raising = RangeBaseline.entryBasisPoints(of: [
            RangeCell(handClass: "AKo", actionWeightsBasisPoints: ["raise": 10_000]),
        ])
        let calling = RangeBaseline.entryBasisPoints(of: [
            RangeCell(handClass: "AKo", actionWeightsBasisPoints: ["call": 10_000]),
        ])
        let folding = RangeBaseline.entryBasisPoints(of: [
            RangeCell(handClass: "AKo", actionWeightsBasisPoints: ["fold": 10_000]),
        ])

        #expect(raising == calling)
        #expect(folding == 0)
    }

    /// The denominator is the whole deck, not the hands the table lists. A
    /// table that omits the trash it always folds must not thereby report a
    /// higher entry rate than one that lists it as a 100% fold.
    @Test("分母是全部 1326 个组合，不是表里列出的手牌")
    func dividesByTheWholeDeckRatherThanTheListedHands() {
        let listed = RangeBaseline.entryBasisPoints(of: [
            RangeCell(handClass: "AA", actionWeightsBasisPoints: ["raise": 10_000]),
        ])
        let listedWithExplicitFolds = RangeBaseline.entryBasisPoints(of: [
            RangeCell(handClass: "AA", actionWeightsBasisPoints: ["raise": 10_000]),
            RangeCell(handClass: "72o", actionWeightsBasisPoints: ["fold": 10_000]),
        ])

        #expect(listed == listedWithExplicitFolds)
        // AA is 6 combinations: 6 × 10,000 / 1,326 = 45.25, rounding to 45.
        #expect(listed == 45)
    }

    @Test("场景可产出与 Session 一侧同型的签名")
    func producesASignatureComparableWithASessionHand() throws {
        let pack = try Self.corePack()
        let scenario = try #require(pack.scenarios.first { $0.id == "vs3bet-co-vs-btn" })
        let signature = try #require(scenario.spotSignature)

        #expect(signature.street == .preflop)
        #expect(signature.heroSeatOffsetFromButton == 5)
        #expect(signature.facing == .reraise)
        #expect(signature.handClass == HandClass(notation: "AQs"))
        #expect(signature.stackBucket == .deep)
    }

    @Test("每个已发布场景都能产出签名")
    func everyShippedScenarioHasASignature() throws {
        let pack = try Self.corePack()
        #expect(!pack.scenarios.isEmpty)
        for scenario in pack.scenarios {
            #expect(scenario.spotSignature != nil, "\(scenario.id) 无法产出签名")
        }
    }

    /// The lookup the deviation criterion is built on: once a scenario covers a
    /// spot, what does its range table say about the hand the hero was actually
    /// dealt? Asserted against the shipped pack, and against three cells of
    /// visibly different shapes, because a lookup that always returned 10,000
    /// or always returned the first weight in the dictionary would satisfy any
    /// single one of them.
    @Test("范围表按手牌类别给出英雄所选行动的权重")
    func readsTheWeightOfTheActionTheHeroTook() throws {
        let utg = try #require(try Self.corePack().scenarios.first { $0.id == "rfi-utg" })
        let openTo = BBAmount(centiBB: 250)

        // AA: raise 10000. A hand the range always opens.
        let aces = try #require(HandClass(notation: "AA"))
        #expect(utg.rangeWeightBasisPoints(forHandClass: aces, action: .raise(to: openTo)) == 10_000)
        #expect(utg.rangeWeightBasisPoints(forHandClass: aces, action: .fold) == 0)

        // KJo: fold 7000 / raise 3000. A mixed cell, so the two answers must
        // differ from each other and from the pair above.
        let kingJackOffsuit = try #require(HandClass(notation: "KJo"))
        #expect(utg.rangeWeightBasisPoints(forHandClass: kingJackOffsuit, action: .raise(to: openTo)) == 3_000)
        #expect(utg.rangeWeightBasisPoints(forHandClass: kingJackOffsuit, action: .fold) == 7_000)

        // A class the table does not list. Not missing data: a range chart
        // lists what it plays, so an omitted class is one it folds every time.
        let trash = try #require(HandClass(notation: "72o"))
        #expect(utg.rangeCells.allSatisfy { $0.handClass != "72o" }, "夹具前提不成立：72o 在表里")
        #expect(utg.rangeWeightBasisPoints(forHandClass: trash, action: .fold) == 10_000)
        #expect(utg.rangeWeightBasisPoints(forHandClass: trash, action: .raise(to: openTo)) == 0)

        // An action name the table has, on a class where its weight is zero:
        // the cell exists and simply does not call.
        #expect(utg.rangeWeightBasisPoints(forHandClass: aces, action: .call(to: openTo)) == 0)

        // A check has no name in a range table's vocabulary and no defensible
        // translation into one, so there is no weight rather than a zero.
        #expect(utg.rangeWeightBasisPoints(forHandClass: aces, action: .check) == nil)
    }

    /// A bet, a raise and an all-in are one decision as far as a range chart is
    /// concerned — put in more than is owed. The sizing lives in `options`.
    @Test("下注、加注与全下在范围表里是同一项")
    func treatsEveryAggressiveActionAsARaise() throws {
        let utg = try #require(try Self.corePack().scenarios.first { $0.id == "rfi-utg" })
        let mixed = try #require(HandClass(notation: "KJo"))
        let amount = BBAmount(centiBB: 250)

        for action in [DecisionAction.bet(to: amount), .raise(to: amount), .allIn(to: amount)] {
            #expect(
                utg.rangeWeightBasisPoints(forHandClass: mixed, action: action) == 3_000,
                "\(action) 查到的权重不是 raise 那一项"
            )
        }
        // And the calling row is a different number, so the four are not simply
        // all reading the same entry.
        let vs3bet = try #require(try Self.corePack().scenarios.first { $0.id == "vs3bet-co-vs-btn" })
        let sixes = try #require(HandClass(notation: "66"))
        #expect(vs3bet.rangeWeightBasisPoints(forHandClass: sixes, action: .call(to: amount)) == 6_000)
        #expect(vs3bet.rangeWeightBasisPoints(forHandClass: sixes, action: .raise(to: amount)) == 0)
        #expect(vs3bet.rangeWeightBasisPoints(forHandClass: sixes, action: .fold) == 4_000)
    }

    /// The six situations the shipped pack covers, enumerated.
    ///
    /// The count is the load-bearing part: six scenarios, six *distinct*
    /// coverage keys, even though two of them are at the cutoff. A key that
    /// left out the aggression faced would collapse those two and this would
    /// read five. A key that left out the street or the stack bucket would not
    /// be caught here — those are asserted component by component in
    /// `SpotSignatureTests`, on a signature built to vary one at a time, which
    /// the shipped pack cannot do because every scenario is preflop at 100BB.
    @Test("已发布内容覆盖六个互不相同的局面")
    func enumeratesTheSituationsTheShippedPackCovers() throws {
        let pack = try Self.corePack()
        let keys = pack.scenarios.compactMap(\.spotCoverageKey)
        #expect(keys.count == pack.scenarios.count)
        #expect(Set(keys).count == 6, "六个场景只产出了 \(Set(keys).count) 个不同的覆盖键")

        let byPosition = Set(keys.map { PositionFacing(
            heroSeatOffsetFromButton: $0.heroSeatOffsetFromButton,
            facing: $0.facing
        ) })
        #expect(byPosition == Set([
            PositionFacing(heroSeatOffsetFromButton: 0, facing: .unopened),
            PositionFacing(heroSeatOffsetFromButton: 1, facing: .unopened),
            PositionFacing(heroSeatOffsetFromButton: 3, facing: .unopened),
            PositionFacing(heroSeatOffsetFromButton: 4, facing: .unopened),
            PositionFacing(heroSeatOffsetFromButton: 5, facing: .unopened),
            PositionFacing(heroSeatOffsetFromButton: 5, facing: .reraise),
        ]))
        #expect(Set(keys.map(\.street)) == [.preflop])
        #expect(Set(keys.map(\.stackBucket)) == [.deep])

        // The big blind is the position with no scenario, which is why coverage
        // of the hero's preflop decisions tops out well short of everything.
        #expect(!keys.contains { $0.heroSeatOffsetFromButton == 2 })
    }

    private static func corePack() throws -> StrategyPack {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // StrategyContentTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // StrategyContent
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repository root
            .appending(path: "PokerCoach/Resources/CoreStrategyPack.json")
        return try StrategyPackLoader().load(
            data: try Data(contentsOf: url),
            expectedSHA256: nil
        )
    }
}
