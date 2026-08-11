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
        let pack = LearnFixture.pack(riverScenarioCount: 0)
        let viewModel = LearnViewModel(
            pack: pack,
            events: [],
            strategyContentAvailability: .unverifiedContentAvailable
        )
        viewModel.refresh()

        let river = try XCTUnwrap(viewModel.nodes.first { $0.id == "river-bluff-catch" })
        XCTAssertTrue(river.isContentUnavailable)

        // "Not plannable" asserted against the thing that actually builds the
        // plan. This used to check `LearnViewModel.plannableNodeIDs`, a
        // property no plan ever read: the daily plan is built by
        // TrainingPlanner from the runtime catalog, so the assertion described
        // an exclusion that was never enforced anywhere. The real mechanism is
        // that a node with no scenarios contributes no catalog items.
        XCTAssertTrue(
            RuntimeTrainingCatalog.items(from: pack)
                .allSatisfy { $0.curriculumNodeID != "river-bluff-catch" },
            "无场景的节点仍出现在训练目录里，今日计划可以选中它"
        )

        // The denominator counts nodes that could actually be mastered. That
        // excludes the empty node and also flop-cbet, which has two scenarios
        // against a transfer requirement of three: mastery demonstrated over
        // fewer scenarios than that is memorising hands, not learning the spot.
        let turnBarrel = try XCTUnwrap(viewModel.nodes.first { $0.id == "turn-barrel" })
        XCTAssertFalse(turnBarrel.hasInsufficientContentForMastery)
        let flopCbet = try XCTUnwrap(viewModel.nodes.first { $0.id == "flop-cbet" })
        XCTAssertEqual(flopCbet.practisableScenarioCount, 2)
        XCTAssertTrue(flopCbet.hasInsufficientContentForMastery)
        XCTAssertEqual(viewModel.masteryProgressDenominator, 1)
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
