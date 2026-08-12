import Foundation
import PokerCore
import SessionPersistence
import SessionSimulation
import StrategyContent
import XCTest
@testable import PokerCoach

/// The aggregate the professional workflow actually uses: not "did I play this
/// hand right" but "am I too loose from this seat".
///
/// Two things it must never do, and both are easy to do by accident: report a
/// verdict on a handful of hands, and compare a seat against a baseline drawn
/// from a different spot.
final class SessionFrequencyReportTests: XCTestCase {
    private static let button = PositionFacing(heroSeatOffsetFromButton: 0, facing: .unopened)
    private static let cutoff = PositionFacing(heroSeatOffsetFromButton: 5, facing: .unopened)
    private static let cutoffVersusRaise = PositionFacing(heroSeatOffsetFromButton: 5, facing: .singleRaise)
    private static let cutoffVersus3Bet = PositionFacing(heroSeatOffsetFromButton: 5, facing: .reraise)
    private static let bigBlind = PositionFacing(heroSeatOffsetFromButton: 2, facing: .unopened)

    // MARK: - Reporting counts against the baseline

    // GIVEN 用户在 BTN 位置累计有 8 次开池机会，阈值为 30
    // WHEN 打开频率报告
    // THEN 显示「BTN 8 次机会」与实际开池次数
    // AND 不显示与基准的差值
    // AND 显示「样本不足，暂不比较」
    // AND 该位置不出现在漏洞列表里
    @MainActor
    func testAThinSampleIsCountedButNotJudged() throws {
        let pack = try Self.shippedPack()
        let report = SessionFrequencyReport.make(
            counts: [Self.button: HeroPreflopCounts(opportunities: 8, entries: 5)],
            installedContent: pack
        )

        let row = try XCTUnwrap(report.rows.first { $0.key == Self.button })
        XCTAssertEqual(row.position?.label, "BTN")
        XCTAssertEqual(row.opportunities, 8)
        XCTAssertEqual(row.entries, 5)
        XCTAssertEqual(row.frequencyBasisPoints, 6_250)

        // The content does cover this spot, so a withheld verdict cannot be
        // explained by there being nothing to compare against.
        XCTAssertEqual(row.baselineBasisPoints, 4_122)
        XCTAssertFalse(row.hasEnoughOpportunities)
        XCTAssertNil(row.deltaBasisPoints)
        XCTAssertNil(row.leak)
        XCTAssertTrue(report.leaks.isEmpty)
    }

    // GIVEN 用户在 BTN 位置累计有 60 次开池机会，其中开池 42 次
    // AND 已安装内容的 BTN 开池基准为 41.22%
    // WHEN 打开频率报告
    // THEN 显示实际 70.00%、基准 41.22%、差值 +28.78 个百分点
    // AND 该位置出现在漏洞列表里，标注为偏松
    @MainActor
    func testASufficientSampleIsComparedAgainstTheBaseline() throws {
        let report = SessionFrequencyReport.make(
            counts: [Self.button: HeroPreflopCounts(opportunities: 60, entries: 42)],
            installedContent: try Self.shippedPack()
        )

        let row = try XCTUnwrap(report.rows.first { $0.key == Self.button })
        XCTAssertEqual(row.frequencyBasisPoints, 7_000)
        XCTAssertEqual(row.baselineBasisPoints, 4_122)
        XCTAssertEqual(row.deltaBasisPoints, 2_878)
        XCTAssertTrue(row.hasEnoughOpportunities)
        XCTAssertEqual(row.leak, .loose)
        XCTAssertEqual(report.leaks.map(\.key), [Self.button])
    }

    /// The threshold is a floor, so both sides of it have to be pinned. An
    /// implementation using `>` reads exactly like one using `>=` until 30
    /// opportunities land on the line.
    @MainActor
    func testTheThresholdIncludesTheThirtiethOpportunity() throws {
        let pack = try Self.shippedPack()

        let justUnder = SessionFrequencyReport.make(
            counts: [Self.button: HeroPreflopCounts(opportunities: 29, entries: 20)],
            installedContent: pack
        )
        let exactly = SessionFrequencyReport.make(
            counts: [Self.button: HeroPreflopCounts(opportunities: 30, entries: 21)],
            installedContent: pack
        )

        XCTAssertNil(justUnder.rows.first?.deltaBasisPoints, "29 次机会就给出了结论")
        XCTAssertNotNil(exactly.rows.first?.deltaBasisPoints, "30 次机会仍不给结论")
        XCTAssertEqual(exactly.rows.first?.frequencyBasisPoints, 7_000)
        XCTAssertEqual(exactly.rows.first?.deltaBasisPoints, 2_878)
    }

