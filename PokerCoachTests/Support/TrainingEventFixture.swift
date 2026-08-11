import Foundation
import TrainingDomain

/// Builds real graded events for tests that care about storage and identity
/// rather than scoring. The grade comes from the real scorer so the fixture
/// can never drift from a shape the domain would reject.
@MainActor
enum TrainingEventFixture {
    static func make(
        id: UUID = UUID(),
        localUserID: UUID,
        deviceID: UUID,
        occurredAt: Date = Date(timeIntervalSince1970: 1_786_172_800),
        dimension: String = "bet-sizing"
    ) throws -> TrainingEvent {
        let scenario = try DecisionSessionFixture.makePack(
            abilityDimension: dimension
        ).scenarios[0]
        let submission = DecisionSubmission(
            action: scenario.options[0].action,
            confidence: .verySure
        )
        let grade = try DecisionScorer().grade(
            submission: submission,
            scenario: scenario
        )
        return TrainingEvent(
            id: id,
            localUserID: localUserID,
            deviceID: deviceID,
            occurredAt: occurredAt,
            scenarioID: scenario.id,
            strategyPackID: "cash-pack",
            strategyContentVersion: "2026.08.06",
            abilityDimension: dimension,
            submission: submission,
            grade: grade
        )
    }
}
