import XCTest

/// Drives the river trainer in a real (debug) build.
///
/// The trainer runs on `reviewed` content, so this proves it is reachable from
/// within 复盘 and that the answering screen shows no unverified disclosure. It
/// then answers one hand (Check, always available) and confirms feedback renders.
final class RiverTrainerSurfaceTests: XCTestCase {
    func testTrainerReachableFromReviewAndReviewedContentHasNoUnverifiedBanner() {
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

        let entry = app.buttons["review.riverTrainer"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "复盘里找不到河牌决策训练入口")
        entry.tap()

        XCTAssertTrue(app.staticTexts["river.trainer.prompt"].waitForExistence(timeout: 10), "没有出题")
        XCTAssertFalse(
            app.staticTexts["river.trainer.disclosure"].exists,
            "已审核内容不应显示未经审核披露"
        )

        // Answer one hand: check + a confidence, then submit, and see feedback.
        XCTAssertTrue(app.buttons["river.trainer.action.check"].waitForExistence(timeout: 10), "没有过牌按钮")
        app.buttons["river.trainer.action.check"].tap()
        app.buttons["river.trainer.confidence.unsure"].tap()
        app.buttons["river.trainer.submit"].tap()

        XCTAssertTrue(
            app.staticTexts["river.trainer.feedback"].waitForExistence(timeout: 10),
            "提交后没有显示反馈"
        )
    }
}
