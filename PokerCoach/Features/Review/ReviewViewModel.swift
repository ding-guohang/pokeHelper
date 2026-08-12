import Foundation
import Observation
import StrategyContent
import TrainingDomain

@MainActor
@Observable
final class ReviewViewModel {
    private(set) var state: DashboardLoadState = .loading
    private(set) var abilities: [AbilitySnapshot] = []
    private(set) var history: [TrainingEvent] = []
    private(set) var suggestedTraining: DailyPlanItem?
    private(set) var failureMessage: String?
    let strategyContentAvailability: StrategyContentAvailability

    var canStartTraining: Bool {
        strategyContentAvailability.canStartTraining
    }

    var trainingUnavailableExplanation: String? {
        guard !canStartTraining else {
            return nil
        }
        return "未安装已审核策略内容，当前仅可查看复盘。"
    }

    private let eventStore: any TrainingEventStore
    private let reducer: PlayerModelReducer
    private let planner: TrainingPlanner
    private let catalog: [TrainingCatalogItem]
    /// Optional, like Today's: Review still lists history with no content
    /// installed, it just cannot resolve which repetitions are due.
    private let strategyProvider: (any StrategyPackProviding)?
    /// Review status and origin of each installed pack, keyed by pack ID.
    private let installedContent: [String: (ReviewStatus, ContentOrigin)]
    private let now: @MainActor () -> Date

    init(
        eventStore: any TrainingEventStore,
        reducer: PlayerModelReducer,
        planner: TrainingPlanner = TrainingPlanner(),
        catalog: [TrainingCatalogItem] = [],
        strategyContentAvailability: StrategyContentAvailability =
            .reviewedContentUnavailable,
        strategyProvider: (any StrategyPackProviding)? = nil,
        installedContent: [String: (ReviewStatus, ContentOrigin)] = [:],
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.eventStore = eventStore
        self.reducer = reducer
        self.planner = planner
        self.catalog = catalog
        self.strategyContentAvailability = strategyContentAvailability
        self.strategyProvider = strategyProvider
        self.installedContent = installedContent
        self.now = now
    }

    func refresh() async {
        state = .loading
        do {
            let events = try await eventStore.allEvents()
            let profile = reducer.reduce(events: events)
            abilities = profile.abilitiesWeakestFirst
            history = events.sorted(by: Self.isMoreRecentFirst)
            // Same inputs as Today, due-repetition term included. Omitting it
            // here let the two screens name different first items from the
            // same profile and the same catalog.
            let pack = try? await strategyProvider?.pack()
            suggestedTraining = planner.makePlan(
                profile: profile,
                catalog: catalog,
                dueRepetitionNodeIDs: RepetitionScheduler().dueNodeIDs(
                    events: events,
                    pack: pack,
                    now: now()
                ),
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
        guard canStartTraining else {
            return nil
        }
        return suggestedTraining?.catalogItem.scenarioID
    }

    /// Disclosure for one history entry, resolved from the review status of
    /// the pack that produced it.
    ///
    /// Returns a disclosure — never nil — when the pack is not installed. A
    /// history entry whose provenance cannot be established has to say so:
    /// falling back to nil would render `unverifiedDraft` history with no
    /// label at all, which reads as endorsement.
    func contentDisclosure(for event: TrainingEvent) -> String? {
        guard let installed = installedContent[event.strategyPackID] else {
            return StrategyContentMetadata.unknownProvenanceDisclosure
        }
        return StrategyContentMetadata.disclosure(
            forReviewStatus: installed.0,
            origin: installed.1
        )
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
