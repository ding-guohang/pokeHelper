import XCTest

/// Drives the tournament ICM calculator in a real build.
///
/// The calculator is pure content-free math (ICM equity, bubble factor) with no
/// screen until here. This test is the difference between "the engine exists"
/// and "a user can reach it": it opens the tool from within 复盘, enters stacks,
/// a payout structure and two seats, and reads the equities and bubble factor
/// off the screen — then confirms malformed input surfaces an error, not a
/// number.
final class TournamentICMSurfaceTests: XCTestCase {
    func testCalculatorShowsEquitiesBubbleFactorAndInputErrors() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-training-events"]
        app.launch()

        openCalculator(app)

        let stacks = app.textFields["icm.stacks"]
        XCTAssertTrue(stacks.waitForExistence(timeout: 10), "找不到筹码输入框")
        stacks.tap()
        stacks.typeText("1000,1000,1000")

        app.textFields["icm.payouts"].tap()
        app.textFields["icm.payouts"].typeText("5000,3000,2000")

        // Naming the hero seat asks for the bubble factor against each other
        // seat. With equal stacks and this ladder the ratio is 4/3 for both.
        app.textFields["icm.hero"].tap()
        app.textFields["icm.hero"].typeText("0")

        app.buttons["icm.compute"].tap()

        // Each of three equal stacks owns 10000/3 → 3333.33 (exact rational,
        // rendered by integer long division, not a float).
        let equity0 = app.staticTexts["icm.equity.0"]
        XCTAssertTrue(equity0.waitForExistence(timeout: 10), "没有显示座位 0 的权益")
        XCTAssertEqual(equity0.label, "座位 0：3333.33")
        XCTAssertTrue(app.staticTexts["icm.equity.2"].exists, "没有显示全部三家权益")

        // Bubble factor of hero (seat 0) vs each opponent: 4/3 → 1.33.
        let bubbleFactorVs1 = app.staticTexts["icm.bubbleFactor.1"]
        XCTAssertTrue(bubbleFactorVs1.waitForExistence(timeout: 10), "没有显示对座位 1 的泡沫系数")
        XCTAssertTrue(bubbleFactorVs1.label.contains("1.33"), "对座位 1 的泡沫系数不是 1.33：\(bubbleFactorVs1.label)")
        XCTAssertTrue(app.staticTexts["icm.bubbleFactor.2"].exists, "没有显示对座位 2 的泡沫系数")

        // Malformed stacks surface an error, not a number.
        clear(stacks)
        stacks.typeText("1000,abc")
        app.buttons["icm.compute"].tap()
        XCTAssertTrue(app.staticTexts["icm.error"].waitForExistence(timeout: 10), "非法输入没有报错")
    }

    /// The calculator is reached from within 复盘 (Review), not a primary tab.
    private func openCalculator(_ app: XCUIApplication) {
        let review = "复盘"
        if app.tabBars.buttons[review].waitForExistence(timeout: 10) {
            app.tabBars.buttons[review].tap()
        } else {
            let row = app.cells.staticTexts[review]
            XCTAssertTrue(row.waitForExistence(timeout: 10), "侧栏里找不到复盘")
            row.tap()
        }
        let entry = app.buttons["review.tournamentICM"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "复盘里找不到锦标赛 ICM 计算器入口")
        entry.tap()
    }

    /// Clears a text field by deleting its current value one character at a time.
    private func clear(_ field: XCUIElement) {
        field.tap()
        guard let value = field.value as? String, !value.isEmpty else { return }
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
    }
}
