import XCTest

/// Drives the M2B remediation surface in a real build.
///
/// The third slice adds one reachable thing: a covered deviation in an analyzed
/// hand offers "练这个漏洞", and tapping it opens the ordinary training flow on
/// the covering scenario. The bridge and the field it reads are unit-tested;
/// only a UI test tells "remediation exists" from "a user can start it". This
/// adopts appendix G — the hero opens 32o from the button, a full-magnitude
/// deviation the shipped `rfi-btn` range covers — reaches its analysis, taps the
/// remediation entry, and drives the drill to feedback.
final class M2BRemediationSurfaceTests: XCTestCase {
    func testStartingRemediationFromADeviationReachesTrainingAndRecordsAnAnswer() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-training-events", "--reset-hand-library"]
        app.launch()

        openHandLab(app)

        // Load the deviation sample (appendix G, hero opens 32o from the button)
        // and parse it.
        let loadDeviation = app.buttons["handlab.loadDeviationSample"]
        XCTAssertTrue(loadDeviation.waitForExistence(timeout: 10), "没有载入偏离示例入口")
        loadDeviation.tap()

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

        // The deviation row offers a remediation entry.
        let remediate = app.buttons["handlab.analysis.row.0.remediate"]
        XCTAssertTrue(remediate.waitForExistence(timeout: 10), "偏离行没有练这个漏洞入口")
        remediate.tap()

        // The ordinary training screen: an action, a confidence, one submit.
        XCTAssertTrue(
            app.buttons["decision.submit"].waitForExistence(timeout: 10),
            "点练这个漏洞后没有进入训练界面"
        )
        let action = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "decision.action.")
        ).element(boundBy: 0)
        XCTAssertTrue(action.exists, "训练界面没有给出行动选项")
        action.tap()
        app.buttons["decision.confidence.verySure"].tap()
        app.buttons["decision.submit"].tap()

        // Submitting records the answer and shows feedback.
        XCTAssertTrue(
            app.staticTexts["回答已保存"].waitForExistence(timeout: 10),
            "补救提交后没有落库并给出反馈"
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
