import XCTest
import TrainingDomain
@testable import PokerCoach

@MainActor
final class TodayViewModelTests: XCTestCase {
    func testWeakestDimensionBecomesPrimaryTraining() async throws {
        let fixture = DashboardFixture.withBetSizingWeakness()

        await fixture.today.refresh()

        XCTAssertEqual(fixture.today.primaryItem?.abilityDimension, "bet-sizing")
        XCTAssertEqual(fixture.today.durationText, "约 8 分钟")
    }

    func testRefreshRereadsAppendedEventsAndUpdatesDailyPlan() async throws {
        let fixture = DashboardFixture.empty()
        await fixture.today.refresh()
        let initialReason = try XCTUnwrap(fixture.today.primaryItem?.reason)

        await fixture.store.append(
            DashboardFixture.weakPreflopEvent(
                contentVersion: "2026.08.07"
            )
        )
        await fixture.today.refresh()

        XCTAssertEqual(fixture.today.state, .loaded)
        XCTAssertEqual(fixture.today.primaryItem?.abilityDimension, "preflop-range")
        XCTAssertEqual(fixture.today.supportingItems.count, 2)
        XCTAssertNotEqual(fixture.today.primaryItem?.reason, initialReason)
        XCTAssertEqual(fixture.today.durationText, "约 8 分钟")
        XCTAssertEqual(fixture.today.startPrimaryItem(), "cash-preflop-range")
    }

    func testTodayModelsLoadingEmptyAndRecoverableFailure() async {
        let emptyCatalog = TodayViewModel(
            eventStore: InMemoryTrainingEventStore(),
            reducer: PlayerModelReducer(),
            planner: TrainingPlanner(),
            catalog: []
        )
        XCTAssertEqual(emptyCatalog.state, .loading)
        await emptyCatalog.refresh()
        XCTAssertEqual(emptyCatalog.state, .empty)

        let failing = TodayViewModel(
            eventStore: FailingDashboardEventStore(),
            reducer: PlayerModelReducer(),
            planner: TrainingPlanner()
        )
        await failing.refresh()
        XCTAssertEqual(
            failing.state,
            .failed(message: "读取训练记录失败，请重试")
        )
    }

    func testLocalCatalogIsAvailableOutsideDebugStrategyContent() {
        XCTAssertEqual(M1ALocalTrainingCatalog.cashItems.count, 3)
        XCTAssertEqual(
            M1ALocalTrainingCatalog.cashItems.map(\.estimatedMinutes),
            [4, 2, 2]
        )
    }
}