    /// A leak has a direction, and a near miss is not a leak. The tolerance is
    /// a decision this task had to make — the proposal fixes the sample
    /// threshold and says nothing about how big a gap counts.
    @MainActor
    func testALeakIsNamedByDirectionAndOnlyOutsideTheTolerance() throws {
        let pack = try Self.shippedPack()

        // 10/30 = 33.33% against a 41.22% baseline: 7.89 points tight.
        let tooTight = SessionFrequencyReport.make(
            counts: [Self.button: HeroPreflopCounts(opportunities: 30, entries: 10)],
            installedContent: pack
        )
        // 13/30 = 43.33%, two points over — inside the tolerance.
        let onTheNose = SessionFrequencyReport.make(
            counts: [Self.button: HeroPreflopCounts(opportunities: 30, entries: 13)],
            installedContent: pack
        )

        XCTAssertEqual(tooTight.rows.first?.deltaBasisPoints, -789)
        XCTAssertEqual(tooTight.rows.first?.leak, .tight)
        XCTAssertEqual(tooTight.leaks.count, 1)

        XCTAssertEqual(onTheNose.rows.first?.deltaBasisPoints, 211)
        XCTAssertNil(onTheNose.rows.first?.leak)
        XCTAssertTrue(onTheNose.leaks.isEmpty, "差 2.11 个百分点也被当成漏洞")
    }

    // GIVEN 两个已安装内容版本，其 BTN 范围表的组合权重不同
    // WHEN 分别打开频率报告
    // THEN 两次显示的基准值不同
    // AND 每次的基准值等于该版本 BTN 未面对下注范围表中的非弃牌组合数除以 1326
    @MainActor
    func testTheBaselineIsComputedFromTheInstalledRangeTable() throws {
        // AA alone is 6 combinations of 1,326: 45.25 basis points, rounding to
        // 45. Adding KK doubles the combinations: 90.99, rounding to 90.
        let onlyAces = try Self.pack(buttonRange: [
            RangeCell(handClass: "AA", actionWeightsBasisPoints: ["raise": 10_000]),
        ])
        let acesAndKings = try Self.pack(buttonRange: [
            RangeCell(handClass: "AA", actionWeightsBasisPoints: ["raise": 10_000]),
            RangeCell(handClass: "KK", actionWeightsBasisPoints: ["raise": 10_000]),
        ])
        let counts = [Self.button: HeroPreflopCounts(opportunities: 60, entries: 42)]

        let tight = SessionFrequencyReport.make(counts: counts, installedContent: onlyAces)
        let looser = SessionFrequencyReport.make(counts: counts, installedContent: acesAndKings)

        XCTAssertEqual(tight.rows.first?.baselineBasisPoints, 45)
        XCTAssertEqual(looser.rows.first?.baselineBasisPoints, 90)
        XCTAssertNotEqual(
            tight.rows.first?.baselineBasisPoints,
            looser.rows.first?.baselineBasisPoints,
            "换了范围表，基准却没有变——它是写死的"
        )
        // The realized side did not move, so the change came from the content.
        XCTAssertEqual(tight.rows.first?.frequencyBasisPoints, looser.rows.first?.frequencyBasisPoints)
    }

