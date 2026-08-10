import Foundation
import PokerCore
import StrategyContent
import TrainingDomain

/// Content wide enough for the twelve-question diagnostic, plus a catalog and
/// events shaped to match it.
enum DiagnosticContentFixture {
    static let now = Date(timeIntervalSince1970: 1_786_000_000)
    static let dimensions = [
        "preflop-range", "flop-cbet", "turn-barrel", "river-bluff-catch",
    ]

    static let pack: StrategyPack = {
        var scenarios: [DecisionScenario] = []
        for dimension in dimensions {
            for seat in 0 ..< 6 {
                for (streetIndex, boardSize) in [0, 3, 4, 5].enumerated() {
                    for (stackIndex, stack) in [5_000, 10_000].enumerated() {
                        scenarios.append(
                            scenario(
                                id: "\(dimension)-s\(seat)-t\(streetIndex)-k\(stackIndex)",
                                dimension: dimension,
                                seat: seat,
                                boardSize: boardSize,
                                stackCentiBB: stack
                            )
                        )
                    }
                }
            }
        }

        return StrategyPack(
            manifest: StrategyPackManifest(
                id: "diagnostic-pack",
                schemaVersion: 1,
                contentVersion: "2026.08.10",
                reviewStatus: .unverifiedDraft,
                generatedSource: "diagnostic-content-fixture",
                reviewedBy: nil,
                reviewedAt: nil
            ),
            curriculum: dimensions.map {
                CurriculumNode(id: $0, title: $0, prerequisiteNodeIDs: [])
            },
            scenarios: scenarios
        )
    }()

    static let catalog: [TrainingCatalogItem] = dimensions.enumerated().map {
        TrainingCatalogItem(
            id: "item-\($0.offset)",
            scenarioID: "\($0.element)-s0-t1-k1",
            abilityDimension: $0.element,
                curriculumNodeID: "node-" + $0.element,
            estimatedMinutes: 2
        )
    }

    static func event(scenarioID: String) -> TrainingEvent {
        TrainingEvent(
            id: UUID(),
            localUserID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            deviceID: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            occurredAt: now.addingTimeInterval(-3_600),
            scenarioID: scenarioID,
            strategyPackID: "diagnostic-pack",
            strategyContentVersion: "2026.08.10",
            abilityDimension: "preflop-range",
            submission: DecisionSubmission(action: .check, confidence: .unsure),
            grade: DecisionGrade(
                selectedAction: .check,
                selectedFrequencyBasisPoints: 10_000,
                selectedEV: EVAmount(milliBB: 1_000),
                bestEV: EVAmount(milliBB: 1_000),
                evLoss: EVAmount(milliBB: 0),
                lossRateBasisPoints: 0,
                score: 100,
                quality: .excellent,
                isStrategicallyAvailable: true
            )
        )
    }

    private static let deck = [
        "2c", "3d", "4h", "5s", "6c", "7d", "8h", "9s", "Tc", "Jd", "Qh",
    ]

    private static func scenario(
        id: String,
        dimension: String,
        seat: Int,
        boardSize: Int,
        stackCentiBB: Int
    ) -> DecisionScenario {
        // Character sum, not hashValue: Swift seeds hashing per process, so a
        // hash-derived board would differ between runs.
        let offset = id.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 6 }
        let board = (0 ..< boardSize).map { deck[($0 + offset) % deck.count] }

        return DecisionScenario(
            id: id,
            title: id,
            abilityDimension: dimension,
            curriculumNodeID: dimension,
            heroSeatOffsetFromButton: seat,
            heroCards: [Card(code: "Ad")!, Card(code: "Kc")!],
            board: board.map { Card(code: $0)! },
            decision: BettingDecisionContext(
                pot: BBAmount(centiBB: 1_000),
                effectiveStack: BBAmount(centiBB: stackCentiBB),
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
                effectiveStack: BBAmount(centiBB: stackCentiBB),
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
