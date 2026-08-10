import StrategyContent
import TrainingDomain
import XCTest
@testable import PokerCoach

@MainActor
final class TodayDiagnosticTests: XCTestCase {
    // GIVEN 用户尚无训练历史
    // THEN 诊断入口出现，进度为 0/12
    func testOffersTheDiagnosticToANewUser() async throws {
        let viewModel = makeViewModel(events: [])

        await viewModel.refresh()

        XCTAssertTrue(viewModel.showsDiagnosticEntry)
        XCTAssertTrue(viewModel.showsDiagnosticPrompt)
        XCTAssertEqual(viewModel.diagnosticProgressText, "0/12")
    }

    // GIVEN 用户完成了前 5 题后退出
    // THEN 进度显示 5/12，入口仍在
    func testResumesTheDiagnosticFromTheEventHistory() async throws {
        let session = DiagnosticSession(
            blueprint: .cash6MaxDefault,
            pack: DiagnosticContentFixture.pack
        )
        let answered = session.questions.prefix(5).map(\.scenarioID)
        let viewModel = makeViewModel(
            events: answered.map { DiagnosticContentFixture.event(scenarioID: $0) }
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.diagnosticProgressText, "5/12")
        XCTAssertTrue(viewModel.showsDiagnosticEntry)
    }

    // GIVEN 用户跳过诊断
    // THEN 提示消失但入口保留，今日计划仍然可用
    func testKeepsTheEntryAndThePlanAfterSkipping() async throws {
        let viewModel = makeViewModel(events: [])
        await viewModel.refresh()

        viewModel.skipDiagnostic()

        XCTAssertFalse(viewModel.showsDiagnosticPrompt)
        XCTAssertTrue(viewModel.showsDiagnosticEntry, "跳过不应该把入口一起藏掉")
        XCTAssertNotNil(viewModel.primaryItem)
    }

    // GIVEN 诊断已全部作答
    // THEN 入口不再出现
    func testHidesTheEntryOnceTheDiagnosticIsComplete() async throws {
        let session = DiagnosticSession(
            blueprint: .cash6MaxDefault,
            pack: DiagnosticContentFixture.pack
        )
        let viewModel = makeViewModel(
            events: session.questions.map {
                DiagnosticContentFixture.event(scenarioID: $0.scenarioID)
            }
        )

        await viewModel.refresh()

        XCTAssertFalse(viewModel.showsDiagnosticEntry)
        XCTAssertNil(viewModel.diagnosticProgressText)
    }

    // 计划项的入选原因来自 planner 的枚举，而不是界面重新推算一遍。
    func testShowsThePlannersOwnReason() async throws {
        let viewModel = makeViewModel(events: [])

        await viewModel.refresh()

        let reason = try XCTUnwrap(viewModel.primaryReasonText)
        let expected = TodayReasonPresentation.headline(
            for: try XCTUnwrap(viewModel.primaryItem).reason
        )
        XCTAssertTrue(reason.contains(expected), "界面文案与 planner 的判定不一致：\(reason)")
    }

    // Without content there is no curriculum to diagnose against, but Today
    // must still load rather than fail.
    func testWorksWithNoContentInstalled() async throws {
        let viewModel = TodayViewModel(
            eventStore: InMemoryTrainingEventStore(events: []),
            reducer: PlayerModelReducer(),
            planner: TrainingPlanner(),
            catalog: DiagnosticContentFixture.catalog,
            strategyContentAvailability: .reviewedContentUnavailable,
            strategyProvider: nil,
            now: { DiagnosticContentFixture.now }
        )

        await viewModel.refresh()

        XCTAssertFalse(viewModel.showsDiagnosticEntry)
        XCTAssertNotNil(viewModel.primaryItem)
    }

    private func makeViewModel(events: [TrainingEvent]) -> TodayViewModel {
        TodayViewModel(
            eventStore: InMemoryTrainingEventStore(events: events),
            reducer: PlayerModelReducer(),
            planner: TrainingPlanner(),
            catalog: DiagnosticContentFixture.catalog,
            strategyContentAvailability: .unverifiedContentAvailable,
            strategyProvider: InMemoryStrategyPackProvider(
                pack: DiagnosticContentFixture.pack
            ),
            now: { DiagnosticContentFixture.now }
        )
    }
}

@MainActor
final class TodayRepetitionTests: XCTestCase {
    // The reason this test exists: the app fed curriculum node IDs into a
    // parameter the planner compared against ability dimensions. Both fixtures
    // set the two fields to the same string, so every domain test passed while
    // the due-repetition bonus never fired in any build.
    //
    // The pack below keeps the namespaces distinct, as shipped content does.
    func testDueRepetitionReachesThePlanFromTheApp() async throws {
        let pack = RepetitionAppFixture.pack
        let events = [
            RepetitionAppFixture.event(
                scenarioID: "s-turn-1",
                quality: .blunder,
                daysAfterEpoch: 0
            ),
        ]
        let viewModel = TodayViewModel(
            eventStore: InMemoryTrainingEventStore(events: events),
            reducer: PlayerModelReducer(),
            planner: TrainingPlanner(),
            catalog: RepetitionAppFixture.catalog,
            strategyContentAvailability: .reviewedContentAvailable,
            strategyProvider: InMemoryStrategyPackProvider(pack: pack),
            now: { RepetitionAppFixture.epoch.addingTimeInterval(5 * 86_400) }
        )

        await viewModel.refresh()

        let item = try XCTUnwrap(
            viewModel.primaryItem,
            "计划为空，无法判断复练是否进入排序"
        )
        let other = try XCTUnwrap(viewModel.supportingItems.first)

        // The two catalog entries share an ability dimension and differ only by
        // node, and "flop-item" sorts before "turn-item", so a tie would put
        // flop first. Turn winning means the due bonus actually reached the
        // ranking rather than the two namespaces silently missing each other.
        XCTAssertEqual(
            item.curriculumNodeIDForTesting,
            "turn-barrel",
            "到期复练没有进入排序：很可能又把节点 ID 与能力维度混为一谈了"
        )
        XCTAssertGreaterThan(item.priority, other.priority)
    }
}

extension DailyPlanItem {
    var curriculumNodeIDForTesting: String { catalogItem.curriculumNodeID }
}
