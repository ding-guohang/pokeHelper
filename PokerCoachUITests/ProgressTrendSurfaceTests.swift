import XCTest

/// Drives the training progress trend in a real build.
///
/// The per-day aggregation is content-free and unit-tested; this proves the
/// difference between "the aggregation exists" and "a user can reach it": it
/// opens 训练进度 from within 复盘. With training events reset, it renders the
/// empty state.
final class ProgressTrendSurfaceTests: XCTestCase {
    func testProgressTrendReachableFromReviewAndShowsEmptyState() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-training-events"]
        app.launch()

        let review = "复盘"
        if app.tabBars.buttons[review].waitForExistence(timeout: 10) {
            app.tabBars.buttons[review].tap()
        } else {
            let row = app.cells.staticTexts[review]
            XCTAssertTrue(row.waitForExistence(timeout: 10), "侧栏里找不到复盘")
            row.tap()
        }

        let entry = app.buttons["review.progressTrend"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "复盘里找不到训练进度入口")
        entry.tap()

        // The empty-state title renders as a static text; assert it directly
        // rather than relying on the container's accessibility identifier.
        XCTAssertTrue(
            app.staticTexts["还没有训练记录"].waitForExistence(timeout: 10),
            "重置训练事件后应显示空态"
        )
    }
}
