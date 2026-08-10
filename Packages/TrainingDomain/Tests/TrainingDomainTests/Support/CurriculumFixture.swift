import Foundation
import PokerCore
import StrategyContent
@testable import TrainingDomain

/// Packs and events for the curriculum, repetition and mastery tests.
///
/// Events are described by the grade they should carry rather than by raw
/// EV numbers, so a test can say "a very-sure blunder" and stay readable.
enum CurriculumFixture {
    static let packID = "cash-pack"
    static let contentVersion = "2026.08.06"
    static let epoch = Date(timeIntervalSince1970: 1_786_000_000)

    static func pack(
        packID: String = CurriculumFixture.packID,
        contentVersion: String = CurriculumFixture.contentVersion,
        scenarios: [(id: String, node: String)] = [("scenario-1", "turn-barrel")],
        nodes: [(id: String, prerequisites: [String])] = [("turn-barrel", [])]
    ) -> StrategyPack {
        StrategyPack(
            manifest: StrategyPackManifest(
                id: packID,
                schemaVersion: 1,
                contentVersion: contentVersion,
                reviewStatus: .testFixture,
                generatedSource: "curriculum-fixture",
                reviewedBy: nil,
                reviewedAt: nil
            ),
            curriculum: nodes.map {
                CurriculumNode(id: $0.id, title: $0.id, prerequisiteNodeIDs: $0.prerequisites)
            },
            scenarios: scenarios.map { scenario(id: $0.id, node: $0.node) }
        )
    }

    static func event(
        scenarioID: String = "scenario-1",
        packID: String = CurriculumFixture.packID,
        contentVersion: String = CurriculumFixture.contentVersion,
        abilityDimension: String = "bet-sizing",
        quality: DecisionQuality = .excellent,
        confidence: DecisionConfidence = .unsure,
        daysAfterEpoch: Double = 0,
        id: UUID = UUID()
    ) -> TrainingEvent {
        let lossRate = Self.lossRateBasisPoints(for: quality)
        let evLossMilliBB = lossRate / 2

        return TrainingEvent(
            id: id,
            localUserID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            deviceID: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            occurredAt: epoch.addingTimeInterval(daysAfterEpoch * 86_400),
            scenarioID: scenarioID,
            strategyPackID: packID,
            strategyContentVersion: contentVersion,
            abilityDimension: abilityDimension,
            submission: DecisionSubmission(action: .check, confidence: confidence),
            grade: DecisionGrade(
                selectedAction: .check,
                selectedFrequencyBasisPoints: 10_000,
                selectedEV: EVAmount(milliBB: 1_000 - evLossMilliBB),
                bestEV: EVAmount(milliBB: 1_000),
                evLoss: EVAmount(milliBB: evLossMilliBB),
                lossRateBasisPoints: lossRate,
                score: max(0, 100 - lossRate / 5),
                quality: quality,
                isStrategicallyAvailable: true
            )
        )
    }

    /// A representative loss rate inside each quality band, so a fixture can be
    /// written in terms of the grade a reader cares about.
    static func lossRateBasisPoints(for quality: DecisionQuality) -> Int {
        switch quality {
        case .excellent: 0
        case .acceptable: 50
        case .improvable: 300
        case .blunder: 800
        }
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