    // GIVEN 已安装内容在 CO 位置同时有未面对下注与面对 3bet 两个场景
    // WHEN 计算 CO 的基准
    // THEN 未面对下注的基准为 24.86%，面对 3bet 的基准为 9.05%
    // AND 两者不被合并成一个 CO 基准
    @MainActor
    func testTheTwoCutoffSpotsKeepSeparateBaselines() throws {
        let report = SessionFrequencyReport.make(
            counts: [
                Self.cutoff: HeroPreflopCounts(opportunities: 40, entries: 12),
                Self.cutoffVersus3Bet: HeroPreflopCounts(opportunities: 35, entries: 12),
            ],
            installedContent: try Self.shippedPack()
        )

        let unopened = try XCTUnwrap(report.rows.first { $0.key == Self.cutoff })
        let versus3Bet = try XCTUnwrap(report.rows.first { $0.key == Self.cutoffVersus3Bet })

        XCTAssertEqual(unopened.baselineBasisPoints, 2_486)
        XCTAssertEqual(versus3Bet.baselineBasisPoints, 905)
        XCTAssertNotEqual(unopened.baselineBasisPoints, versus3Bet.baselineBasisPoints)
        XCTAssertEqual(report.rows.count, 2, "同一位置的两种面对情形被合并成了一行")

        // Same realized frequency, opposite verdicts — which is the point of
        // keying on the pair. 30.00% is tight for an open-raise and wildly
        // loose against a 3-bet.
        XCTAssertEqual(unopened.frequencyBasisPoints, 3_000)
        XCTAssertEqual(versus3Bet.frequencyBasisPoints, 3_429)
        XCTAssertEqual(unopened.leak, .loose)
        XCTAssertEqual(versus3Bet.leak, .loose)
        XCTAssertEqual(unopened.deltaBasisPoints, 514)
        XCTAssertEqual(versus3Bet.deltaBasisPoints, 2_524)
    }

    // GIVEN 已安装内容没有 BB 位置的场景
    // WHEN 打开频率报告
    // THEN 显示 BB 的实际次数与频率
    // AND BB 行不显示基准值或差值
    // AND BB 不出现在漏洞列表里
    @MainActor
    func testAPositionTheContentDoesNotCoverShowsCountsWithoutABaseline() throws {
        let pack = try Self.shippedPack()
        XCTAssertNil(pack.entryBaselines[Self.bigBlind], "已发布内容有 BB 基准，这条断言就没有意义了")

        let report = SessionFrequencyReport.make(
            counts: [
                Self.bigBlind: HeroPreflopCounts(opportunities: 48, entries: 36),
                Self.button: HeroPreflopCounts(opportunities: 48, entries: 36),
            ],
            installedContent: pack
        )

        let row = try XCTUnwrap(report.rows.first { $0.key == Self.bigBlind })
        XCTAssertEqual(row.position?.label, "BB")
        XCTAssertEqual(row.opportunities, 48)
        XCTAssertEqual(row.entries, 36)
        XCTAssertEqual(row.frequencyBasisPoints, 7_500)
        XCTAssertNil(row.baselineBasisPoints)
        XCTAssertNil(row.deltaBasisPoints)
        XCTAssertNil(row.leak)
        XCTAssertFalse(report.leaks.contains { $0.key == Self.bigBlind })

        // The identical counts at a covered position do produce a verdict, so
        // the silence above is about the missing baseline and not about the
        // numbers.
        XCTAssertEqual(report.leaks.map(\.key), [Self.button])
    }

    // GIVEN 未安装任何内容
    // WHEN 打开频率报告
    // THEN 仍显示各位置的实际次数与频率
    // AND 不显示任何基准值或差值
    // AND 不出现漏洞列表
    @MainActor
    func testWithoutContentTheReportStillCountsAndInventsNoBaseline() throws {
        let counts = [
            Self.button: HeroPreflopCounts(opportunities: 60, entries: 42),
            Self.cutoff: HeroPreflopCounts(opportunities: 40, entries: 12),
        ]
        let report = SessionFrequencyReport.make(counts: counts, installedContent: nil)

        XCTAssertEqual(report.rows.count, 2)
        XCTAssertEqual(report.rows.map(\.opportunities), [60, 40])
        XCTAssertEqual(report.rows.map(\.frequencyBasisPoints), [7_000, 3_000])
        XCTAssertTrue(report.rows.allSatisfy { $0.baselineBasisPoints == nil })
        XCTAssertTrue(report.rows.allSatisfy { $0.deltaBasisPoints == nil })
        XCTAssertTrue(report.leaks.isEmpty)

        // The same counts with content do produce baselines, so "no baselines"
        // is a consequence of nothing being installed.
        let withContent = SessionFrequencyReport.make(
            counts: counts,
            installedContent: try Self.shippedPack()
        )
        XCTAssertTrue(withContent.rows.allSatisfy { $0.baselineBasisPoints != nil })
    }

