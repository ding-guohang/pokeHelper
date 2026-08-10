import Foundation
import PokerCore
import StrategyContent
import TrainingDomain

/// A three-node curriculum with a controllable number of scenarios per node.
enum LearnFixture {
    static func pack(
        turnBarrelScenarioCount: Int = 3,
        riverScenarioCount: Int = 2
    ) -> StrategyPack {
        var scenarios: [DecisionScenario] = []
        scenarios += (0 ..< 2).map { scenario(id: "cbet-\($0)", node: "flop-cbet") }
        scenarios += (0 ..< turnBarrelScenarioCount).map {
            scenario(id: "turn-\($0)", node: "turn-barrel")
        }
        scenarios += (0 ..< riverScenarioCount).map {
            scenario(id: "river-\($0)", node: "river-bluff-catch")
        }

        return StrategyPack(
            manifest: StrategyPackManifest(
                id: "learn-pack",
                schemaVersion: 1,
                contentVersion: "2026.08.10",
                reviewStatus: .unverifiedDraft,
                generatedSource: "learn-fixture",
                origin: .fixture,
                reviewedBy: nil,
                reviewedAt: nil
            ),
            curriculum: [
                CurriculumNode(id: "flop-cbet", title: "翻牌持续下注", prerequisiteNodeIDs: []),
                CurriculumNode(
                    id: "turn-barrel",
                    title: "转牌第二枪",
                    prerequisiteNodeIDs: ["flop-cbet"]
                ),
                CurriculumNode(
                    id: "river-bluff-catch",
                    title: "河牌抓诈",
                    prerequisiteNodeIDs: ["turn-barrel"]
                ),
            ],
            scenarios: scenarios
        )
    }

    /// Four answers in turn-barrel: enough to make every mastery signal report
    /// a partial value rather than zero across the board.
    static func earlyProgressEvents() -> [TrainingEvent] {
        (0 ..< 4).map { index in
            event(
                scenarioID: "turn-\(index % 3)",
                quality: index == 0 ? .blunder : .excellent,
                secondsAfterEpoch: Double(index) * 3_600
            )
        }
    }

    private static func event(
        scenarioID: String,
        quality: DecisionQuality,
        secondsAfterEpoch: Double
    ) -> TrainingEvent {
        let lossRate = quality == .blunder ? 800 : 0

        return TrainingEvent(
            id: UUID(),
            localUserID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            deviceID: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            occurredAt: Date(timeIntervalSince1970: 1_786_000_000 + secondsAfterEpoch),
            scenarioID: scenarioID,
            strategyPackID: "learn-pack",
            strategyContentVersion: "2026.08.10",
            abilityDimension: "turn-barrel",
            submission: DecisionSubmission(action: .check, confidence: .unsure),
            grade: DecisionGrade(
                selectedAction: .check,
                selectedFrequencyBasisPoints: 10_000,
                selectedEV: EVAmount(milliBB: 1_000 - lossRate / 2),
                bestEV: EVAmount(milliBB: 1_000),
                evLoss: EVAmount(milliBB: lossRate / 2),
                lossRateBasisPoints: lossRate,
                score: max(0, 100 - lossRate / 5),
                quality: quality,
                isStrategicallyAvailable: true
            )
        )
    }

    private static func scenario(id: String, node: String) -> DecisionScenario {
        DecisionScenario(
            id: id,
            title: id,
            abilityDimension: node,
            curriculumNodeID: node,
            heroSeatOffsetFromButton: 0,
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
                    frequencyBasisPoints: 10_000,
                    ev: EVAmount(milliBB: 1_000)
                ),
            ],
            rangeCells: [],
            assumptions: SolverAssumptions(
                gameType: "NLHE cash",
                tableSize: 6,
                effectiveStack: BBAmount(centiBB: 10_000),
                rakeDescription: "5% capped",
                allowedBetSizeDescription: "50%"
            ),
            explanation: StructuredExplanation(
                conclusion: "占位。",
                rangeReasoning: "占位。",
                boardReasoning: "占位。",
                opponentReasoning: "占位。",
                futurePlan: "占位。",
                gtoBaseline: "占位。",
                exploitCondition: nil
            )
        )
    }
}
