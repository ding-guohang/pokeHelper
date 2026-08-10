import XCTest

/// Drives the surfaces M1C added.
///
/// These exist because a whole capability shipped computed and unrendered: the
/// diagnostic had a view model, six passing unit tests, and no view reading any
/// of it. Nothing but a UI test can tell those two states apart.
final class M1CSurfaceTests: XCTestCase {
    func testDiagnosticEntryIsOfferedOnToday() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-training-events"]
        app.launch()

        XCTAssertTrue(
            app.buttons["today.diagnostic.start"].waitForExistence(timeout: 5),
            "今日页没有诊断入口"
        )
        XCTAssertTrue(
            app.staticTexts["today.diagnostic.progress"].exists,
            "诊断入口没有显示进度"
        )
    }

    // Skipping must hide the prompt and keep the entry: the promise is
    // "open it and train", not "be diagnosed or nothing".
    func testSkippingTheDiagnosticKeepsItsEntryAndThePlan() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-training-events"]
        app.launch()

        XCTAssertTrue(
            app.buttons["today.diagnostic.skip"].waitForExistence(timeout: 5)
        )
        app.buttons["today.diagnostic.skip"].tap()

        XCTAssertFalse(app.buttons["today.diagnostic.skip"].exists)
        XCTAssertTrue(
            app.buttons["today.diagnostic.start"].exists,
            "跳过把入口也一起藏掉了"
        )
        XCTAssertTrue(app.buttons["开始今日训练"].exists)
    }

    func testCurriculumTreeRendersNodesAndMasterySignals() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-training-events"]
        app.launch()

        navigateToLearn(app)

        // Tapping a node has to reveal the five mastery signals, not a verdict.
        let firstNode = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "learn.node."))
            .element(boundBy: 0)
        XCTAssertTrue(firstNode.waitForExistence(timeout: 5), "能力树里没有节点")
        firstNode.tap()

        let signal = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "learn.signal."))
            .element(boundBy: 0)
        XCTAssertTrue(
            signal.waitForExistence(timeout: 3),
            "展开节点后没有列出掌握信号"
        )
    }

    /// Learn sits behind a tab on iPhone and a sidebar row on iPad, so the
    /// route differs by layout. Probing both keeps this test from encoding one.
    private func navigateToLearn(_ app: XCUIApplication) {
        if app.tabBars.buttons["学习"].exists {
            app.tabBars.buttons["学习"].tap()
            return
        }
        let sidebarRow = app.cells.staticTexts["学习"]
        if sidebarRow.waitForExistence(timeout: 2) {
            sidebarRow.tap()
        }
    }
}
