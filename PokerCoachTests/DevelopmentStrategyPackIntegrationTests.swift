import Foundation
import PokerCore
import StrategyContent
import XCTest
@testable import PokerCoach

@MainActor
final class DevelopmentStrategyPackIntegrationTests: XCTestCase {
    func testDevelopmentPackBuildsCompleteLoadableDailyPlan() async throws {
        let fixtureURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "DevStrategyPack",
                withExtension: "json"
            )
        )
        let data = try Data(contentsOf: fixtureURL)
        let pack = try StrategyPackLoader().load(
            data: data,
            expectedSHA256: nil
        )

        XCTAssertEqual(pack.manifest.reviewStatus, .testFixture)
        XCTAssertEqual(
            pack.scenarios.map(\.id),
            [
                "cash-bet-sizing",
                "cash-preflop-range",
                "cash-flop-cbet",
            ]
        )
        XCTAssertEqual(Set(pack.scenarios.map(\.id)).count, 3)

        let dependencies = AppDependencies.availableContent(
            eventStore: InMemoryTrainingEventStore(),
            strategyPack: pack,
            strategyContentAvailability: .developmentFixtureAvailable
        )
        let today = TodayViewModel(
            eventStore: dependencies.eventStore,
            reducer: dependencies.playerModelReducer,
            planner: dependencies.planner,
            catalog: dependencies.localTrainingCatalog,
            strategyContentAvailability:
                dependencies.strategyContentAvailability
        )

        await today.refresh()

        XCTAssertEqual(
            today.primaryItem?.catalogItem.scenarioID,
            "cash-bet-sizing"
        )
        XCTAssertEqual(today.supportingItems.count, 2)
        let plannedScenarioIDs = (
            [today.primaryItem].compactMap { $0 }
                + today.supportingItems
        ).map(\.catalogItem.scenarioID)
        XCTAssertEqual(Set(plannedScenarioIDs).count, 3)

        for scenarioID in plannedScenarioIDs {
            _ = try await dependencies.strategyProvider.scenario(id: scenarioID)
        }

        let totalMinutes = (
            [today.primaryItem].compactMap { $0 }
                + today.supportingItems
        ).reduce(0) { $0 + $1.catalogItem.estimatedMinutes }
        XCTAssertTrue((5...10).contains(totalMinutes))
        XCTAssertEqual(today.durationText, "约 9 分钟")

        let firstScenario = try XCTUnwrap(pack.scenarios.first)
        XCTAssertTrue(
            firstScenario.options.contains {
                $0.action == .bet(to: .init(centiBB: 217))
            }
        )
    }
}
