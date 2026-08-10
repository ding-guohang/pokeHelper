import Foundation
import PokerCore
import StrategyContent
@testable import StrategyToolingCore

/// Builds solver exports in code. Exports are the importer's input, so they are
/// constructed rather than loaded from disk: a test that wants a specific
/// defect (a frequency total that misses 10,000, say) needs to state it
/// directly, not bury it in a JSON blob.
enum SolverExportFixture {
    static func export(
        nodeCount: Int,
        frequencyTotalOverride: Int? = nil
    ) -> SolverExport {
        SolverExport(
            packID: "cash-6max-100bb-core",
            generatedSource: "fixture-solver 1.0",
            exportedAt: Date(timeIntervalSince1970: 1_786_000_000),
            gameType: "NLHE cash",
            tableSize: 6,
            effectiveStack: BBAmount(centiBB: 10_000),
            rakeDescription: "5% capped at 3BB",
            allowedBetSizeDescription: "33%, 75%",
            curriculum: [
                SolverCurriculumNode(
                    id: "flop-cbet",
                    title: "翻牌持续下注",
                    prerequisiteNodeIDs: []
                ),
            ],
            nodes: (0 ..< nodeCount).map { index in
                node(
                    index: index,
                    // Only the last node carries the defect, so a builder that
                    // stops at the first node cannot pass by accident.
                    frequencyTotalOverride: index == nodeCount - 1
                        ? frequencyTotalOverride
                        : nil
                )
            }
        )
    }

    static func node(index: Int, frequencyTotalOverride: Int? = nil) -> SolverNode {
        let checkFrequency = frequencyTotalOverride.map { $0 - 4_000 } ?? 6_000
        return SolverNode(
            id: "node-\(index)",
            title: "场景 \(index)",
            abilityDimension: "flop-cbet",
            curriculumNodeID: "flop-cbet",
            heroSeatOffsetFromButton: index % 6,
            heroCards: ["As", "Kd"],
            board: ["7c", "8h", "2s"],
            pot: BBAmount(centiBB: 650),
            amountToCall: BBAmount(centiBB: 0),
            minimumRaiseTo: nil,
            configuredBetSizes: [BBAmount(centiBB: 217)],
            actions: [
                SolverAction(
                    action: .check,
                    frequencyBasisPoints: checkFrequency,
                    ev: EVAmount(milliBB: 1_000)
                ),
                SolverAction(
                    action: .bet(to: BBAmount(centiBB: 217)),
                    frequencyBasisPoints: 4_000,
                    ev: EVAmount(milliBB: 1_200)
                ),
            ],
            rangeCells: [
                SolverRangeCell(
                    handClass: "AKo",
                    actionWeightsBasisPoints: ["check": 6_000, "bet": 4_000]
                ),
                SolverRangeCell(
                    handClass: "72o",
                    actionWeightsBasisPoints: ["check": 10_000]
                ),
            ],
            explanation: SolverExplanation(
                conclusion: "以中等频率持续下注。",
                rangeReasoning: "范围含强牌与需要保护的边缘牌。",
                boardReasoning: "低连牌面让小尺度有用。",
                opponentReasoning: "假设对手平衡继续。",
                futurePlan: "按转牌与尺度继续。",
                gtoBaseline: "基线是过牌与小注的混合。",
                exploitCondition: nil
            )
        )
    }
}
