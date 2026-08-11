import Foundation
import Observation
import StrategyContent
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
    /// Renders the planner's own verdict rather than re-deriving one.
    ///
    /// This used to rebuild an explanation from the profile, which meant the
    /// screen could disagree with the ranking that actually placed the item —
    /// two implementations of "why is this here" with nothing keeping them in
    /// step.
    static func text(for item: DailyPlanItem, profile: PlayerProfile) -> String {
        let abilityName = AbilityDimensionPresentation.displayName(
            for: item.abilityDimension
        )
        let verdict = "\(abilityName)：\(headline(for: item.reason))"

        // The numbers are descriptive, not a second verdict: they say what the
        // profile holds, while the headline above says why the planner picked
        // this item. Keeping them separate is what stopped the screen from
        // being able to disagree with the ranking.
        guard let snapshot = profile[item.abilityDimension] else {
            return "\(verdict)（尚无训练记录，按基准分 60 分计算）"
        }
        return "\(verdict)（平均得分 \(snapshot.meanScore) 分，"
            + "高信心错误 \(snapshot.highConfidenceErrorCount) 次）"
    }

    static func headline(for reason: PlanItemReason) -> String {
        switch reason {
        case .weakness: "这是你当前最弱的一项"
        case .highConfidenceError: "你在这里有过很确信但亏损的判断"
        case .repetitionDue: "上次答错后到了复练时间"
        case .pathProgress: "学习路径上的下一步"
        }
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
    /// Diagnostic progress, or nil when there is no content to build one from.
    private(set) var diagnostic: DiagnosticSession?
    /// Skipping hides the prompt for this launch but leaves the entry on the
    /// page: the product promise is "openable and trainable", not "diagnosed
    /// or nothing".
    private(set) var hasSkippedDiagnostic = false

    var showsDiagnosticEntry: Bool {
        guard let diagnostic else { return false }
        return !diagnostic.isComplete
    }

    var showsDiagnosticPrompt: Bool {
        showsDiagnosticEntry && !hasSkippedDiagnostic
    }

    var diagnosticProgressText: String? {
        guard let diagnostic, !diagnostic.isComplete else { return nil }
        return "\(diagnostic.completedCount)/\(diagnostic.totalCount)"
    }

    func skipDiagnostic() {
        hasSkippedDiagnostic = true
    }

    /// The next unanswered diagnostic question, or nil when there is nothing
    /// left to ask.
    func startDiagnostic() -> String? {
        guard canStartTraining else {
            return nil
        }
        return diagnostic?.remaining.first?.scenarioID
    }
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
    /// Optional: Today still works with no content installed, it just cannot
    /// offer a diagnostic or resolve which repetitions are due.
    private let strategyProvider: (any StrategyPackProviding)?
    private let now: @MainActor () -> Date

    init(
        eventStore: any TrainingEventStore,
        reducer: PlayerModelReducer,
        planner: TrainingPlanner,
        catalog: [TrainingCatalogItem] = [],
        strategyContentAvailability: StrategyContentAvailability =
            .reviewedContentUnavailable,
        strategyProvider: (any StrategyPackProviding)? = nil,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.eventStore = eventStore
        self.reducer = reducer
        self.planner = planner
        self.catalog = catalog
        self.strategyContentAvailability = strategyContentAvailability
        self.strategyProvider = strategyProvider
        self.now = now
    }

    func refresh() async {
        state = .loading
        do {
            let events = try await eventStore.allEvents()
            let profile = reducer.reduce(events: events)
            let pack = try? await strategyProvider?.pack()

            if let pack {
                diagnostic = DiagnosticSession(
                    blueprint: .cash6MaxDefault,
                    pack: pack
                ).resuming(answeredScenarioIDs: Set(events.map(\.scenarioID)))
            }

            let dueNodeIDs = RepetitionScheduler().dueNodeIDs(
                events: events,
                pack: pack,
                now: now()
            )

            let plan = planner.makePlan(
                profile: profile,
                catalog: catalog,
                dueRepetitionNodeIDs: dueNodeIDs,
                now: now()
            )
            primaryItem = plan.items.first
            supportingItems = Array(plan.items.dropFirst())
            primaryReasonText = plan.items.first.map {
                TodayReasonPresentation.text(for: $0, profile: profile)
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
