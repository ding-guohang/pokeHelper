import XCTest

/// Drives the tournament push/fold trainer in a real (debug) build.
///
/// The trainer runs on `reviewed` content, so this proves it is reachable from
/// within 复盘 and that the answering screen shows no unverified disclosure (a
/// reviewed pack must not carry the "未经策略审核" banner). It then answers one
/// hand and confirms feedback renders.
final class TournamentPushFoldSurfaceTests: XCTestCase {
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

        let entry = app.buttons["review.tournamentPushFold"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "复盘里找不到单挑 Push/Fold 训练入口")
        entry.tap()

        // The answering screen loads (prompt visible), and because the content is
        // reviewed there must be no unverified disclosure banner.
        XCTAssertTrue(app.staticTexts["tourn.trainer.prompt"].waitForExistence(timeout: 10), "没有出题")
        XCTAssertFalse(
            app.staticTexts["tourn.trainer.disclosure"].exists,
            "已审核内容不应显示未经审核披露"
        )

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
