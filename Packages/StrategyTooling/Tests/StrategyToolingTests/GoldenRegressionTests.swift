import Foundation
import PokerCore
import StrategyContent
import TrainingDomain
import Testing
@testable import StrategyToolingCore

@Suite("内容升级黄金回归")
struct GoldenRegressionTests {
    private let regression = GoldenRegression()

    // GIVEN 某场景的 lossRateBasisPoints 从 40 变为 260
    // WHEN 运行升级回归
    // THEN 以非零码失败，报告含场景 ID、旧值、新值与跨越的 quality 边界
    @Test("跨越 quality 边界时失败")
    func failsWhenGradingCrossesAQualityBoundary() throws {
        let report = try regression.compare(
            old: GoldenFixture.pack(checkEVMilliBB: 960),
            new: GoldenFixture.pack(checkEVMilliBB: 740),
            cases: GoldenFixture.cases,
            toleranceBasisPoints: 500
        )

        #expect(report.exitCode != 0)
        let change = try #require(report.changes.first)
        #expect(change.scenarioID == GoldenFixture.scenarioID)
        #expect(change.oldLossRateBasisPoints == 40)
        #expect(change.newLossRateBasisPoints == 260)
        #expect(change.oldQuality == .acceptable)
        #expect(change.newQuality == .improvable)
        #expect(change.crossesQualityBoundary)
    }

    // GIVEN 变化在容差内且不跨越边界
    // WHEN 运行回归
    // THEN 以零码通过，但报告仍逐条列出变化量
    @Test("容差内通过但仍逐条报告")
    func passesWithinToleranceAndStillReportsEveryDelta() throws {
        let report = try regression.compare(
            old: GoldenFixture.pack(checkEVMilliBB: 960),
            new: GoldenFixture.pack(checkEVMilliBB: 930),
            cases: GoldenFixture.cases,
            toleranceBasisPoints: 500
        )

        #expect(report.exitCode == 0)
        // Passing has to list the deltas too. Otherwise "nothing changed" and
        // "changed but within tolerance" look identical in the output, and the
        // upgrade becomes a black box.
        #expect(report.changes.count == 1)
        #expect(report.changes[0].deltaBasisPoints == 30)
        #expect(report.changes[0].crossesQualityBoundary == false)
    }

    @Test("完全没有变化时也逐条报告")
    func reportsEveryCaseEvenWhenNothingMoved() throws {
        let report = try regression.compare(
            old: GoldenFixture.pack(checkEVMilliBB: 960),
            new: GoldenFixture.pack(checkEVMilliBB: 960),
            cases: GoldenFixture.cases,
            toleranceBasisPoints: 500
        )

        #expect(report.exitCode == 0)
        #expect(report.changes.count == 1)
        #expect(report.changes[0].deltaBasisPoints == 0)
    }

    // A large move that stays inside one quality band is still a strategy
    // change the reviewer needs to see, so tolerance is enforced separately
    // from the band boundary.
    @Test("未跨边界但超出容差同样失败")
    func failsOnALargeMoveInsideOneQualityBand() throws {
        // 20 bp and 100 bp are both `acceptable` (the band is 11–100), so this
        // move is entirely inside one band while still exceeding the tolerance.
        let report = try regression.compare(
            old: GoldenFixture.pack(checkEVMilliBB: 980),
            new: GoldenFixture.pack(checkEVMilliBB: 900),
            cases: GoldenFixture.cases,
            toleranceBasisPoints: 50
        )

        #expect(report.exitCode != 0)
        #expect(report.changes[0].oldQuality == .acceptable)
        #expect(report.changes[0].newQuality == .acceptable)
        #expect(report.changes[0].crossesQualityBoundary == false)
        #expect(report.changes[0].deltaBasisPoints == 80)
    }

    // Dropping a scenario silently would let an upgrade shrink coverage while
    // every surviving case still matched.
    @Test("新包缺少黄金场景时失败")
    func failsWhenTheNewPackNoLongerHasAGoldenScenario() throws {
        let report = try regression.compare(
            old: GoldenFixture.pack(checkEVMilliBB: 960),
            new: GoldenFixture.pack(checkEVMilliBB: 960, scenarioID: "renamed"),
            cases: GoldenFixture.cases,
            toleranceBasisPoints: 500
        )

        #expect(report.exitCode != 0)
        #expect(report.missingScenarioIDs == [GoldenFixture.scenarioID])
    }
}

enum GoldenFixture {
    static let scenarioID = "golden-scenario"

    static let cases = [
        GoldenCase(
            scenarioID: scenarioID,
            submission: DecisionSubmission(action: .check, confidence: .verySure)
        ),
    ]

    /// A pack whose best action is a 1,000 milli-BB bet, with the check option's
    /// EV parameterised so a test can place the loss rate anywhere it needs.
    ///
    /// The pot is 1,000 centi-BB, so lossRateBasisPoints is evLoss in milli-BB:
    /// (1000 - checkEV) * 10,000 / (1000 * 10).
    static func pack(
        checkEVMilliBB: Int,
        scenarioID: String = GoldenFixture.scenarioID
    ) -> StrategyPack {
        StrategyPack(
            manifest: StrategyPackManifest(
                id: "golden-pack",
                schemaVersion: 1,
                contentVersion: "2026.08.10",
                reviewStatus: .unverifiedDraft,
                generatedSource: "golden-fixture",
                origin: .fixture,
                reviewedBy: nil,
                reviewedAt: nil
            ),
            curriculum: [
                CurriculumNode(id: "flop-cbet", title: "翻牌持续下注", prerequisiteNodeIDs: []),
            ],
            scenarios: [
                DecisionScenario(
                    id: scenarioID,
                    title: "黄金场景",
                    abilityDimension: "flop-cbet",
                    curriculumNodeID: "flop-cbet",
                    heroSeatOffsetFromButton: 0,
                    facing: .unopened,
                    heroCards: [Card(code: "As")!, Card(code: "Kd")!],
                    board: [Card(code: "7c")!, Card(code: "8h")!, Card(code: "2s")!],
                    decision: BettingDecisionContext(
                        pot: BBAmount(centiBB: 1_000),
                        effectiveStack: BBAmount(centiBB: 10_000),
                        amountToCall: BBAmount(centiBB: 0),
                        minimumRaiseTo: nil,
                        configuredBetSizes: [BBAmount(centiBB: 500)]
                    ),
                    options: [
                        StrategyOption(
                            action: .check,
                            frequencyBasisPoints: 6_000,
                            ev: EVAmount(milliBB: checkEVMilliBB)
                        ),
                        StrategyOption(
                            action: .bet(to: BBAmount(centiBB: 500)),
                            frequencyBasisPoints: 4_000,
                            ev: EVAmount(milliBB: 1_000)
                        ),
                    ],
                    rangeCells: [
                        RangeCell(
                            handClass: "AKo",
                            actionWeightsBasisPoints: ["check": 6_000, "bet": 4_000]
                        ),
                    ],
                    assumptions: SolverAssumptions(
                        gameType: "NLHE cash",
                        tableSize: 6,
                        effectiveStack: BBAmount(centiBB: 10_000),
                        rakeDescription: "5% capped",
                        allowedBetSizeDescription: "50%"
                    ),
                    explanation: StructuredExplanation(
                        conclusion: "以中等频率过牌。",
                        rangeReasoning: "范围含强牌。",
                        boardReasoning: "牌面干燥。",
                        opponentReasoning: "对手平衡。",
                        futurePlan: "按转牌继续。",
                        gtoBaseline: "混合策略。",
                        exploitCondition: nil
                    )
                ),
            ]
        )
    }
}
