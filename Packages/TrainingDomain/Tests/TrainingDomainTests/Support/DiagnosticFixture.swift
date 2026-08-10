import Foundation
import PokerCore
import StrategyContent
@testable import TrainingDomain

/// Content wide enough for the diagnostic to sample across every axis its
/// blueprint declares, plus a deliberately thin variant.
enum DiagnosticFixture {
    static let dimensions = ["preflop-range", "flop-cbet", "turn-barrel", "river-bluff-catch"]

    /// Every combination of four dimensions, six seats, four streets and two
    /// stack depths, so a failure to spread is the blueprint's doing and not
    /// the fixture's.
    static func pack() -> StrategyPack {
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
        return pack(scenarios: scenarios)
    }

    /// Four scenarios in one dimension, all on the same seat, street and stack.
    static func thinPack() -> StrategyPack {
        pack(
            scenarios: (0 ..< 4).map {
                scenario(
                    id: "thin-\($0)",
                    dimension: "flop-cbet",
                    seat: 0,
                    boardSize: 3,
                    stackCentiBB: 10_000
                )
            }
        )
    }

    static func catalog() -> [TrainingCatalogItem] {
        dimensions.enumerated().map { index, dimension in
            TrainingCatalogItem(
                id: "item-\(index)",
                scenarioID: "\(dimension)-s0-t1-k1",
                abilityDimension: dimension,
                curriculumNodeID: dimension,
                estimatedMinutes: 2
            )
        }
    }

    private static func pack(scenarios: [DecisionScenario]) -> StrategyPack {
        StrategyPack(
            manifest: StrategyPackManifest(
                id: "diagnostic-pack",
                schemaVersion: 1,
                contentVersion: "2026.08.10",
                reviewStatus: .testFixture,
                generatedSource: "diagnostic-fixture",
                origin: .fixture,
                reviewedBy: nil,
                reviewedAt: nil
            ),
            curriculum: dimensions.map {
                CurriculumNode(id: $0, title: $0, prerequisiteNodeIDs: [])
            },
            scenarios: scenarios
        )
    }

    private static let deck = [
        "2c", "3d", "4h", "5s", "6c", "7d", "8h", "9s", "Tc", "Jd", "Qh", "Ks", "Ac",
    ]

    private static func scenario(
        id: String,
        dimension: String,
        seat: Int,
        boardSize: Int,
        stackCentiBB: Int
    ) -> DecisionScenario {
        // Board cards come from a fixed deck slice keyed on the ID so no two
        // cards in one scenario repeat, which the validator forbids.
        //
        // The offset is a character sum, not `hashValue`: Swift seeds hashing
        // per process, so a hash-derived board would differ between runs and
        // make this fixture non-deterministic across processes.
        let offset = id.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 6 }
        let board = (0 ..< boardSize).map { deck[($0 + offset) % (deck.count - 2)] }

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
