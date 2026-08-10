import StrategyContent
import TrainingDomain
import XCTest
@testable import PokerCoach

@MainActor
final class LearnViewModelTests: XCTestCase {
    // GIVEN 包中映射到 turn-barrel 的场景有 7 个，river-bluff-catch 前置为 turn-barrel
    // THEN 两个节点的场景数与前置关系都正确
    func testPresentsNodesWithCountsAndPrerequisites() throws {
        let viewModel = LearnViewModel(
            pack: LearnFixture.pack(turnBarrelScenarioCount: 7),
            events: [],
            strategyContentAvailability: .unverifiedContentAvailable
        )
        viewModel.refresh()

        let turnBarrel = try XCTUnwrap(viewModel.nodes.first { $0.id == "turn-barrel" })
        XCTAssertEqual(turnBarrel.practisableScenarioCount, 7)

        let river = try XCTUnwrap(viewModel.nodes.first { $0.id == "river-bluff-catch" })
        XCTAssertEqual(river.prerequisiteTitles, ["转牌第二枪"])
    }

    // GIVEN river-bluff-catch 在当前包中无场景
    // THEN 标记暂无内容、不进计划、不计入进度分母
    func testMarksEmptyNodesAndExcludesThemFromProgress() throws {
        let viewModel = LearnViewModel(
            pack: LearnFixture.pack(riverScenarioCount: 0),
            events: [],
            strategyContentAvailability: .unverifiedContentAvailable
        )
        viewModel.refresh()

        let river = try XCTUnwrap(viewModel.nodes.first { $0.id == "river-bluff-catch" })
        XCTAssertTrue(river.isContentUnavailable)
        XCTAssertEqual(viewModel.masteryProgressDenominator, viewModel.nodes.count - 1)
        XCTAssertFalse(viewModel.plannableNodeIDs.contains("river-bluff-catch"))
    }

    // GIVEN 某节点未掌握
    // THEN 五项信号逐行可读，不是一个笼统结论
    func testListsEveryMasterySignalRatherThanAVerdict() throws {
        let viewModel = LearnViewModel(
            pack: LearnFixture.pack(),
            events: LearnFixture.earlyProgressEvents(),
            strategyContentAvailability: .unverifiedContentAvailable
        )
        viewModel.refresh()

        let detail = try XCTUnwrap(viewModel.detail(forNode: "turn-barrel"))
        XCTAssertEqual(detail.signalRows.count, 5)
        XCTAssertEqual(detail.signalRows.map(\.label), [
            "样本", "近期稳定性", "信心校准", "复练", "迁移",
        ])
        XCTAssertEqual(detail.signalRows[0].value, "4/20")
        XCTAssertFalse(detail.signalRows[0].satisfied)
    }

    // A node with no very-sure answers reads better as a phrase than as "0/0",
    // which looks like a failure.
    func testDescribesCalibrationWithoutVerySureAnswersInWords() throws {
        let viewModel = LearnViewModel(
            pack: LearnFixture.pack(),
            events: LearnFixture.earlyProgressEvents(),
            strategyContentAvailability: .unverifiedContentAvailable
        )
        viewModel.refresh()

        let detail = try XCTUnwrap(viewModel.detail(forNode: "turn-barrel"))
        XCTAssertEqual(detail.signalRows[2].value, "无高信心作答")
        XCTAssertTrue(detail.signalRows[2].satisfied)
    }

    func testReportsNoDetailForAnUnknownNode() throws {
        let viewModel = LearnViewModel(
            pack: LearnFixture.pack(),
            events: [],
            strategyContentAvailability: .unverifiedContentAvailable
        )
        viewModel.refresh()

        XCTAssertNil(viewModel.detail(forNode: "not-a-node"))
    }
}