    @MainActor
    func testRowsComeBackInAFixedOrder() throws {
        let counts: [PositionFacing: HeroPreflopCounts] = [
            PositionFacing(heroSeatOffsetFromButton: 5, facing: .reraise): .init(opportunities: 1, entries: 0),
            PositionFacing(heroSeatOffsetFromButton: 0, facing: .unopened): .init(opportunities: 1, entries: 0),
            PositionFacing(heroSeatOffsetFromButton: 5, facing: .unopened): .init(opportunities: 1, entries: 0),
            PositionFacing(heroSeatOffsetFromButton: 2, facing: .singleRaise): .init(opportunities: 1, entries: 0),
            PositionFacing(heroSeatOffsetFromButton: 2, facing: .unopened): .init(opportunities: 1, entries: 0),
        ]
        let report = SessionFrequencyReport.make(counts: counts, installedContent: nil)

        XCTAssertEqual(
            report.rows.map { "\($0.key.heroSeatOffsetFromButton)/\($0.key.facing.rawValue)" },
            ["0/unopened", "2/unopened", "2/singleRaise", "5/unopened", "5/reraise"]
        )
    }

    // MARK: - Counting the recorded hands

    // AND 英雄在 CO 面对 3bet 的手牌只计入面对 3bet 的机会数
    @MainActor
    func testEachDecisionIsCountedUnderTheAggressionItFaced() throws {
        let hands = Self.session(seed: 42, handCount: 30)
        let counts = SessionFrequencyReport.counts(in: hands)

        // Hand 20 is the one that carries both: the hero opens the cutoff and
        // is then 3-bet. Checked from the record rather than assumed, because
        // without it the two counts below could both come from other hands.
        let both = try XCTUnwrap(hands.first { $0.handIndex == 19 })
        XCTAssertEqual(
            both.heroSpotSignatures.filter { $0.street == .preflop }.map(\.facing),
            [.unopened, .reraise]
        )

        XCTAssertEqual(counts[Self.cutoff]?.opportunities, 2)
        XCTAssertEqual(counts[Self.cutoffVersus3Bet]?.opportunities, 2)
        XCTAssertEqual(
            counts[Self.cutoffVersusRaise]?.opportunities,
            3
        )
    }

    /// Answering a 3-bet and then a 5-bet in one hand is one chance to continue
    /// against a re-raise, not two. Seed 18's fifteenth hand is the case: the
    /// hero acts three times preflop from the hijack, twice of them facing a
    /// re-raise.
    @MainActor
    func testOneHandGivesAtMostOneOpportunityPerSpot() throws {
        let hand = try XCTUnwrap(
            Self.session(seed: 18, handCount: 30).first { $0.handIndex == 14 }
        )
        let hijackReraises = hand.heroSpotSignatures.filter {
            $0.street == .preflop && $0.heroSeatOffsetFromButton == 4 && $0.facing == .reraise
        }
        XCTAssertEqual(hijackReraises.count, 2, "这一手没有两次面对再加注，测的就不是去重了")

        let counts = SessionFrequencyReport.counts(in: [hand])
        let key = PositionFacing(heroSeatOffsetFromButton: 4, facing: .reraise)

        XCTAssertEqual(counts[key]?.opportunities, 1)
        XCTAssertLessThanOrEqual(counts[key]?.entries ?? 0, 1)
        XCTAssertEqual(
            counts[PositionFacing(heroSeatOffsetFromButton: 4, facing: .unopened)]?.opportunities,
            1
        )
    }

    // GIVEN 一手牌在英雄行动前已经结束
    // WHEN 计算频率报告
    // THEN 该手不计入英雄所在位置的机会数
    // AND 也不计入开池次数
    @MainActor
    func testAHandTheHeroNeverActedInIsNotAnOpportunity() throws {
        // Everyone folds around to the hero in the big blind. A real hand: the
        // blinds are posted, five players act, and the hero wins the small
        // blind without being asked anything.
        let walk = Self.hand(seed: 42, handIndex: 4, policy: FoldingTable())
        XCTAssertEqual(walk.actions.count, 5)
        XCTAssertTrue(walk.actions.allSatisfy { $0.action == .fold })
        XCTAssertEqual(walk.result.stackDeltasCentiBB[TableRules.heroSeat], 50)
        XCTAssertTrue(walk.heroSpotSignatures.isEmpty, "英雄在这一手里行动过，夹具不成立")

        let played = Self.session(seed: 42, handCount: 30)
        let withoutTheWalk = SessionFrequencyReport.counts(in: played)
        let withTheWalk = SessionFrequencyReport.counts(in: played + [walk])

        XCTAssertFalse(withoutTheWalk.isEmpty)
        XCTAssertEqual(withTheWalk, withoutTheWalk, "英雄没行动的一手改变了机会数")
        XCTAssertTrue(SessionFrequencyReport.counts(in: [walk]).isEmpty)
    }

