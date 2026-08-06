import Testing
import PokerCore
import StrategyContent
@testable import TrainingDomain

@Test func highestEVActionScoresOneHundred() throws {
    let scenario = try ScenarioFixture.mixedStrategy()
    let grade = try DecisionScorer().grade(
        submission: .init(action: scenario.options[0].action, confidence: .verySure),
        scenario: scenario
    )

    #expect(grade.evLoss == .init(milliBB: 0))
    #expect(grade.score == 100)
    #expect(grade.quality == .excellent)
}

@Test func closeMixedActionRemainsAcceptable() throws {
    let scenario = try ScenarioFixture.mixedStrategy()
    let grade = try DecisionScorer().grade(
        submission: .init(action: scenario.options[1].action, confidence: .unsure),
        scenario: scenario
    )

    #expect(grade.evLoss == .init(milliBB: 20))
    #expect(grade.quality == .acceptable)
    #expect(grade.isStrategicallyAvailable)
}

@Test func unlistedActionIsRejected() throws {
    let scenario = try ScenarioFixture.mixedStrategy()

    #expect(throws: DecisionScoringError.actionNotInStrategy) {
        try DecisionScorer().grade(
            submission: .init(action: .fold, confidence: .guessing),
            scenario: scenario
        )
    }
}
