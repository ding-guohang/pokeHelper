import Foundation

public struct TrainingCatalogItem: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let scenarioID: String
    public let abilityDimension: String
    public let estimatedMinutes: Int

    public init(id: String, scenarioID: String, abilityDimension: String, estimatedMinutes: Int) {
        self.id = id
        self.scenarioID = scenarioID
        self.abilityDimension = abilityDimension
        self.estimatedMinutes = estimatedMinutes
    }
}

public struct DailyPlanItem: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let catalogItem: TrainingCatalogItem
    public let priority: Int
    public let reason: String

    public var abilityDimension: String {
        catalogItem.abilityDimension
    }

    public init(id: String, catalogItem: TrainingCatalogItem, priority: Int, reason: String) {
        self.id = id
        self.catalogItem = catalogItem
        self.priority = priority
        self.reason = reason
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
    public init() {}

    public func makePlan(
        profile: PlayerProfile,
        catalog: [TrainingCatalogItem],
        now: Date
    ) -> DailyPlan {
        let rankedItems = catalog
            .map { makePlanItem(for: $0, profile: profile, now: now) }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority > rhs.priority
                }
                return lhs.catalogItem.id < rhs.catalogItem.id
            }

        var selectedIDs = Set<String>()
        let items = rankedItems.filter { selectedIDs.insert($0.catalogItem.id).inserted }.prefix(3)

        return DailyPlan(generatedAt: now, items: Array(items))
    }

    private func makePlanItem(
        for catalogItem: TrainingCatalogItem,
        profile: PlayerProfile,
        now: Date
    ) -> DailyPlanItem {
        guard let snapshot = profile[catalogItem.abilityDimension] else {
            let priority = priority(meanScore: 60, highConfidenceErrorCount: 0, daysSincePractice: 7)
            return DailyPlanItem(
                id: catalogItem.id,
                catalogItem: catalogItem,
                priority: priority,
                reason: "Unseen ability: baseline score 60, 7 days since practice; priority \(priority)."
            )
        }

        let daysSincePractice = daysSince(snapshot.lastPracticedAt, now: now)
        let priority = priority(
            meanScore: snapshot.meanScore,
            highConfidenceErrorCount: snapshot.highConfidenceErrorCount,
            daysSincePractice: daysSincePractice
        )
        return DailyPlanItem(
            id: catalogItem.id,
            catalogItem: catalogItem,
            priority: priority,
            reason: "Mean score \(snapshot.meanScore), \(snapshot.highConfidenceErrorCount) high-confidence errors, \(daysSincePractice) days since practice; priority \(priority)."
        )
    }

    private func priority(
        meanScore: Int,
        highConfidenceErrorCount: Int,
        daysSincePractice: Int
    ) -> Int {
        (100 - meanScore)
            + min(highConfidenceErrorCount * 15, 45)
            + min(daysSincePractice * 2, 30)
    }

    private func daysSince(_ lastPracticedAt: Date?, now: Date) -> Int {
        guard let lastPracticedAt else {
            return 7
        }
        return max(0, Int(now.timeIntervalSince(lastPracticedAt) / 86_400))
    }
}
