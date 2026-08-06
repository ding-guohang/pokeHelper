import Foundation
import Observation
import TrainingDomain

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

enum TodayReasonPresentation {
    static func text(
        for item: DailyPlanItem,
        profile: PlayerProfile,
        now: Date
    ) -> String {
        let abilityName = AbilityDimensionPresentation.displayName(
            for: item.abilityDimension
        )
        guard let snapshot = profile[item.abilityDimension] else {
            return "尚无\(abilityName)训练记录，按基准分 60 分、距上次练习 7 天计算；优先级 \(item.priority)。"
        }

        let daysSincePractice = snapshot.lastPracticedAt.map {
            max(0, Int(now.timeIntervalSince($0) / 86_400))
        } ?? 7
        return "\(abilityName)平均得分 \(snapshot.meanScore) 分，高信心错误 \(snapshot.highConfidenceErrorCount) 次，距上次练习 \(daysSincePractice) 天；优先级 \(item.priority)。"
    }
}

@MainActor
@Observable
final class TodayViewModel {
    private(set) var state: DashboardLoadState = .loading
    private(set) var primaryItem: DailyPlanItem?
    private(set) var supportingItems: [DailyPlanItem] = []
    private(set) var primaryReasonText: String?
    private(set) var durationText = "约 0 分钟"
    private(set) var failureMessage: String?
    let strategyContentAvailability: StrategyContentAvailability

    var contentDisclosureText: String {
        strategyContentAvailability.disclosureText
    }

    var canStartTraining: Bool {
        strategyContentAvailability.canStartTraining
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
        catalog: [TrainingCatalogItem] = [],
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
            primaryReasonText = plan.items.first.map {
                TodayReasonPresentation.text(
                    for: $0,
                    profile: profile,
                    now: plan.generatedAt
                )
            }
            let totalMinutes = plan.items.reduce(0) { partialResult, item in
                partialResult + item.catalogItem.estimatedMinutes
            }
            durationText = "约 \(totalMinutes) 分钟"
            failureMessage = nil
            state = plan.items.isEmpty ? .empty : .loaded
        } catch {
            primaryItem = nil
            supportingItems = []
            primaryReasonText = nil
            durationText = "约 0 分钟"
            failureMessage = "读取训练记录失败，请重试"
            state = .failed(message: "读取训练记录失败，请重试")
        }
    }

    func startPrimaryItem() -> String? {
        guard canStartTraining else {
            return nil
        }
        return primaryItem?.catalogItem.scenarioID
    }
}
