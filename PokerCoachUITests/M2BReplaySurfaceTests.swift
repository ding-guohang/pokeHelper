import XCTest

/// Drives the M2B replay surface in a real build.
///
/// The fifth slice ships a street-by-street replay and per-hero-node
/// counterfactuals — pure mappings, tested, none of them on a screen until here.
/// This test is the difference between "the replay exists" and "a user can reach
/// it": it adopts appendix A, opens 回放 alongside 分析, and reads a street's
/// board and a hero node's content counterfactual off the screen.
final class M2BReplaySurfaceTests: XCTestCase {
    func testReplayingAHandShowsStreetsAndANodeCounterfactual() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-training-events", "--reset-hand-library"]
        app.launch()

        openHandLab(app)

        // Load appendix A (a clean four-street hand) via the development sample
        // button and parse it.
        let loadSample = app.buttons["handlab.loadSample"]
        XCTAssertTrue(loadSample.waitForExistence(timeout: 10), "没有载入示例入口")
        loadSample.tap()

        let heroPosition = app.staticTexts["handlab.preview.heroPosition"]
        XCTAssertTrue(heroPosition.waitForExistence(timeout: 10), "预览没有出现")
        XCTAssertEqual(heroPosition.label, "英雄位置 BTN")

        // Adopt it into the library.
        let accept = app.buttons["handlab.accept"]
        XCTAssertTrue(accept.exists, "没有采纳入口")
        accept.tap()

        XCTAssertTrue(
            waitForLabel(app.staticTexts["handlab.library.count"], "共 1 手", timeout: 10),
            "采纳后牌库计数没有变为 1"
        )

        // Open the replay for the stored hand.
        let replay = app.buttons["handlab.replay.0"]
        XCTAssertTrue(replay.waitForExistence(timeout: 10), "牌库项没有回放入口")
        replay.tap()

        // The flop board is replayed with its own three cards.
        let flopBoard = app.staticTexts["handlab.replay.flop.board"]
        XCTAssertTrue(flopBoard.waitForExistence(timeout: 10), "回放没有翻牌一街")
        XCTAssertEqual(flopBoard.label, "翻牌 Ac 7h 2s")

        // And the hero's first decision carries a content counterfactual.
        let counterfactual = app.staticTexts["handlab.replay.node.0.counterfactual"]
        XCTAssertTrue(counterfactual.waitForExistence(timeout: 10), "回放没有展示节点反事实")
    }

    /// Hand Lab is reached from within 复盘 (Review), not a primary tab.
    private func openHandLab(_ app: XCUIApplication) {
        let review = "复盘"
        if app.tabBars.buttons[review].waitForExistence(timeout: 10) {
            app.tabBars.buttons[review].tap()
        } else {
            let row = app.cells.staticTexts[review]
            XCTAssertTrue(row.waitForExistence(timeout: 10), "侧栏里找不到复盘")
            row.tap()
        }

        let entry = app.buttons["review.handLab"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "复盘里找不到牌局实验室入口")
        entry.tap()
    }

    private func waitForLabel(
        _ element: XCUIElement,
        _ expected: String,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