    /// Entering is continuing, which is everything except folding — the same
    /// question the baseline asks of a range table, whose denominator counts
    /// every non-fold weight. Pinned hand by hand, because "entries ≤
    /// opportunities" holds for any rule at all, including one that counts the
    /// wrong action.
    @MainActor
    func testEnteringIsEveryActionButFolding() throws {
        let hands = Self.session(seed: 42, handCount: 30)

        // Cutoff facing a raise, folded.
        try Self.assertCounts(
            in: hands,
            handIndex: 1,
            expecting: [Self.cutoffVersusRaise: HeroPreflopCounts(opportunities: 1, entries: 0)]
        )
        // Small blind facing a raise, called for 93BB.
        try Self.assertCounts(
            in: hands,
            handIndex: 5,
            expecting: [
                PositionFacing(heroSeatOffsetFromButton: 1, facing: .singleRaise):
                    HeroPreflopCounts(opportunities: 1, entries: 1),
            ]
        )
        // Big blind, nobody raised, checked. A check is not a fold: the hero
        // took the flop, and a range table that checked here would count the
        // whole combination as continuing.
        try Self.assertCounts(
            in: hands,
            handIndex: 16,
            expecting: [Self.bigBlind: HeroPreflopCounts(opportunities: 1, entries: 1)]
        )
        // One hand, two spots, one of each: opened the button and folded to the
        // 3-bet.
        try Self.assertCounts(
            in: hands,
            handIndex: 12,
            expecting: [
                Self.button: HeroPreflopCounts(opportunities: 1, entries: 1),
                PositionFacing(heroSeatOffsetFromButton: 0, facing: .reraise):
                    HeroPreflopCounts(opportunities: 1, entries: 0),
            ]
        )

        // And over the whole session: two folds and one call at the cutoff
        // facing a raise.
        let counts = SessionFrequencyReport.counts(in: hands)
        XCTAssertEqual(
            counts[Self.cutoffVersusRaise],
            HeroPreflopCounts(opportunities: 3, entries: 1)
        )
    }

    /// The counts one hand contributes, with the hero's own actions printed
    /// into the failure so a wrong expectation is distinguishable from a wrong
    /// implementation.
    @MainActor
    private static func assertCounts(
        in hands: [SessionHandRecord],
        handIndex: Int,
        expecting expected: [PositionFacing: HeroPreflopCounts],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let hand = try XCTUnwrap(hands.first { $0.handIndex == handIndex }, file: file, line: line)
        let preflop = zip(hand.heroSpotSignatures, hand.heroActions)
            .filter { $0.0.street == .preflop }
        XCTAssertEqual(
            preflop.count,
            expected.count,
            "第 \(handIndex) 手英雄的翻前决策数与预期不符",
            file: file,
            line: line
        )

        XCTAssertEqual(
            SessionFrequencyReport.counts(in: [hand]),
            expected,
            "第 \(handIndex) 手英雄的翻前行动是 \(preflop.map(\.1))",
            file: file,
            line: line
        )
    }

    // GIVEN 三局各 15 手的已完成 Session
    // WHEN 打开频率报告
    // THEN 各位置的机会数等于三局之和
    // AND 删除其中一局后，机会数相应减少
    @MainActor
    func testCountsAccumulateAcrossSessionsAndShrinkWhenOneIsDeleted() throws {
        let sessions = [42, 18, 7].map { Self.session(seed: UInt64($0), handCount: 15) }
        XCTAssertTrue(sessions.allSatisfy { $0.count == 15 })

        let all = SessionFrequencyReport.counts(in: sessions.flatMap { $0 })
        let perSession = sessions.map { SessionFrequencyReport.counts(in: $0) }

        XCTAssertFalse(all.isEmpty)
        for key in all.keys {
            let summed = perSession.reduce(0) { $0 + ($1[key]?.opportunities ?? 0) }
            XCTAssertEqual(all[key]?.opportunities, summed, "\(key) 的机会数不是三局之和")
        }
        // Three sessions really do contribute; otherwise the sum above is one
        // session's counts plus two zeroes.
        XCTAssertTrue(
            perSession.allSatisfy { !$0.isEmpty },
            "有 Session 没有贡献任何机会"
        )

        let afterDeletion = SessionFrequencyReport.counts(in: sessions.dropLast().flatMap { $0 })
        let dropped = perSession[2]
        XCTAssertFalse(dropped.isEmpty)
        for (key, count) in dropped {
            XCTAssertEqual(
                (afterDeletion[key]?.opportunities ?? 0) + count.opportunities,
                all[key]?.opportunities,
                "删掉第三局之后 \(key) 的机会数不对"
            )
        }
        XCTAssertLessThan(
            afterDeletion.values.reduce(0) { $0 + $1.opportunities },
            all.values.reduce(0) { $0 + $1.opportunities }
        )
    }

