import XCTest

/// Drives the M2B analysis surface in a real build.
///
/// The second slice ships a signature exporter, a content matcher, a key-node
/// selection and an analysis coordinator — all tested, none of them on a screen
/// until here. This test is the difference between "the analysis exists" and
/// "a user can reach it": it adopts a hand with a genuine deviation and reads
/// the flagged key node and its content comparison off the screen.
///
/// The deviation hand is loaded through the development-only "载入偏离示例"
/// button, which fills the editor with appendix G — appendix A with the hero
/// holding `3s 2d`. `32o` has no cell in the shipped `rfi-btn` range, so the
/// button-open is weight 0, a full-magnitude deviation, exactly as the
/// `ImportedHandKeyNodeTests` unit test pins.
final class M2BAnalysisSurfaceTests: XCTestCase {
    func testAnalyzingAHandShowsAFlaggedDeviationWithTheContentComparison() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-training-events", "--reset-hand-library"]
        app.launch()

        openHandLab(app)

        // Load the deviation sample (appendix G, hero opens 32o from the button)
        // and parse it.
        let loadDeviation = app.buttons["handlab.loadDeviationSample"]
        XCTAssertTrue(loadDeviation.waitForExistence(timeout: 10), "没有载入偏离示例入口")
        loadDeviation.tap()

        // The preview confirms the hand parsed — hero on the button.
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

        // Open analysis for the stored hand.
        let analyze = app.buttons["handlab.analyze.0"]
        XCTAssertTrue(analyze.waitForExistence(timeout: 10), "牌库项没有分析入口")
        analyze.tap()

        // The 32o button-open is surfaced as a deviation…
        let reason = app.staticTexts["handlab.analysis.row.0.reason"]
        XCTAssertTrue(reason.waitForExistence(timeout: 10), "分析里没有关键节点")
        XCTAssertEqual(reason.label, "偏离", "32o 开池应被标为偏离")

        // …with the content comparison shown: the range plays this line 0% of
        // the time, a full 100% departure.
        let comparison = app.staticTexts["handlab.analysis.row.0.comparison"]
        XCTAssertTrue(comparison.waitForExistence(timeout: 10), "分析没有展示内容对照")
        XCTAssertEqual(comparison.label, "内容频率 0% · 偏离 100%")
    }

    /// Hand Lab is reached from within 复盘 (Review), not a primary tab: open the
    /// Review destination — a tab on iPhone, a sidebar row on iPad — then tap the
    /// Hand Lab entry inside it.
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

    /// Polls until an element's label matches, since the label changes after an
    /// async write rather than the element appearing.
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
