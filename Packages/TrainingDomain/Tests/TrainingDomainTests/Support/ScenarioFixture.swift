import PokerCore
@testable import StrategyContent

enum ScenarioFixture {
    static func mixedStrategy() throws -> DecisionScenario {
        DecisionScenario(
            id: "mixed-strategy",
            title: "Mixed strategy scoring fixture",
            abilityDimension: "flop",
            curriculumNodeID: "flop",
            heroSeatOffsetFromButton: 0,
            heroCards: [try card("As"), try card("Kd")],
            board: [try card("7c"), try card("8h"), try card("2s")],
            decision: BettingDecisionContext(
                pot: .init(centiBB: 650),
                effectiveStack: .init(centiBB: 9_700),
                amountToCall: .init(centiBB: 0),
                minimumRaiseTo: nil,
                configuredBetSizes: [.init(centiBB: 217), .init(centiBB: 488)]
            ),
            options: [
                .init(action: .check, frequencyBasisPoints: 4_000, ev: .init(milliBB: 1_000)),
                .init(action: .bet(to: .init(centiBB: 217)), frequencyBasisPoints: 3_500, ev: .init(milliBB: 980)),
                .init(action: .bet(to: .init(centiBB: 488)), frequencyBasisPoints: 2_500, ev: .init(milliBB: 700)),
            ],
            rangeCells: [],
            assumptions: .init(
                gameType: "NLHE",
                tableSize: 6,
                effectiveStack: .init(centiBB: 10_000),
                rakeDescription: "fixture",
                allowedBetSizeDescription: "fixture"
            ),
            explanation: .init(
                conclusion: "fixture",
                rangeReasoning: "fixture",
                boardReasoning: "fixture",
                opponentReasoning: "fixture",
                futurePlan: "fixture",
                gtoBaseline: "fixture",
                exploitCondition: nil
            )
        )
    }

    private static func card(_ code: String) throws -> Card {
        guard let card = Card(code: code) else {
            throw FixtureError.invalidCard(code)
        }

        return card
    }
}

private enum FixtureError: Error {
    case invalidCard(String)
}
