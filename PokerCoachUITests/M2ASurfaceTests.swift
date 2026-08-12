import XCTest

/// Drives the M2A surfaces in a real build.
///
/// The milestone shipped an engine, a matcher, a key-hand selector and a
/// frequency report, all of them tested and none of them on a screen. M1C
/// already produced exactly that — a capability with six passing unit tests and
/// no view reading any of it — and nothing but a UI test tells the two states
/// apart.
///
/// ## Why the seed is fixed
///
/// `--session-seed 25` deals a session whose hands are known: its key hands are
/// 7 and 13, which the installed development content covers, and 9, 2 and 0,
/// which it does not. Without a fixed seed a test that opens a key hand and
/// expects four streets is right most of the time, and a test that expects a
/// comparison is right rather less often than that. The numbers asserted below
/// were measured from that session and are checked against the same seed by
/// `SessionStreetReplayTests` and `SessionKeyHandComparisonTests` in the unit
/// suite, so a change in the engine breaks those with a readable message before
/// it breaks this with a missing element.
final class M2ASurfaceTests: XCTestCase {
    private let keyHandWithContent = 7
    private let keyHandWithoutContent = 9

    /// Who the user is about to play against, and where those numbers come
    /// from. Written out rather than read from `OpponentProfileTable`, which
    /// this target cannot see: the point is that the screen states the defined
    /// values, and an expectation taken from the definition would agree with a
    /// screen that computed them from play.
    func testTheOpponentTableAndItsProvenanceAreShownBeforeAnyHandIsDealt() {
        let app = launch()
        openSession(app)

        XCTAssertEqual(
            app.staticTexts["session.disclosure"].label,
            "对手行为来自固定启发式规则，不是求解器策略，也不代表真实牌手。"
        )

        let expected: [(id: String, name: String, entry: String, aggression: String, calling: String)] = [
            ("rock", "岩石", "8.0%", "25.0%", "20.0%"),
            ("tag", "稳固加注者", "24.0%", "60.0%", "40.0%"),
            ("station", "跟注站", "44.0%", "5.0%", "85.0%"),
            ("maniac", "疯子", "62.0%", "90.0%", "60.0%"),
        ]
        for profile in expected {
            XCTAssertEqual(
                app.staticTexts["session.profile.\(profile.id).name"].label,
                profile.name
            )
            XCTAssertEqual(
                app.staticTexts["session.profile.\(profile.id).entry"].label,
                profile.entry
            )
            XCTAssertEqual(
                app.staticTexts["session.profile.\(profile.id).aggression"].label,
                profile.aggression
            )
            XCTAssertEqual(
                app.staticTexts["session.profile.\(profile.id).calling"].label,
                profile.calling
            )
            XCTAssertFalse(
                app.staticTexts["session.profile.\(profile.id).summary"].label.isEmpty
            )
        }
    }

