import XCTest

/// Signing in is optional. These tests prove the whole M1A experience stays
/// reachable with no account, and that the local-only storage promise is
/// visible from every destination rather than buried in a settings screen.
final class AnonymousAccountEntryTests: XCTestCase {
    private let localOnlyNotice = "仅保存在本机。"

    func testAllFourDestinationsStayUsableAnonymouslyAndDiscloseLocalOnlyStorage() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-training-events"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["开发演示数据"].waitForExistence(timeout: 5),
            "the app must open straight into training without an account"
        )

        for destination in ["今日", "学习", "训练", "复盘"] {
            app.tabBars.buttons[destination].tap()
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
        let app = XCUIApplication()
        app.launchArguments = ["--reset-training-events"]
        app.launch()

        // Training is reachable before the account center is ever opened.
        XCTAssertTrue(app.buttons["开始今日训练"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.tabBars.buttons.count,
            4,
            "the account center must not become a fifth tab"
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
}