    // GIVEN 一份任意的 Session 记录集合
    // WHEN 计算频率报告两次，第二次在重新读取记录之后
    // THEN 两次结果逐字段相等
    @MainActor
    func testTheReportCanBeRecomputedFromTheRecordsOnDisk() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = try FileSessionRecordStore(directory: directory)
        let pack = try Self.shippedPack()

        for (index, seed) in [UInt64(42), 18].enumerated() {
            let id = UUID(uuidString: "5E551000-0000-0000-0000-00000000004\(index)")!
            try await store.create(SessionRecord(id: id, seed: seed, handCount: 15))
            try await SessionPlaythrough.play(sessionID: id, store: store)
        }

        let first = try await SessionFrequencyReport.make(store: store, installedContent: pack)
        // A second store over the same directory, so the hands are decoded
        // again rather than served from anything the first one kept.
        let reopened = try FileSessionRecordStore(directory: directory)
        let second = try await SessionFrequencyReport.make(store: reopened, installedContent: pack)

        XCTAssertFalse(first.rows.isEmpty, "两份空报告相等说明不了任何事")
        XCTAssertGreaterThan(first.rows.reduce(0) { $0 + $1.opportunities }, 15)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.rows, second.rows)
        XCTAssertEqual(first.leaks.map(\.key), second.leaks.map(\.key))

        // And it is the hands on disk that produced it, not the sessions that
        // happened to be played in this process.
        var handsOnDisk: [SessionHandRecord] = []
        for id in try await store.sessionIDs() {
            handsOnDisk.append(contentsOf: try await store.hands(for: id))
        }
        XCTAssertEqual(handsOnDisk.count, 30)
        XCTAssertEqual(
            SessionFrequencyReport.make(hands: handsOnDisk, installedContent: pack),
            first
        )
    }

    // MARK: - Fixtures

    /// Every seat folds when it can, so the action reaches nobody it does not
    /// have to. Used to produce a hand the hero is never asked about.
    private struct FoldingTable: SessionActionPolicy {
        func chooseAction(at decision: DecisionPoint, using rng: inout SplitMix64) -> DecisionAction {
            decision.legalActions.contains(.fold) ? .fold : .check
        }
    }

    private static func session(seed: UInt64, handCount: Int) -> [SessionHandRecord] {
        SessionRunner(seed: seed).run(handCount: handCount).hands.map(SessionHandRecord.init)
    }

    private static func hand(
        seed: UInt64,
        handIndex: Int,
        policy: any SessionActionPolicy
    ) -> SessionHandRecord {
        SessionHandRecord(
            SessionRunner(seed: seed, policy: policy)
                .playHand(handIndex: handIndex, stacks: SessionRunner.initialStacks)
        )
    }

    @MainActor
    private static func shippedPack() throws -> StrategyPack {
        try BundledContentLoader(bundle: .main).loadPreferredPack().pack
    }

    /// A pack whose only scenario is an unopened button spot with the given
    /// range table.
    @MainActor
    private static func pack(buttonRange: [RangeCell]) throws -> StrategyPack {
        let template = try DecisionSessionFixture.makePack()
        let scenario = template.scenarios[0]

        return StrategyPack(
            manifest: template.manifest,
            curriculum: template.curriculum,
            scenarios: [
                DecisionScenario(
                    id: "rfi-btn",
                    title: "BTN 开池",
                    abilityDimension: scenario.abilityDimension,
                    curriculumNodeID: scenario.curriculumNodeID,
                    heroSeatOffsetFromButton: 0,
                    facing: .unopened,
                    heroCards: scenario.heroCards,
                    board: [],
                    decision: scenario.decision,
                    options: scenario.options,
                    rangeCells: buttonRange,
                    assumptions: scenario.assumptions,
                    explanation: scenario.explanation
                ),
            ]
        )
    }
}
