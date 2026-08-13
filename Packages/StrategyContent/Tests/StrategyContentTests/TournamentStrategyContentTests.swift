import Foundation
import PokerCore
import Testing
@testable import StrategyContent

@Test func tournamentScenarioRequiresAll169HandsAndActionEVs() throws {
    let pack = try TournamentStrategyFixture.pack(rangeCells: [
        .init(
            handClass: "AA",
            actionWeightsBasisPoints: ["fold": 0, "raise": 10_000],
            actionEVs: [
                "fold": .init(milliBB: -500),
                "raise": .init(milliBB: 1_250),
            ]
        ),
    ])

    #expect(throws: StrategyPackValidationError.self) {
        try StrategyPackValidator().validate(pack)
    }
}

@Test func legacyCashPackStillDecodesWithoutTournamentFields() throws {
    let data = try fixtureURL("valid-pack.json")
    let pack = try StrategyPackLoader().load(data: data, expectedSHA256: nil)

    #expect(pack.scenarios[0].assumptions.tournament == nil)
    #expect(pack.scenarios[0].rangeCells.allSatisfy { $0.actionEVs == nil })
}

private enum TournamentStrategyFixture {
    static func pack(rangeCells: [RangeCell]) throws -> StrategyPack {
        let data = try fixtureURL("valid-pack.json")
        let legacy = try StrategyPackLoader().load(data: data, expectedSHA256: nil)
        let scenario = try #require(legacy.scenarios.first)
        let tournamentScenario = DecisionScenario(
            id: scenario.id,
            title: scenario.title,
            abilityDimension: scenario.abilityDimension,
            curriculumNodeID: scenario.curriculumNodeID,
            heroSeatOffsetFromButton: scenario.heroSeatOffsetFromButton,
            facing: scenario.facing,
            heroCards: scenario.heroCards,
            board: scenario.board,
            decision: scenario.decision,
            options: scenario.options,
            rangeCells: rangeCells,
            assumptions: SolverAssumptions(
                gameType: scenario.assumptions.gameType,
                tableSize: scenario.assumptions.tableSize,
                effectiveStack: scenario.assumptions.effectiveStack,
                rakeDescription: scenario.assumptions.rakeDescription,
                allowedBetSizeDescription: scenario.assumptions.allowedBetSizeDescription,
                tournament: .init(
                    effectiveBigBlinds: 100,
                    smallBlindCentiBB: 50,
                    bigBlindCentiBB: 100,
                    hasAnte: false,
                    anteDescription: "No ante",
                    equilibrium: .chipEV
                )
            ),
            explanation: scenario.explanation
        )
        return StrategyPack(
            manifest: legacy.manifest,
            curriculum: legacy.curriculum,
            scenarios: [tournamentScenario]
        )
    }
}

private func fixtureURL(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: nil) else {
        throw TournamentFixtureError.missing(name)
    }
    return try Data(contentsOf: url)
}

private enum TournamentFixtureError: Error {
    case missing(String)
}
