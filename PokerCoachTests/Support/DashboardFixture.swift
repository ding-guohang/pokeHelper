import Foundation
import TrainingDomain
@testable import PokerCoach

@MainActor
struct DashboardFixture {
    let today: TodayViewModel
    let review: ReviewViewModel
    let store: InMemoryTrainingEventStore

    static let catalog = [
        TrainingCatalogItem(
            id: "cash-bet-sizing",
            scenarioID: "cash-bet-sizing",
            abilityDimension: "bet-sizing",
            curriculumNodeID: "node-bet-sizing",
            estimatedMinutes: 4
        ),
        TrainingCatalogItem(
            id: "cash-preflop-range",
            scenarioID: "cash-preflop-range",
            abilityDimension: "preflop-range",
            curriculumNodeID: "node-preflop-range",
            estimatedMinutes: 2
        ),
        TrainingCatalogItem(
            id: "cash-flop-cbet",
            scenarioID: "cash-flop-cbet",
            abilityDimension: "flop-cbet",
            curriculumNodeID: "node-flop-cbet",
            estimatedMinutes: 2
        ),
    ]

    static func withBetSizingWeakness() throws -> DashboardFixture {
        make(events: [
            try event(
                id: "40000000-0000-0000-0000-000000000001",
                occurredAt: 1_786_000_000,
                score: 40,
                confidence: .verySure,
                dimension: "bet-sizing"
            ),
            try event(
                id: "40000000-0000-0000-0000-000000000002",
                occurredAt: 1_786_086_400,
                score: 80,
                confidence: .unsure,
                dimension: "preflop-range"
            ),
        ])
    }

    static func withTwoDimensions() throws -> DashboardFixture {
        try withBetSizingWeakness()
    }

    static func empty() -> DashboardFixture {
        make(events: [])
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
                catalog: catalog,
                strategyContentAvailability:
                    .developmentFixtureAvailable,
                now: { Date(timeIntervalSince1970: 1_786_086_400) }
            ),
            review: ReviewViewModel(
                eventStore: store,
                reducer: reducer,
                planner: planner,
                catalog: catalog,
                strategyContentAvailability:
                    .developmentFixtureAvailable,
                now: { Date(timeIntervalSince1970: 1_786_086_400) }
            ),
            store: store
        )
    }

    static func weakPreflopEvent(
        contentVersion: String
    ) throws -> TrainingEvent {
        try event(
            id: "40000000-0000-0000-0000-000000000003",
            occurredAt: 1_786_172_800,
            score: 0,
            confidence: .verySure,
            dimension: "preflop-range",
            contentVersion: contentVersion
        )
    }

    static func developmentBetSizingEvent() throws -> TrainingEvent {
        try event(
            id: "40000000-0000-0000-0000-000000000004",
            occurredAt: 1_786_172_800,
            score: 40,
            confidence: .verySure,
            dimension: "bet-sizing",
            strategyPackID: "cash-6max-100bb-dev"
        )
    }

    private static func event(
        id: String,
        occurredAt: TimeInterval,
        score: Int,
        confidence: DecisionConfidence,
        dimension: String,
        contentVersion: String = "2026.08.06",
        strategyPackID: String = "cash-pack"
    ) throws -> TrainingEvent {
        let scenario = try DecisionSessionFixture.makePack(
            abilityDimension: dimension,
            foldEVMilliBB: score == 0 ? 0 : (score < 50 ? 200 : 0)
        ).scenarios[0]
        let action = score < 50
            ? scenario.options[0].action
            : scenario.options[1].action
        let submission = DecisionSubmission(
            action: action,
            confidence: confidence
        )
        let grade = try DecisionScorer().grade(
            submission: submission,
            scenario: scenario
        )
        return TrainingEvent(
            id: UUID(uuidString: id)!,
            localUserID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            deviceID: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            occurredAt: Date(timeIntervalSince1970: occurredAt),
            scenarioID: "fixture-\(dimension)",
            strategyPackID: strategyPackID,
            strategyContentVersion: contentVersion,
            abilityDimension: dimension,
            submission: submission,
            grade: grade
        )
    }
}

actor FailingDashboardEventStore: TrainingEventStore {
    enum Failure: Error {
        case unavailable
    }

    func append(_ event: TrainingEvent) throws {
        throw Failure.unavailable
    }

    func allEvents() throws -> [TrainingEvent] {
        throw Failure.unavailable
    }

    func events(after checkpoint: UUID?) throws -> [TrainingEvent] {
        throw Failure.unavailable
    }
}
