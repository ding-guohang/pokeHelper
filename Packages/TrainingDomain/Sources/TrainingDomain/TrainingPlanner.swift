import Foundation

public struct TrainingCatalogItem: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let scenarioID: String
    public let abilityDimension: String
    /// The curriculum node this scenario belongs to.
    ///
    /// Separate from `abilityDimension` because they are different namespaces:
    /// several nodes can exercise one dimension. Repetition is scheduled per
    /// node, so matching due repetitions against the dimension silently never
    /// matched at all in the shipped content, where every scenario is
    /// `preflop-range` but nodes are `preflop-rfi` and `preflop-vs-3bet`.
    public let curriculumNodeID: String
    public let estimatedMinutes: Int

    public init(
        id: String,
        scenarioID: String,
        abilityDimension: String,
        curriculumNodeID: String,
        estimatedMinutes: Int
    ) {
        self.id = id
        self.scenarioID = scenarioID
        self.abilityDimension = abilityDimension
        self.curriculumNodeID = curriculumNodeID
        self.estimatedMinutes = estimatedMinutes
    }
}

/// Why an item earned its place in today's plan.
///
/// An enumeration rather than prose: the screen has to explain the choice, and
/// free text cannot be asserted against without pinning the wording.
public enum PlanItemReason: String, Equatable, Codable, Sendable, CaseIterable {
    case weakness
    case highConfidenceError
    case repetitionDue
    case pathProgress
}

public struct DailyPlanItem: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let catalogItem: TrainingCatalogItem
    public let priority: Int
    public let reason: PlanItemReason
    /// Diagnostic detail behind the reason. Not for display: the screen renders
    /// `reason`, this exists so a failing plan can be read in a log.
    public let reasonDetail: String

    public var abilityDimension: String {
        catalogItem.abilityDimension
    }

    public init(
        id: String,
        catalogItem: TrainingCatalogItem,
        priority: Int,
        reason: PlanItemReason,
        reasonDetail: String
    ) {
        self.id = id
        self.catalogItem = catalogItem
        self.priority = priority
        self.reason = reason
        self.reasonDetail = reasonDetail
    }
}

public struct DailyPlan: Equatable, Codable, Sendable {
    public let generatedAt: Date
    public let items: [DailyPlanItem]

    public init(generatedAt: Date, items: [DailyPlanItem]) {
        self.generatedAt = generatedAt
        self.items = items
    }
}

public struct TrainingPlanner: Sendable {
    /// The plan aims to fill this many minutes and never to exceed the upper
    /// bound, so a session stays inside the time the product promises.
    public static let targetMinutes = 5 ... 10

    public init() {}

    public func makePlan(
        profile: PlayerProfile,
        catalog: [TrainingCatalogItem],
        dueRepetitionNodeIDs: Set<String> = [],
        pathDimensions: Set<String> = [],
        now: Date
    ) -> DailyPlan {
        let rankedItems = catalog
            .map {
                makePlanItem(
                    for: $0,
                    profile: profile,
                    isRepetitionDue: dueRepetitionNodeIDs.contains($0.curriculumNodeID),
                    isOnPath: pathDimensions.contains($0.abilityDimension),
                    now: now
                )
            }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority > rhs.priority
                }
                return lhs.catalogItem.id < rhs.catalogItem.id
            }

        return DailyPlan(generatedAt: now, items: fill(from: rankedItems))
    }

    /// Takes items in priority order while they fit the window.
    ///
    /// Keeps scanning after a skip rather than stopping at the first item that
    /// does not fit, so a long item cannot truncate an otherwise full plan. A
    /// single candidate longer than the window is still taken: the user opened
    /// the app to train, and an empty plan serves them worse than an overrun.
    private func fill(from ranked: [DailyPlanItem]) -> [DailyPlanItem] {
        var selected: [DailyPlanItem] = []
        var seenIDs: Set<String> = []
        var minutes = 0

        for item in ranked where seenIDs.insert(item.catalogItem.id).inserted {
            let candidate = minutes + item.catalogItem.estimatedMinutes
            if candidate <= Self.targetMinutes.upperBound {
                selected.append(item)
                minutes = candidate
            }
        }

        if selected.isEmpty, let first = ranked.first {
            return [first]
        }
        return selected
    }

    private func makePlanItem(
        for catalogItem: TrainingCatalogItem,
        profile: PlayerProfile,
        isRepetitionDue: Bool,
        isOnPath: Bool,
        now: Date
    ) -> DailyPlanItem {
        let snapshot = profile[catalogItem.abilityDimension]
        let meanScore = snapshot?.meanScore ?? 60
        let highConfidenceErrorCount = snapshot?.highConfidenceErrorCount ?? 0
        let daysSincePractice = daysSince(snapshot?.lastPracticedAt, now: now)

        let weakness = 100 - meanScore
        let confidence = min(highConfidenceErrorCount * 15, 45)
        let staleness = min(daysSincePractice * 2, 30)
        let due = isRepetitionDue ? 10 : 0
        let path = isOnPath ? 5 : 0

        return DailyPlanItem(
            id: catalogItem.id,
            catalogItem: catalogItem,
            priority: weakness + confidence + staleness + due + path,
            reason: Self.dominantReason(
                weakness: weakness + staleness,
                confidence: confidence,
                due: due,
                path: path
            ),
            reasonDetail: snapshot == nil
                ? "Unseen ability: baseline score 60, 7 days since practice."
                : "Mean score \(meanScore), \(highConfidenceErrorCount) high-confidence errors, \(daysSincePractice) days since practice, due: \(isRepetitionDue), on path: \(isOnPath)."
        )
    }

    /// The largest contribution decides the reason shown.
    ///
    /// Staleness counts toward weakness rather than getting a case of its own:
    /// the product vocabulary has four reasons, and "you have not practised
    /// this lately" is the same message to the user as "this is weak".
    private static func dominantReason(
        weakness: Int,
        confidence: Int,
        due: Int,
        path: Int
    ) -> PlanItemReason {
        let ranked: [(PlanItemReason, Int)] = [
            (.highConfidenceError, confidence),
            (.repetitionDue, due),
            (.pathProgress, path),
            (.weakness, weakness),
        ]
        // Written as an explicit scan rather than max(by:): the tie-break has
        // to be the listed order so the reason is stable for equal inputs, and
        // which element max(by:) keeps among equals is not worth relying on.
        var best = ranked[0]
        for candidate in ranked.dropFirst() where candidate.1 > best.1 {
            best = candidate
        }
        return best.0
    }

    private func daysSince(_ lastPracticedAt: Date?, now: Date) -> Int {
        guard let lastPracticedAt else {
            return 7
        }
        return max(0, Int(now.timeIntervalSince(lastPracticedAt) / 86_400))
    }
}
