import StrategyContent
import XCTest
import TrainingDomain
@testable import PokerCoach

@MainActor
final class ReviewViewModelTests: XCTestCase {
    func testUnavailableContentKeepsHistoryButBlocksSuggestedRoute()
        async
    {
        let event = DashboardFixture.developmentBetSizingEvent()
        let viewModel = ReviewViewModel(
            eventStore: InMemoryTrainingEventStore(events: [event]),
            reducer: PlayerModelReducer(),
            catalog: DashboardFixture.catalog,
            strategyContentAvailability: .reviewedContentUnavailable
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.history.count, 1)
        XCTAssertEqual(
            viewModel.suggestedTraining?.catalogItem.scenarioID,
            "cash-bet-sizing"
        )
        XCTAssertFalse(viewModel.canStartTraining)
        XCTAssertNil(viewModel.startSuggestedTraining())
        XCTAssertEqual(
            viewModel.trainingUnavailableExplanation,
            "未安装已审核策略内容，当前仅可查看复盘。"
        )
    }

    func testAvailableContentAllowsSuggestedRoute() async {
        let event = DashboardFixture.developmentBetSizingEvent()

        for availability in [
            StrategyContentAvailability.developmentFixtureAvailable,
            .reviewedContentAvailable,
        ] {
            let viewModel = ReviewViewModel(
                eventStore: InMemoryTrainingEventStore(events: [event]),
                reducer: PlayerModelReducer(),
                catalog: DashboardFixture.catalog,
                strategyContentAvailability: availability
            )

            await viewModel.refresh()

            XCTAssertTrue(viewModel.canStartTraining)
            XCTAssertNil(viewModel.trainingUnavailableExplanation)
            XCTAssertEqual(
                viewModel.startSuggestedTraining(),
                "cash-bet-sizing"
            )
        }
    }

    func testDevelopmentEventDisclosesFixtureInsteadOfPackID() async throws {
        let event = DashboardFixture.developmentBetSizingEvent()
        let viewModel = ReviewViewModel(
            eventStore: InMemoryTrainingEventStore(events: [event]),
            reducer: PlayerModelReducer(),
            installedContent: [event.strategyPackID: .testFixture]
        )

        await viewModel.refresh()

        let historyEvent = try XCTUnwrap(viewModel.history.first)
        XCTAssertEqual(
            viewModel.contentDisclosure(for: historyEvent),
            "开发演示数据"
        )
        XCTAssertNotEqual(
            viewModel.contentDisclosure(for: historyEvent),
            historyEvent.strategyPackID
        )
    }

    func testUnverifiedHistoryIsDisclosedAsUnreviewed() async throws {
        let event = DashboardFixture.developmentBetSizingEvent()
        let viewModel = ReviewViewModel(
            eventStore: InMemoryTrainingEventStore(events: [event]),
            reducer: PlayerModelReducer(),
            installedContent: [event.strategyPackID: .unverifiedDraft]
        )

        await viewModel.refresh()

        let historyEvent = try XCTUnwrap(viewModel.history.first)
        XCTAssertEqual(
            viewModel.contentDisclosure(for: historyEvent),
            "未经策略审核"
        )
    }

    func testReviewedHistoryCarriesNoDisclosure() async throws {
        let event = DashboardFixture.developmentBetSizingEvent()
        let viewModel = ReviewViewModel(
            eventStore: InMemoryTrainingEventStore(events: [event]),
            reducer: PlayerModelReducer(),
            installedContent: [event.strategyPackID: .reviewed]
        )

        await viewModel.refresh()

        let historyEvent = try XCTUnwrap(viewModel.history.first)
        XCTAssertNil(viewModel.contentDisclosure(for: historyEvent))
    }

    // A history entry whose pack is no longer installed must not render bare.
    // Silence there reads as "nothing to disclose", which is the opposite of
    // what an unresolvable provenance means.
    func testHistoryFromAnUninstalledPackDisclosesUnknownProvenance() async throws {
        let event = DashboardFixture.developmentBetSizingEvent()
        let viewModel = ReviewViewModel(
            eventStore: InMemoryTrainingEventStore(events: [event]),
            reducer: PlayerModelReducer(),
            installedContent: [:]
        )

        await viewModel.refresh()

        let historyEvent = try XCTUnwrap(viewModel.history.first)
        XCTAssertEqual(
            viewModel.contentDisclosure(for: historyEvent),
            "内容来源未知"
        )
    }

    func testReviewSortsWeakestAbilityFirst() async throws {
        let fixture = DashboardFixture.withTwoDimensions()

        await fixture.review.refresh()

        XCTAssertEqual(
            fixture.review.abilities.map(\.dimension),
            ["bet-sizing", "preflop-range"]
        )
    }

    func testRefreshRereadsAppendedEventsIncludingRawEVAndContentVersion() async throws {
        let fixture = DashboardFixture.empty()
        await fixture.review.refresh()
        XCTAssertEqual(fixture.review.state, .empty)

        await fixture.store.append(
            DashboardFixture.weakPreflopEvent(
                contentVersion: "2026.08.07"
            )
        )
        await fixture.review.refresh()

        let event = try XCTUnwrap(fixture.review.history.first)
        XCTAssertEqual(fixture.review.state, .loaded)
        XCTAssertEqual(fixture.review.abilities.map(\.dimension), ["preflop-range"])
        XCTAssertEqual(event.grade.evLoss.milliBB, 500)
        XCTAssertEqual(event.grade.lossRateBasisPoints, 500)
        XCTAssertEqual(event.strategyContentVersion, "2026.08.07")
    }

    func testReviewModelsLoadingAndRecoverableFailure() async {
        let empty = ReviewViewModel(
            eventStore: InMemoryTrainingEventStore(),
            reducer: PlayerModelReducer()
        )
        XCTAssertEqual(empty.state, .loading)
        await empty.refresh()
        XCTAssertEqual(empty.state, .empty)

        let failing = ReviewViewModel(
            eventStore: FailingDashboardEventStore(),
            reducer: PlayerModelReducer()
        )
        await failing.refresh()
        XCTAssertEqual(
            failing.state,
            .failed(message: "读取复盘记录失败，请重试")
        )
    }

    func testAbilityDimensionsUseDeterministicChineseNames() {
        XCTAssertEqual(AbilityDimensionPresentation.displayName(for: "bet-sizing"), "下注尺度")
        XCTAssertEqual(AbilityDimensionPresentation.displayName(for: "preflop-range"), "翻前范围")
        XCTAssertEqual(
            AbilityDimensionPresentation.displayName(for: "unknown-dimension"),
            "其他能力（unknown-dimension）"
        )
    }
}
