import Foundation
import Testing
@testable import TrainingDomain

@Test func plannerPrioritizesHighConfidenceWeakness() throws {
    let profile = PlayerProfileFixture.twoDimensions()
    let plan = TrainingPlanner().makePlan(
        profile: profile,
        catalog: TrainingCatalogFixture.items,
        now: Date(timeIntervalSince1970: 1_800_000_000)
    )

    #expect(plan.items.first?.abilityDimension == "bet-sizing")
    #expect(plan.items.first?.priority == 87)
    #expect(plan.items.count == 3)
}

@Test func plannerUsesUnseenDefaultsAndBreaksPriorityTiesByItemID() throws {
    let plan = TrainingPlanner().makePlan(
        profile: .init(abilities: [:]),
        catalog: [
            .init(id: "unseen-b", scenarioID: "scenario-b", abilityDimension: "unseen", estimatedMinutes: 5),
            .init(id: "unseen-a", scenarioID: "scenario-a", abilityDimension: "unseen", estimatedMinutes: 5),
        ],
        now: Date(timeIntervalSince1970: 1_800_000_000)
    )

    #expect(plan.items.map(\.priority) == [54, 54])
    #expect(plan.items.map(\.id) == ["unseen-a", "unseen-b"])
    #expect(plan.items.allSatisfy { $0.reason.contains("Unseen") })
}
