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

@Test(arguments: [
    TournamentAssumptionMutation.tableSize(6),
    .smallBlind(25),
    .bigBlind(200),
    .hasAnte(true),
    .rake("5% capped"),
])
private func tournamentChipEVRequiresBoundHUAssumptions(
    mutation: TournamentAssumptionMutation
) throws {
    let pack = try TournamentStrategyFixture.validPack(mutating: mutation)

    #expect(
        throws: StrategyPackValidationError.invalidTournamentAssumptions(
            scenarioID: StrategyPackFixture.scenarioID
        )
    ) {
        try StrategyPackValidator().validate(pack)
    }
}

@Test func tournamentDepthRequiresExactCentiBBStackMatch() throws {
    let pack = try TournamentStrategyFixture.validPack(
        mutating: .effectiveStack(.init(centiBB: 10_001))
    )

    #expect(
        throws: StrategyPackValidationError.inconsistentTournamentEffectiveStack(
            scenarioID: StrategyPackFixture.scenarioID
        )
    ) {
        try StrategyPackValidator().validate(pack)
    }
}

private enum TournamentAssumptionMutation: Sendable {
    case tableSize(Int)
    case smallBlind(Int)
    case bigBlind(Int)
    case hasAnte(Bool)
    case rake(String)
    case effectiveStack(BBAmount)
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

    static func validPack(
        mutating mutation: TournamentAssumptionMutation
    ) throws -> StrategyPack {
        let tournament = TournamentSolverAssumptions(
            effectiveBigBlinds: 100,
            smallBlindCentiBB: 50,
            bigBlindCentiBB: 100,
            hasAnte: false,
            anteDescription: "No ante",
            equilibrium: .chipEV
        )
        let cells = canonicalHands.map {
            RangeCell(
                handClass: $0,
                actionWeightsBasisPoints: ["fold": 0, "raise": 10_000],
                actionEVs: [
                    "fold": .init(milliBB: -500),
                    "raise": .init(milliBB: 1_250),
                ]
            )
        }
        let baseline = try pack(rangeCells: cells)
        let scenario = try #require(baseline.scenarios.first)

        let tableSize: Int
        let smallBlind: Int
        let bigBlind: Int
        let hasAnte: Bool
        let rake: String
        let effectiveStack: BBAmount
        switch mutation {
        case let .tableSize(value):
            tableSize = value; smallBlind = 50; bigBlind = 100; hasAnte = false
            rake = "0"; effectiveStack = .init(centiBB: 10_000)
        case let .smallBlind(value):
            tableSize = 2; smallBlind = value; bigBlind = 100; hasAnte = false
            rake = "0"; effectiveStack = .init(centiBB: 10_000)
        case let .bigBlind(value):
            tableSize = 2; smallBlind = 50; bigBlind = value; hasAnte = false
            rake = "0"; effectiveStack = .init(centiBB: 10_000)
        case let .hasAnte(value):
            tableSize = 2; smallBlind = 50; bigBlind = 100; hasAnte = value
            rake = "0"; effectiveStack = .init(centiBB: 10_000)
        case let .rake(value):
            tableSize = 2; smallBlind = 50; bigBlind = 100; hasAnte = false
            rake = value; effectiveStack = .init(centiBB: 10_000)
        case let .effectiveStack(value):
            tableSize = 2; smallBlind = 50; bigBlind = 100; hasAnte = false
            rake = "0"; effectiveStack = value
        }

        let mutated = DecisionScenario(
            id: scenario.id, title: scenario.title,
            abilityDimension: scenario.abilityDimension,
            curriculumNodeID: scenario.curriculumNodeID,
            heroSeatOffsetFromButton: scenario.heroSeatOffsetFromButton,
            facing: scenario.facing, heroCards: scenario.heroCards,
            board: scenario.board, decision: scenario.decision,
            options: scenario.options, rangeCells: scenario.rangeCells,
            assumptions: .init(
                gameType: scenario.assumptions.gameType,
                tableSize: tableSize, effectiveStack: effectiveStack,
                rakeDescription: rake,
                allowedBetSizeDescription: scenario.assumptions.allowedBetSizeDescription,
                tournament: .init(
                    effectiveBigBlinds: tournament.effectiveBigBlinds,
                    smallBlindCentiBB: smallBlind, bigBlindCentiBB: bigBlind,
                    hasAnte: hasAnte, anteDescription: tournament.anteDescription,
                    equilibrium: tournament.equilibrium
                )
            ), explanation: scenario.explanation
        )
        return .init(manifest: baseline.manifest, curriculum: baseline.curriculum, scenarios: [mutated])
    }
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

private func fixtureURL(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: nil) else {
        throw TournamentFixtureError.missing(name)
    }
    return try Data(contentsOf: url)
}

private enum TournamentFixtureError: Error {
    case missing(String)
}
