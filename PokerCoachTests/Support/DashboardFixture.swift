import Foundation
import TrainingDomain
@testable import PokerCoach

@MainActor
struct DashboardFixture {
    let today: TodayViewModel
    let review: ReviewViewModel

    static func withBetSizingWeakness() -> DashboardFixture {
        make(events: [
            event(
                id: "40000000-0000-0000-0000-000000000001",
                occurredAt: 1_786_000_000,
                score: 40,
                confidence: .verySure,
                dimension: "bet-sizing"
            ),
            event(
                id: "40000000-0000-0000-0000-000000000002",
                occurredAt: 1_786_086_400,
                score: 80,
                confidence: .unsure,
                dimension: "preflop-range"
            ),
        ])
    }

    static func withTwoDimensions() -> DashboardFixture {
        withBetSizingWeakness()
    }

    private static func make(events: [TrainingEvent]) -> DashboardFixture {
        let store = InMemoryTrainingEventStore(events: events)

        let reducer = PlayerModelReducer()
        let planner = TrainingPlanner()
        return DashboardFixture(
            today: TodayViewModel(
                eventStore: store,
                reducer: reducer,
                planner: planner,
                catalog: DebugTrainingCatalog.cashItems,
                now: { Date(timeIntervalSince1970: 1_786_086_400) }
            ),
            review: ReviewViewModel(
                eventStore: store,
                reducer: reducer
            )
        )
    }

    private static func event(
        id: String,
        occurredAt: TimeInterval,
        score: Int,
        confidence: DecisionConfidence,
        dimension: String
    ) -> TrainingEvent {
        let scenario = DecisionSessionFixture.makePack(
            abilityDimension: dimension,
            foldEVMilliBB: score < 50 ? 200 : 0
        ).scenarios[0]
        let action = score < 50
            ? scenario.options[0].action
            : scenario.options[1].action
        let submission = DecisionSubmission(
            action: action,
            confidence: confidence
        )
        let grade = try! DecisionScorer().grade(
            submission: submission,
            scenario: scenario
        )
        return TrainingEvent(
            id: UUID(uuidString: id)!,
            localUserID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            deviceID: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            occurredAt: Date(timeIntervalSince1970: occurredAt),
            scenarioID: "fixture-\(dimension)",
            strategyPackID: "cash-pack",
            strategyContentVersion: "2026.08.06",
            abilityDimension: dimension,
            submission: submission,
            grade: grade
        )
    }
}
