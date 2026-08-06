import XCTest

final class IPadLayoutTests: XCTestCase {
    func testFeedbackShowsTableAndAnalysisColumnsTogether() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-training-events"]
        app.launch()

        app.buttons["开始今日训练"].tap()
        app.buttons["decision.action.bet-217"].tap()
        app.buttons["decision.confidence.verySure"].tap()
        app.buttons["decision.submit"].tap()

        XCTAssertTrue(
            app.otherElements["feedback.table-column"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.otherElements["feedback.analysis-column"].exists
        )
        XCTAssertTrue(app.staticTexts["开发演示数据"].exists)
    }
}
