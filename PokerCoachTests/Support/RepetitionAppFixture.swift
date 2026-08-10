import Foundation
import PokerCore
import StrategyContent
import TrainingDomain

/// Content whose curriculum node IDs differ from its ability dimensions, the
/// way shipped content does.
///
/// Fixtures that set the two to the same string cannot distinguish a component
/// that keys on one from a component that keys on the other.
enum RepetitionAppFixture {
    static let epoch = Date(timeIntervalSince1970: 1_786_000_000)

    static let pack = StrategyPack(
        manifest: StrategyPackManifest(
            id: "repetition-pack",
            schemaVersion: 1,
            contentVersion: "2026.08.10",
            reviewStatus: .reviewed,
            generatedSource: "repetition-fixture",
            reviewedBy: "fixture",
            reviewedAt: Date(timeIntervalSince1970: 1_786_000_000)
        ),
        curriculum: [
            CurriculumNode(id: "turn-barrel", title: "转牌第二枪", prerequisiteNodeIDs: []),
            CurriculumNode(id: "flop-cbet", title: "翻牌持续下注", prerequisiteNodeIDs: []),
        ],
        scenarios: [
            scenario(id: "s-turn-1", node: "turn-barrel"),
            scenario(id: "s-turn-2", node: "turn-barrel"),
            scenario(id: "s-flop-1", node: "flop-cbet"),
        ]
    )

    /// Both catalog entries share one ability dimension and differ only by
    /// node, so a planner keying on the dimension cannot tell them apart.
    static let catalog = [
        TrainingCatalogItem(
            id: "turn-item",
            scenarioID: "s-turn-2",
            abilityDimension: "postflop",
            curriculumNodeID: "turn-barrel",
            estimatedMinutes: 4
        ),
        TrainingCatalogItem(
            id: "flop-item",
            scenarioID: "s-flop-1",
            abilityDimension: "postflop",
            curriculumNodeID: "flop-cbet",
            estimatedMinutes: 4
        ),
    ]

    static func event(
        scenarioID: String,
        quality: DecisionQuality,
        daysAfterEpoch: Double
    ) -> TrainingEvent {
        let lossRate = quality == .blunder ? 800 : 0
        return TrainingEvent(
            id: UUID(),
            localUserID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            deviceID: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            occurredAt: epoch.addingTimeInterval(daysAfterEpoch * 86_400),
            scenarioID: scenarioID,
            strategyPackID: "repetition-pack",
            strategyContentVersion: "2026.08.10",
            abilityDimension: "postflop",
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
            abilityDimension: "postflop",
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
