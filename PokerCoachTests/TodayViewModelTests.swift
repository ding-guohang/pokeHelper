import XCTest
import TrainingDomain
@testable import PokerCoach

@MainActor
final class TodayViewModelTests: XCTestCase {
    func testUnavailableContentKeepsPlanButBlocksPrimaryRoute() async {
        let viewModel = TodayViewModel(
            eventStore: InMemoryTrainingEventStore(),
            reducer: PlayerModelReducer(),
            planner: TrainingPlanner(),
            catalog: DashboardFixture.catalog,
            strategyContentAvailability: .reviewedContentUnavailable
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(
            viewModel.primaryItem?.catalogItem.scenarioID,
            "cash-bet-sizing"
        )
        XCTAssertFalse(viewModel.canStartTraining)
        XCTAssertNil(viewModel.startPrimaryItem())
    }

    func testAvailableContentAllowsPrimaryRoute() async {
        for availability in [
            StrategyContentAvailability.developmentFixtureAvailable,
            .reviewedContentAvailable,
        ] {
            let viewModel = TodayViewModel(
                eventStore: InMemoryTrainingEventStore(),
                reducer: PlayerModelReducer(),
                planner: TrainingPlanner(),
                catalog: DashboardFixture.catalog,
                strategyContentAvailability: availability
            )

            await viewModel.refresh()

            XCTAssertTrue(viewModel.canStartTraining)
            XCTAssertEqual(
                viewModel.startPrimaryItem(),
                "cash-bet-sizing"
            )
        }
    }

    func testDevelopmentPlanDisclosesFixtureContent() async {
        let viewModel = TodayViewModel(
            eventStore: InMemoryTrainingEventStore(),
            reducer: PlayerModelReducer(),
            planner: TrainingPlanner(),
            catalog: DashboardFixture.catalog,
            strategyContentAvailability: .developmentFixtureAvailable
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.contentDisclosureText, "开发演示数据")
    }

    func testWeakestDimensionBecomesPrimaryTraining() async throws {
        let fixture = DashboardFixture.withBetSizingWeakness()

        await fixture.today.refresh()

        XCTAssertEqual(fixture.today.primaryItem?.abilityDimension, "bet-sizing")
        XCTAssertEqual(fixture.today.durationText, "约 8 分钟")
    }

    func testRefreshRereadsAppendedEventsAndUpdatesDailyPlan() async throws {
        let fixture = DashboardFixture.empty()
        await fixture.today.refresh()
        let initialReason = try XCTUnwrap(fixture.today.primaryItem?.reasonDetail)

        await fixture.store.append(
            DashboardFixture.weakPreflopEvent(
                contentVersion: "2026.08.07"
            )
        )
        await fixture.today.refresh()

        XCTAssertEqual(fixture.today.state, .loaded)
        XCTAssertEqual(fixture.today.primaryItem?.abilityDimension, "preflop-range")
        XCTAssertEqual(fixture.today.supportingItems.count, 2)
        // reason is an enum now and legitimately stays .weakness across this
        // change; the numbers behind it are what must move.
        XCTAssertNotEqual(fixture.today.primaryItem?.reasonDetail, initialReason)
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
            planner: TrainingPlanner(),
            catalog: DashboardFixture.catalog
        )
        await failing.refresh()
        XCTAssertEqual(
            failing.state,
            .failed(message: "读取训练记录失败，请重试")
        )
    }

    func testEmptyCatalogStaysEmptyWhenRefreshedAgain() async {
        let viewModel = TodayViewModel(
            eventStore: InMemoryTrainingEventStore(),
            reducer: PlayerModelReducer(),
            planner: TrainingPlanner(),
            catalog: []
        )

        await viewModel.refresh()
        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertNil(viewModel.startPrimaryItem())
    }

    func testEmptyPresentationRoutesToTrainingCallback() {
        var startTrainingCount = 0

        TodayEmptyPresentation.startTraining {
            startTrainingCount += 1
        }

        XCTAssertEqual(TodayEmptyPresentation.buttonTitle, "前往训练")
        XCTAssertEqual(startTrainingCount, 1)
    }

    func testDashboardFixtureCatalogKeepsExpectedDurations() {
        XCTAssertEqual(DashboardFixture.catalog.count, 3)
        XCTAssertEqual(
            DashboardFixture.catalog.map(\.estimatedMinutes),
            [4, 2, 2]
        )
    }

    func testUnseenPrimaryReasonIsPresentedInChinese() async throws {
        let fixture = DashboardFixture.empty()

        await fixture.today.refresh()

        XCTAssertEqual(
            fixture.today.primaryReasonText,
            "下注尺度：这是你当前最弱的一项（尚无训练记录，按基准分 60 分计算）"
        )
    }

    func testPracticedPrimaryReasonIsPresentedInChinese() async throws {
        let fixture = DashboardFixture.withBetSizingWeakness()

        await fixture.today.refresh()

        let reason = try XCTUnwrap(fixture.today.primaryReasonText)
        let item = try XCTUnwrap(fixture.today.primaryItem)
        XCTAssertTrue(reason.contains("下注尺度"))
        XCTAssertTrue(reason.contains("平均得分"))
        XCTAssertTrue(reason.contains("高信心错误"))
        XCTAssertFalse(reason.contains("Mean score"))
        // The verdict has to be the planner's, not one the screen re-derived.
        XCTAssertTrue(
            reason.contains(TodayReasonPresentation.headline(for: item.reason))
        )
    }
}
