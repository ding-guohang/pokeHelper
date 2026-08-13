import XCTest

/// Drives the tournament push/fold trainer in a real (debug) build.
///
/// The trainer runs on unverified content, so this proves two things at once:
/// it is reachable from within 复盘, and it discloses "未经策略审核" on the
/// answering screen. It then answers one hand and confirms feedback renders.
final class TournamentPushFoldSurfaceTests: XCTestCase {
    func testTrainerReachableFromReviewAndDisclosesUnverified() {
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

        let entry = app.buttons["review.tournamentPushFold"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "复盘里找不到单挑 Push/Fold 训练入口")
        entry.tap()

        // Unverified disclosure must be visible while answering.
        XCTAssertTrue(
            app.staticTexts["tourn.trainer.disclosure"].waitForExistence(timeout: 10),
            "作答界面没有披露未经审核"
        )
        XCTAssertTrue(app.staticTexts["tourn.trainer.prompt"].waitForExistence(timeout: 10), "没有出题")

        // Answer one hand: fold + a confidence, then submit, and see feedback.
        XCTAssertTrue(app.buttons["tourn.trainer.action.fold"].waitForExistence(timeout: 10), "没有弃牌按钮")
        app.buttons["tourn.trainer.action.fold"].tap()
        app.buttons["tourn.trainer.confidence.unsure"].tap()
        app.buttons["tourn.trainer.submit"].tap()

        XCTAssertTrue(
            app.staticTexts["tourn.trainer.feedback"].waitForExistence(timeout: 10),
            "提交后没有显示反馈"
        )
    }
}
