import Foundation
@testable import TrainingDomain

enum PlayerProfileFixture {
    static func twoDimensions() -> PlayerProfile {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

        return PlayerProfile(abilities: [
            "bet-sizing": AbilitySnapshot(
                dimension: "bet-sizing",
                sampleCount: 2,
                meanScore: 60,
                meanLossRateBasisPoints: 400,
                highConfidenceErrorCount: 3,
                lastPracticedAt: referenceDate.addingTimeInterval(-86_400)
            ),
            "preflop-range": AbilitySnapshot(
                dimension: "preflop-range",
                sampleCount: 4,
                meanScore: 80,
                meanLossRateBasisPoints: 200,
                highConfidenceErrorCount: 0,
                lastPracticedAt: referenceDate
            ),
        ])
    }
}

enum TrainingCatalogFixture {
    static let items = [
        TrainingCatalogItem(id: "bet-sizing-002", scenarioID: "scenario-2", abilityDimension: "bet-sizing",
                curriculumNodeID: "node-" + "bet-sizing", estimatedMinutes: 5),
        TrainingCatalogItem(id: "preflop-range-001", scenarioID: "scenario-3", abilityDimension: "preflop-range",
                curriculumNodeID: "node-" + "preflop-range", estimatedMinutes: 5),
        TrainingCatalogItem(id: "bet-sizing-001", scenarioID: "scenario-1", abilityDimension: "bet-sizing",
                curriculumNodeID: "node-" + "bet-sizing", estimatedMinutes: 5),
    ]
}
