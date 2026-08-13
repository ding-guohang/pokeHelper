import Foundation
import PokerCore
import StrategyContent
import Testing
@testable import StrategyToolingCore

@Test func packBuilderPreservesTournamentFieldsAndDecisionStack() throws {
    let cells = canonicalHands.map { handClass in
        SolverRangeCell(
            handClass: handClass,
            actionWeightsBasisPoints: ["fold": 0, "raise": 10_000],
            actionEVs: [
                "fold": .init(milliBB: -500),
                "raise": .init(milliBB: 1_250),
            ]
        )
    }
    let source = SolverExportFixture.export(nodeCount: 1)
    let node = SolverNode(
        id: source.nodes[0].id,
        title: source.nodes[0].title,
        abilityDimension: source.nodes[0].abilityDimension,
        curriculumNodeID: source.nodes[0].curriculumNodeID,
        heroSeatOffsetFromButton: source.nodes[0].heroSeatOffsetFromButton,
        facing: source.nodes[0].facing,
        heroCards: source.nodes[0].heroCards,
        board: source.nodes[0].board,
        pot: source.nodes[0].pot,
        amountToCall: source.nodes[0].amountToCall,
        minimumRaiseTo: source.nodes[0].minimumRaiseTo,
        configuredBetSizes: source.nodes[0].configuredBetSizes,
        decisionEffectiveStack: .init(centiBB: 2_000),
        actions: source.nodes[0].actions,
        rangeCells: cells,
        explanation: source.nodes[0].explanation
    )
    let export = SolverExport(
        packID: source.packID,
        generatedSource: source.generatedSource,
        exportedAt: source.exportedAt,
        gameType: source.gameType,
        tableSize: source.tableSize,
        effectiveStack: source.effectiveStack,
        rakeDescription: source.rakeDescription,
        allowedBetSizeDescription: source.allowedBetSizeDescription,
        tournament: .init(
            effectiveBigBlinds: 100,
            smallBlindCentiBB: 50,
            bigBlindCentiBB: 100,
            hasAnte: false,
            anteDescription: "No ante",
            equilibrium: .chipEV
        ),
        curriculum: source.curriculum,
        nodes: [node]
    )

    let pack = try PackBuilder().build(
        from: export,
        contentVersion: "2026.08.13",
        reviewStatus: .unverifiedDraft,
        origin: .fixture,
        reviewedBy: nil,
        reviewedAt: nil
    )

    let scenario = try #require(pack.scenarios.first)
    #expect(scenario.assumptions.tournament?.equilibrium == .chipEV)
    #expect(scenario.decision.effectiveStack == .init(centiBB: 2_000))
    #expect(scenario.rangeCells[0].actionEVs == cells[0].actionEVs)
}

private let canonicalHands: [String] = {
    let ranks = ["A", "K", "Q", "J", "T", "9", "8", "7", "6", "5", "4", "3", "2"]
    return ranks.enumerated().flatMap { row, high in
        ranks.enumerated().map { column, low in
            if row == column { return high + low }
            return row < column ? high + low + "s" : low + high + "o"
        }
    }
}()
