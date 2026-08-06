import XCTest
import TrainingDomain
@testable import PokerCoach

@MainActor
final class ReviewViewModelTests: XCTestCase {
    func testDevelopmentEventDisclosesFixtureInsteadOfPackID() async throws {
        let event = DashboardFixture.developmentBetSizingEvent()
        let viewModel = ReviewViewModel(
            eventStore: InMemoryTrainingEventStore(events: [event]),
            reducer: PlayerModelReducer()
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
