import Foundation
import Observation
import TrainingDomain

enum M1ALocalTrainingCatalog {
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
}

enum DashboardLoadState: Equatable {
    case loading
    case loaded
    case empty
    case failed(message: String)
}

enum TodayEmptyPresentation {
    static let buttonTitle = "前往训练"

    static func startTraining(_ onStartTraining: () -> Void) {
        onStartTraining()
    }
}

enum AbilityDimensionPresentation {
    static func displayName(for dimension: String) -> String {
        let normalized = dimension.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return switch normalized {
        case "bet-sizing":
            "下注尺度"
        case "preflop-range":
            "翻前范围"
        case "flop-cbet":
            "翻牌持续下注"
        case "":
            "未命名能力"
        default:
            "其他能力（\(normalized)）"
        }
    }
}

@MainActor
@Observable
final class TodayViewModel {
    private(set) var state: DashboardLoadState = .loading
    private(set) var primaryItem: DailyPlanItem?
    private(set) var supportingItems: [DailyPlanItem] = []
    private(set) var durationText = "约 0 分钟"
    private(set) var failureMessage: String?
    let strategyContentAvailability: StrategyContentAvailability

    var contentDisclosureText: String {
        strategyContentAvailability.disclosureText
    }

    private let eventStore: any TrainingEventStore
    private let reducer: PlayerModelReducer
    private let planner: TrainingPlanner
    private let catalog: [TrainingCatalogItem]
    private let now: @MainActor () -> Date

    init(
        eventStore: any TrainingEventStore,
        reducer: PlayerModelReducer,
        planner: TrainingPlanner,
        catalog: [TrainingCatalogItem] = M1ALocalTrainingCatalog.cashItems,
        strategyContentAvailability: StrategyContentAvailability =
            .reviewedContentUnavailable,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.eventStore = eventStore
        self.reducer = reducer
        self.planner = planner
        self.catalog = catalog
        self.strategyContentAvailability = strategyContentAvailability
        self.now = now
    }

    func refresh() async {
        state = .loading
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
            state = plan.items.isEmpty ? .empty : .loaded
        } catch {
            primaryItem = nil
            supportingItems = []
            durationText = "约 0 分钟"
            failureMessage = "读取训练记录失败，请重试"
            state = .failed(message: "读取训练记录失败，请重试")
        }
    }

    func startPrimaryItem() -> String? {
        primaryItem?.catalogItem.scenarioID
    }
}
