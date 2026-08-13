import XCTest

/// Drives the M2B manual scenario builder in a real build.
///
/// The fourth slice adds one reachable thing: a builder under Hand Lab where a
/// user assembles a preflop spot by hand and sees whether installed content
/// covers it. The view model, the matcher core and the constructed-spot store are
/// unit-tested; only a UI test tells "the builder exists" from "a user can reach
/// it". This opens the builder and builds its default spot — a 100BB BTN open
/// with AA, which the shipped `rfi-btn` range raises 100% of the time — and reads
/// the content comparison off the screen.
final class M2BScenarioBuilderSurfaceTests: XCTestCase {
    func testBuildingACoveredBTNSpotShowsTheContentComparison() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-training-events", "--reset-hand-library"]
        app.launch()

        openHandLab(app)

        let entry = app.buttons["handlab.scenarioBuilder"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "Hand Lab 里找不到构造场景入口")
        entry.tap()

        let build = app.buttons["scenarioBuilder.build"]
        XCTAssertTrue(build.waitForExistence(timeout: 10), "构造界面没有构造按钮")
        build.tap()

        // The default inputs describe a BTN open the reviewed pack covers, so the
        // comparison is shown: `rfi-btn` raises AA 100% of the time.
        let comparison = app.staticTexts["scenarioBuilder.comparison"]
        XCTAssertTrue(comparison.waitForExistence(timeout: 10), "构造界面没有展示内容对照")
        XCTAssertEqual(comparison.label, "内容频率 100%")

        // A covered spot offers the same remediation entry an imported deviation
        // does.
        XCTAssertTrue(
            app.buttons["scenarioBuilder.remediate"].waitForExistence(timeout: 10),
            "命中的构造 spot 应给出练这个漏洞入口"
        )
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
}