    func testPlayingASessionListsBetweenThreeAndFiveKeyHands() {
        let app = launch()
        play15Hands(app)

        XCTAssertEqual(app.staticTexts["session.summary.hands"].label, "已打完 15 手")

        let keyHands = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "session.keyhand.")
        )
        XCTAssertGreaterThanOrEqual(keyHands.count, 3)
        XCTAssertLessThanOrEqual(keyHands.count, 5)
    }

    /// Each street shows its own board, its own closing pot and its own
    /// actions. The four pots are four different numbers, so a screen printing
    /// the final pot four times fails here rather than looking complete.
    func testAKeyHandReplaysStreetByStreetWithItsOwnBoardPotAndActions() {
        let app = launch()
        play15Hands(app)
        openKeyHand(app, keyHandWithContent)

        let boards = ["preflop": "0", "flop": "3", "turn": "4", "river": "5"]
        for (street, count) in boards {
            let element = app.staticTexts["session.replay.\(street).boardCount"]
            XCTAssertTrue(element.waitForExistence(timeout: 5), "\(street) 没有公共牌数")
            XCTAssertTrue(
                element.label.hasSuffix(count),
                "\(street) 显示的公共牌数是 \(element.label)"
            )
        }

        let pots = ["preflop": "3 BB", "flop": "6 BB", "turn": "12 BB", "river": "24 BB"]
        for (street, pot) in pots {
            let element = app.staticTexts["session.replay.\(street).pot"]
            XCTAssertTrue(
                element.label.hasSuffix(pot),
                "\(street) 的底池是 \(element.label)，应当以 \(pot) 结尾"
            )
        }
        XCTAssertEqual(Set(pots.values).count, 4, "四个街道的底池被写成了同一个数")

        let actionCounts = ["preflop": "6", "flop": "4", "turn": "5", "river": "3"]
        for (street, count) in actionCounts {
            XCTAssertTrue(
                app.staticTexts["session.replay.\(street).actionCount"].label.hasSuffix(count),
                "\(street) 的行动数是 \(app.staticTexts["session.replay.\(street).actionCount"].label)"
            )
            // And the lines themselves are there, one per action on that
            // street — a count with nothing under it would pass the line above.
            XCTAssertTrue(
                app.staticTexts["session.replay.\(street)-0"].exists,
                "\(street) 报了行动数却没有列出行动"
            )
        }
        XCTAssertFalse(
            app.staticTexts["session.replay.river-3"].exists,
            "河牌只有三个行动，却列出了第四个"
        )
    }

    /// A covered hand shows the content's numbers, says it is a comparison, and
    /// offers the way into training — which really is training: action and
    /// confidence submitted together, then feedback.
    func testACoveredKeyHandComparesAndRoutesTheReplayIntoTraining() {
        let app = launch()
        play15Hands(app)
        openKeyHand(app, keyHandWithContent)

        let notice = app.staticTexts["session.comparison.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "命中内容的关键手没有对照")
        XCTAssertTrue(notice.label.contains("对照"), notice.label)
        XCTAssertTrue(notice.label.contains("不是"), notice.label)
        XCTAssertTrue(notice.label.contains("评分"), notice.label)

        XCTAssertTrue(app.staticTexts["session.comparison.heroAction"].exists)

        // Frequencies and EVs, at least two rows of them.
        let frequencies = app.staticTexts.matching(
            NSPredicate(format: "identifier ENDSWITH %@", ".frequency")
        )
        let evs = app.staticTexts.matching(
            NSPredicate(format: "identifier ENDSWITH %@", ".ev")
        )
        XCTAssertGreaterThanOrEqual(frequencies.count, 2)
        XCTAssertEqual(evs.count, frequencies.count)

        // No grade anywhere on this screen. The feedback screen's own frequency
        // block is the thing that carries one, and it must not be here.
        XCTAssertFalse(app.otherElements["feedback.actionFrequencies"].exists)

        let replay = app.buttons["session.replayAsTraining"]
        XCTAssertTrue(replay.exists, "命中内容的关键手没有重打入口")
        replay.tap()

        // The ordinary training screen: an action, a confidence, one submit.
        XCTAssertTrue(app.buttons["decision.submit"].waitForExistence(timeout: 10))
        let action = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "decision.action.")
        ).element(boundBy: 0)
        XCTAssertTrue(action.exists, "重打没有给出行动选项")
        action.tap()
        app.buttons["decision.confidence.verySure"].tap()
        app.buttons["decision.submit"].tap()

        XCTAssertTrue(
            app.staticTexts["回答已保存"].waitForExistence(timeout: 10),
            "重打提交后没有落库并给出反馈"
        )
    }

    func testAnUncoveredKeyHandShowsNeitherComparisonNorReplay() {
        let app = launch()
        play15Hands(app)
        openKeyHand(app, keyHandWithoutContent)

        XCTAssertTrue(
            app.staticTexts["session.replay.preflop.pot"].waitForExistence(timeout: 5),
            "未命中内容的关键手连回放都没有"
        )
        XCTAssertTrue(app.staticTexts["session.replay.river.pot"].exists)
        XCTAssertFalse(
            app.staticTexts["session.comparison.notice"].exists,
            "内容没有覆盖这一手，却显示了对照"
        )
        XCTAssertFalse(
            app.buttons["session.replayAsTraining"].exists,
            "内容没有覆盖这一手，却给了重打入口"
        )
    }

    func testTheFrequencyReportIsReachableAndReportsPerPosition() {
        let app = launch()
        play15Hands(app)

        app.buttons["session.frequency.open"].tap()

        XCTAssertTrue(
            app.staticTexts["session.frequency.rule"].waitForExistence(timeout: 10),
            "频率报告没有说明样本阈值"
        )
        let spots = app.staticTexts.matching(
            NSPredicate(format: "identifier ENDSWITH %@", ".spot")
        )
        XCTAssertGreaterThan(spots.count, 0, "频率报告一行都没有")
        let actuals = app.staticTexts.matching(
            NSPredicate(format: "identifier ENDSWITH %@", ".actual")
        )
        XCTAssertEqual(actuals.count, spots.count, "有位置却没有实际频率")
        // Fifteen hands is nowhere near thirty opportunities anywhere, so every
        // row has to be withholding its verdict rather than printing one.
        let withheld = app.staticTexts.matching(
            NSPredicate(format: "identifier ENDSWITH %@", ".withheld")
        )
        XCTAssertEqual(
            withheld.count,
            spots.count,
            "一局 15 手就有位置给出了结论"
        )
    }

    // MARK: - Driving

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--reset-training-events",
            "--reset-sessions",
            "--session-seed", "25",
        ]
        app.launch()
        return app
    }

    /// Training sits behind a tab on iPhone and a sidebar row on iPad.
    private func openSession(_ app: XCUIApplication) {
        if app.tabBars.buttons["训练"].waitForExistence(timeout: 10) {
            app.tabBars.buttons["训练"].tap()
        } else {
            let row = app.cells.staticTexts["训练"]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
        }
        XCTAssertTrue(app.buttons["session.start"].waitForExistence(timeout: 10))
    }

    private func play15Hands(_ app: XCUIApplication) {
        openSession(app)
        app.buttons["session.handCount.15"].tap()
        app.buttons["session.start"].tap()
        XCTAssertTrue(
            app.staticTexts["session.summary.hands"].waitForExistence(timeout: 60),
            "对局没有打完"
        )
    }

    private func openKeyHand(_ app: XCUIApplication, _ handIndex: Int) {
        let button = app.buttons["session.keyhand.\(handIndex)"]
        XCTAssertTrue(
            button.waitForExistence(timeout: 10),
            "第 \(handIndex + 1) 手不在关键手列表里"
        )
        button.tap()
        XCTAssertTrue(
            app.staticTexts["session.keyhand.reason"].waitForExistence(timeout: 10)
        )
    }
}
