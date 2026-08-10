import XCTest

/// Signing in is optional. These tests prove the whole M1A experience stays
/// reachable with no account, and that the local-only storage promise is
/// visible from every destination rather than buried in a settings screen.
///
/// They run on both device families, which is not incidental: iPhone uses a tab
/// bar and iPad a split view, so a test written against one layout silently
/// asserts nothing about the other.
final class AnonymousAccountEntryTests: XCTestCase {
    private let localOnlyNotice = "仅保存在本机。"
    private let destinations = ["今日", "学习", "训练", "复盘"]

    func testAllFourDestinationsStayUsableAnonymouslyAndDiscloseLocalOnlyStorage() {
        let app = launch()

        XCTAssertTrue(
            app.staticTexts["开发演示数据"].waitForExistence(timeout: 5),
            "the app must open straight into training without an account"
        )

        for destination in destinations {
            select(destination, in: app)
            XCTAssertTrue(
                app.buttons["account.open"].waitForExistence(timeout: 5),
                "\(destination) must offer the account entry point"
            )
            XCTAssertTrue(
                app.buttons["account.open"].label.contains(localOnlyNotice),
                "\(destination) must disclose that data is stored locally only"
            )
        }
    }

    func testAccountCenterIsAToolbarDestinationRatherThanALaunchWall() {
        let app = launch()

        // Training is reachable before the account center is ever opened.
        XCTAssertTrue(app.buttons["开始今日训练"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            navigationEntryCount(in: app),
            destinations.count,
            "the account center must not become an extra top-level destination"
        )

        app.buttons["account.open"].tap()

        XCTAssertTrue(
            app.staticTexts["尚未登录"].waitForExistence(timeout: 5),
            "the account center opens on demand"
        )
        XCTAssertTrue(app.buttons["account.signInWithApple"].exists)
        XCTAssertTrue(
            app.staticTexts["account.localOnlyNotice"].exists,
            "the account center repeats the local-only guarantee"
        )
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-training-events"]
        app.launch()
        return app
    }

    /// Compact layouts expose destinations as tab-bar buttons, regular layouts
    /// as sidebar cells wrapping a label. Both are top-level navigation; only
    /// the control differs.
    private func select(_ destination: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[destination]
        if tab.exists {
            tab.tap()
            return
        }
        let sidebarLabel = app.cells.staticTexts[destination].firstMatch
        XCTAssertTrue(
            sidebarLabel.waitForExistence(timeout: 5),
            "\(destination) is not reachable in either layout"
        )
        sidebarLabel.tap()
    }

    private func navigationEntryCount(in app: XCUIApplication) -> Int {
        if app.tabBars.buttons.count > 0 {
            return app.tabBars.buttons.count
        }
        return destinations.filter { app.cells.staticTexts[$0].exists }.count
    }
}
