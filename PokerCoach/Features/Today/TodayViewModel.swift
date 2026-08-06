import Foundation
import Observation
import TrainingDomain

enum DebugTrainingCatalog {
    #if DEBUG
    static let cashItems = [
        TrainingCatalogItem(
            id: "cash-bet-sizing",
            scenarioID: "cash-bet-sizing",
            abilityDimension: "bet-sizing",
            estimatedMinutes: 4
        ),
        TrainingCatalogItem(
            id: "cash-preflop-range",
            scenarioID: "cash-preflop-range",
            abilityDimension: "preflop-range",
            estimatedMinutes: 2
        ),
        TrainingCatalogItem(
            id: "cash-flop-cbet",
            scenarioID: "cash-flop-cbet",
            abilityDimension: "flop-cbet",
            estimatedMinutes: 2
        ),
    ]
    #else
    static let cashItems: [TrainingCatalogItem] = []
    #endif
}

@MainActor
@Observable
final class TodayViewModel {
    private(set) var primaryItem: DailyPlanItem?
    private(set) var supportingItems: [DailyPlanItem] = []
    private(set) var durationText = "约 0 分钟"
    private(set) var failureMessage: String?

    private let eventStore: any TrainingEventStore
    private let reducer: PlayerModelReducer
    private let planner: TrainingPlanner
    private let catalog: [TrainingCatalogItem]
    private let now: @MainActor () -> Date

    init(
        eventStore: any TrainingEventStore,
        reducer: PlayerModelReducer,
        planner: TrainingPlanner,
        catalog: [TrainingCatalogItem] = DebugTrainingCatalog.cashItems,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.eventStore = eventStore
        self.reducer = reducer
        self.planner = planner
        self.catalog = catalog
        self.now = now
    }

    func refresh() async {
        do {
            let profile = reducer.reduce(events: try await eventStore.allEvents())
            let plan = planner.makePlan(
                profile: profile,
                catalog: catalog,
                now: now()
            )
            primaryItem = plan.items.first
            supportingItems = Array(plan.items.dropFirst())
            let totalMinutes = plan.items.reduce(0) { partialResult, item in
                partialResult + item.catalogItem.estimatedMinutes
            }
            durationText = "约 \(totalMinutes) 分钟"
            failureMessage = nil
        } catch {
            primaryItem = nil
            supportingItems = []
            durationText = "约 0 分钟"
            failureMessage = "读取训练记录失败，请重试"
        }
    }

    func startPrimaryItem() -> String? {
        primaryItem?.catalogItem.scenarioID
    }
}
