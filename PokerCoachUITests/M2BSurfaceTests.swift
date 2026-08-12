import XCTest

/// Drives the M2B Hand Lab surface in a real build.
///
/// The slice ships a parser, a versioned library, a coordinator and a preview
/// mapping — all tested, none of them on a screen until here. A capability with
/// passing unit tests and no reachable view is exactly the state M1C and M2A
/// each produced once; only a UI test tells that state apart from a shipped one.
///
/// The sample hand is loaded through the development-only "载入示例" button,
/// which fills the editor with the appendix A text the parser tests pin — the
/// same fixture-injection discipline the M2A tests use for their fixed session
/// seed, so the screen is driven with input whose parsed values are known.
final class M2BSurfaceTests: XCTestCase {
    func testImportingAHandShowsTheStandardizedPreviewAndAdoptsItIntoTheLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-training-events", "--reset-hand-library"]
        app.launch()

        openHandLab(app)

        // Nothing adopted yet.
        XCTAssertTrue(
            app.staticTexts["handlab.library.count"].waitForExistence(timeout: 10),
            "牌库计数没有出现"
        )
        XCTAssertEqual(app.staticTexts["handlab.library.count"].label, "共 0 手")

        // Load the pinned sample and parse it.
        let loadSample = app.buttons["handlab.loadSample"]
        XCTAssertTrue(loadSample.waitForExistence(timeout: 10), "没有载入示例入口")
        loadSample.tap()

        // The standardized preview shows this hand's values.
        let heroPosition = app.staticTexts["handlab.preview.heroPosition"]
        XCTAssertTrue(heroPosition.waitForExistence(timeout: 10), "预览没有出现")
        XCTAssertEqual(heroPosition.label, "英雄位置 BTN")
        XCTAssertEqual(
            app.staticTexts["handlab.preview.flop.board"].label,
            "翻牌 Ac 7h 2s"
        )

        // Adopt it, and see it in the library.
        let accept = app.buttons["handlab.accept"]
        XCTAssertTrue(accept.exists, "没有采纳入口")
        accept.tap()

        XCTAssertTrue(
            waitForLabel(app.staticTexts["handlab.library.count"], "共 1 手", timeout: 10),
            "采纳后牌库计数没有变为 1"
        )
        XCTAssertTrue(
            app.staticTexts["handlab.library.row.0"].waitForExistence(timeout: 5),
            "采纳后牌库里看不到这一手"
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
