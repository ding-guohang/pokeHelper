import Foundation
import Observation
import TrainingDomain

@MainActor
@Observable
final class ReviewViewModel {
    private(set) var state: DashboardLoadState = .loading
    private(set) var abilities: [AbilitySnapshot] = []
    private(set) var history: [TrainingEvent] = []
    private(set) var suggestedTraining: DailyPlanItem?
    private(set) var failureMessage: String?

    private let eventStore: any TrainingEventStore
    private let reducer: PlayerModelReducer
    private let planner: TrainingPlanner
    private let catalog: [TrainingCatalogItem]
    private let now: @MainActor () -> Date

    init(
        eventStore: any TrainingEventStore,
        reducer: PlayerModelReducer,
        planner: TrainingPlanner = TrainingPlanner(),
        catalog: [TrainingCatalogItem] = M1ALocalTrainingCatalog.cashItems,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.eventStore = eventStore
        self.reducer = reducer
        self.planner = planner
        self.catalog = catalog
        self.now = now
    }

    func refresh() async {
        state = .loading
        do {
            let events = try await eventStore.allEvents()
            let profile = reducer.reduce(events: events)
            abilities = profile.abilities.values.sorted(by: Self.isWeakerFirst)
            history = events.sorted(by: Self.isMoreRecentFirst)
            suggestedTraining = planner.makePlan(
                profile: profile,
                catalog: catalog,
                now: now()
            ).items.first
            failureMessage = nil
            state = events.isEmpty ? .empty : .loaded
        } catch {
            abilities = []
            history = []
            suggestedTraining = nil
            failureMessage = "读取复盘记录失败，请重试"
            state = .failed(message: "读取复盘记录失败，请重试")
        }
    }

    func startSuggestedTraining() -> String? {
        suggestedTraining?.catalogItem.scenarioID
    }

    func contentDisclosure(for event: TrainingEvent) -> String? {
        StrategyContentMetadata.disclosure(
            forStrategyPackID: event.strategyPackID
        )
    }

    private static func isWeakerFirst(
        _ lhs: AbilitySnapshot,
        _ rhs: AbilitySnapshot
    ) -> Bool {
        if lhs.meanScore != rhs.meanScore {
            return lhs.meanScore < rhs.meanScore
        }
        if lhs.highConfidenceErrorCount != rhs.highConfidenceErrorCount {
            return lhs.highConfidenceErrorCount > rhs.highConfidenceErrorCount
        }
        if lhs.meanLossRateBasisPoints != rhs.meanLossRateBasisPoints {
            return lhs.meanLossRateBasisPoints > rhs.meanLossRateBasisPoints
        }
        return lhs.dimension < rhs.dimension
    }

    private static func isMoreRecentFirst(
        _ lhs: TrainingEvent,
        _ rhs: TrainingEvent
    ) -> Bool {
        if lhs.occurredAt != rhs.occurredAt {
            return lhs.occurredAt > rhs.occurredAt
        }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}
