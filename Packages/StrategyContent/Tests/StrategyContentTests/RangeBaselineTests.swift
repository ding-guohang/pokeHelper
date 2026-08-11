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
            (0, .unopened, 4_633), // BTN 46.33%
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
