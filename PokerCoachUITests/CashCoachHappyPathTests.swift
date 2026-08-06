import XCTest

final class CashCoachHappyPathTests: XCTestCase {
    func testDecisionCreatesProfessionalFeedbackAndReviewHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-training-events"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["开发演示数据"].waitForExistence(timeout: 2)
        )
        app.buttons["开始今日训练"].tap()
        app.buttons["decision.action.bet-217"].tap()
        app.buttons["decision.confidence.verySure"].tap()
        app.buttons["decision.submit"].tap()

        XCTAssertTrue(
            app.staticTexts["开发演示数据"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.staticTexts["EV 损失"].exists)
        XCTAssertTrue(app.staticTexts["行动频率"].exists)

        app.buttons["继续"].tap()
        app.tabBars.buttons["复盘"].tap()
        XCTAssertTrue(
            app.staticTexts["开发演示数据"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.staticTexts["下注尺度"].waitForExistence(timeout: 2)
        )
    }
}
