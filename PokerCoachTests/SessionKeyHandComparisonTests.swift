import Foundation
import PokerCore
import SessionSimulation
import StrategyContent
import TrainingDomain
import TrainingPersistence
import XCTest
@testable import PokerCoach

/// What a key hand shows beside the hand, and what it deliberately does not.
///
/// Two claims, and the second is the one with teeth. A covered hand shows the
/// installed content's frequencies and EVs next to what the user did, labelled
/// as a comparison. It does not show an EV loss, a score or a quality band —
/// not because nobody got round to it, but because grading needs an action and
/// a confidence submitted together and the user played a hand instead of
/// answering a question. The way to a grade is the replay button, which routes
/// the spot through the ordinary training pipeline.
final class SessionKeyHandComparisonTests: XCTestCase {
    private let seed: UInt64 = 16
    private let handCount = 15

    /// Measured: seed 16's third hand is covered by `rfi-hj`, and its sixth is
    /// covered by nothing. Both are needed — one test with only the covered
    /// case says nothing about withholding.
    private let coveredHandIndex = 2
    private let uncoveredHandIndex = 5

    // MARK: - The comparison itself

    @MainActor
    func testACoveredKeyHandShowsTheContentsFrequenciesAndEVsBesideWhatTheUserDid() async throws {
        let played = try await SessionReviewFixture.play(seed: seed, handCount: handCount)
        let review = try played.review(handIndex: coveredHandIndex)
        let comparison = try XCTUnwrap(review.comparison, "这一手没有对照，夹具选错了")
        let scenario = try XCTUnwrap(
            played.pack.scenarios.first { $0.id == comparison.scenarioID }
        )

        XCTAssertEqual(comparison.scenarioID, "rfi-hj")
        XCTAssertEqual(comparison.scenarioTitle, scenario.title)

        // What the user did, taken from the recorded hand rather than restated.
        let hand = try played.hand(coveredHandIndex)
        let heroPreflopActions = zip(hand.heroSpotSignatures, hand.heroActions)
            .filter { $0.0.street == .preflop }
            .map { $0.1 }
        XCTAssertTrue(
            heroPreflopActions.map(\.displayTitle).contains(comparison.heroActionTitle),
            "展示的行动 \(comparison.heroActionTitle) 不在英雄翻前实际做过的行动里"
        )

        // Every option the scenario has, with its frequency and its EV.
        XCTAssertFalse(scenario.options.isEmpty, "场景没有选项，下面的比较是空转的")
        XCTAssertEqual(comparison.rows.map(\.id), scenario.options.map(\.action.stableID))
        XCTAssertEqual(
            comparison.rows.map(\.frequencyText),
            scenario.options.map { StrategyNumberText.frequency(basisPoints: $0.frequencyBasisPoints) }
        )
        XCTAssertEqual(
            comparison.rows.map(\.evText),
            scenario.options.map { StrategyNumberText.ev($0.ev) }
        )
        // Real values, not placeholders: at least one row states a nonzero
        // frequency and at least one states an EV.
        XCTAssertTrue(comparison.rows.contains { $0.frequencyText != "0.0%" })
        XCTAssertEqual(comparison.rows.count, scenario.options.count)

        // And the weight the range gives what the hero actually did.
        XCTAssertEqual(
            comparison.heroActionWeightText,
            StrategyNumberText.frequency(
                basisPoints: try XCTUnwrap(
                    SessionContentMatcher(scenarios: played.pack.scenarios)
                        .heroActionWeightsBasisPoints(in: [hand])[coveredHandIndex]
                )
            )
        )
    }

    /// It says it is a comparison, and it is not a grade.
    @MainActor
    func testTheComparisonIsLabelledAComparisonAndCarriesNoGrade() async throws {
        let played = try await SessionReviewFixture.play(seed: seed, handCount: handCount)
        let comparison = try XCTUnwrap(
            try played.review(handIndex: coveredHandIndex).comparison
        )

        XCTAssertTrue(
            KeyHandComparison.notice.contains("对照"),
            KeyHandComparison.notice
        )
        XCTAssertTrue(
            KeyHandComparison.notice.contains("不是") && KeyHandComparison.notice.contains("评分"),
            "提示没有否认这是评分：\(KeyHandComparison.notice)"
        )

        // Nothing on the screen is an EV loss or a quality band. Checked over
        // every string the comparison can put in front of the user, so a field
        // added later has to be added to a screen that then fails this.
        let shown = [
            comparison.scenarioTitle,
            comparison.spotSummary,
            comparison.heroActionTitle,
            comparison.heroActionWeightText ?? "",
        ]
            + comparison.rows.map(\.actionTitle)
            + comparison.rows.map(\.frequencyText)
            + comparison.rows.map(\.evText)

        for banned in ["EV 损失", "优秀", "可接受", "可改进", "严重失误", "得分", "/ 100"] {
            for text in shown {
                XCTAssertFalse(
                    text.contains(banned),
                    "对照里出现了评分用语「\(banned)」：\(text)"
                )
            }
        }

        // And structurally: no property of the comparison is a grade under
        // another name. `FeedbackPresentation` has evLossText, qualityText and
        // scoreText; this type must have none of them.
        let labels = Set(
            Mirror(reflecting: comparison).children.compactMap(\.label)
        )
        XCTAssertFalse(labels.isEmpty)
        for banned in ["evLoss", "quality", "score", "grade"] {
            XCTAssertFalse(
                labels.contains { $0.lowercased().contains(banned.lowercased()) },
                "对照持有一个叫 \(banned) 的字段：\(labels.sorted())"
            )
        }
    }

    /// The content's own row for the line the hero took is marked.
    ///
    /// Swept rather than asserted on one hand, because the flag is only ever
    /// true when the hero's action kind is one the scenario lists — and a flag
    /// that is never true is decoration. Twelve sessions, and the count of
    /// marked comparisons is asserted to be neither zero nor all of them.
    @MainActor
    func testTheRowMatchingWhatTheHeroDidIsMarkedAndTheOthersAreNot() async throws {
        var comparisons = 0
        var withAMarkedRow = 0

        for seed in UInt64(1) ... 12 {
            let played = try await SessionReviewFixture.play(seed: seed, handCount: 30)
            for review in played.reviews {
                guard let comparison = review.comparison else {
                    continue
                }
                comparisons += 1
                let marked = comparison.rows.filter(\.isHeroAction)
                let heroKey = Self.rangeKey(displayTitle: comparison.heroActionTitle)
                if marked.isEmpty {
                    continue
                }
                withAMarkedRow += 1
                // Marked on the decision, not the sizing. A range chart names
                // folding, calling and putting money in; the amount is the
                // scenario's business and never the hero's, so a marked row is
                // one whose *kind* is what the hero did — a shove marks the
                // raise row, and it marks it at a size nobody played.
                for row in marked {
                    XCTAssertEqual(
                        Self.rangeKey(displayTitle: row.actionTitle),
                        heroKey,
                        "\(row.actionTitle) 被标为英雄的行动，英雄打的是 \(comparison.heroActionTitle)"
                    )
                }
                for row in comparison.rows where !row.isHeroAction {
                    XCTAssertNotEqual(
                        Self.rangeKey(displayTitle: row.actionTitle),
                        heroKey,
                        "\(row.actionTitle) 与英雄的行动同类，却没有被标出"
                    )
                }
            }
        }

        XCTAssertGreaterThan(comparisons, 20)
        XCTAssertGreaterThan(withAMarkedRow, 0, "没有任何一条对照标出了英雄的那一行")
        XCTAssertLessThan(
            withAMarkedRow,
            comparisons,
            "每一条对照都标出了英雄的那一行，标记没有区分度"
        )
    }

    // MARK: - Withholding

    @MainActor
    func testAnUncoveredKeyHandGetsTheReplayAndNothingElse() async throws {
        let played = try await SessionReviewFixture.play(seed: seed, handCount: handCount)
        let review = try played.review(handIndex: uncoveredHandIndex)

        XCTAssertNil(review.comparison, "内容没有覆盖这一手，却给了对照")
        XCTAssertNil(review.replayScenarioID, "内容没有覆盖这一手，却给了重打入口")
        // The replay is still there — withholding the comparison must not
        // withhold the hand.
        XCTAssertEqual(review.streets.count, 4)
        XCTAssertFalse(review.streets.allSatisfy(\.actions.isEmpty))
    }

    /// The replay entry exists exactly where a comparison does, and both cases
    /// occur. A rule that only ever fired one way would pass a test written
    /// against either half alone.
    @MainActor
    func testTheReplayEntryIsOfferedExactlyWhereAComparisonIs() async throws {
        var covered = 0
        var uncovered = 0

        for seed in UInt64(1) ... 12 {
            let played = try await SessionReviewFixture.play(seed: seed, handCount: 30)
            for review in played.reviews {
                XCTAssertEqual(
                    review.replayScenarioID != nil,
                    review.comparison != nil,
                    "第 \(review.handIndex) 手的重打入口与对照不同步"
                )
                if review.comparison == nil { uncovered += 1 } else { covered += 1 }
            }
        }

        XCTAssertGreaterThan(covered, 0, "十二局里没有一手命中内容")
        XCTAssertGreaterThan(uncovered, 0, "十二局里没有一手未命中内容")
    }

    /// No key hand is ever compared against a postflop scenario.
    ///
    /// The shipped pack is preflop-only, which makes this quiet there — so it
    /// is asserted against content that *does* contain flop scenarios: the
    /// app's own development fixture, which is what a debug build actually
    /// trains against. Without the street guard, a dealt flop spot matches
    /// `cash-bet-sizing` and the review offers a curated flop range as an
    /// answer to a flop nobody curated.
    @MainActor
    func testAFlopSpotIsNeverComparedEvenWhenContentHasFlopScenarios() async throws {
        let devURL = try XCTUnwrap(
            Bundle.main.url(forResource: "DevStrategyPack", withExtension: "json")
        )
        let dev = try StrategyPackLoader().load(
            data: try Data(contentsOf: devURL),
            expectedSHA256: nil
        )
        let postflopScenarioIDs = Set(
            dev.scenarios.filter { !$0.board.isEmpty }.map(\.id)
        )
        XCTAssertFalse(
            postflopScenarioIDs.isEmpty,
            "开发内容里没有翻后场景，这条断言没有对手"
        )

        var comparisons = 0
        for seed in UInt64(1) ... 12 {
            let played = try await SessionReviewFixture.play(
                seed: seed,
                handCount: 30,
                pack: dev
            )
            for review in played.reviews {
                guard let comparison = review.comparison else {
                    continue
                }
                comparisons += 1
                XCTAssertFalse(
                    postflopScenarioIDs.contains(comparison.scenarioID),
                    "第 \(review.handIndex) 手被拿去和翻后场景 \(comparison.scenarioID) 对照"
                )
            }
        }
        XCTAssertGreaterThan(comparisons, 0, "开发内容一手都没命中，断言是空转的")
    }

    // MARK: - Replaying as training

    /// The replay produces an ordinary training event.
    ///
    /// Through `AppDependencies.makeDecisionSessionViewModel`, which is the same
    /// call Today makes — the review screen hands it a scenario ID and nothing
    /// else. The event is then compared field by field against one produced the
    /// same way, and against the values the content and the submission imply,
    /// so a route that quietly stamped the event with where it came from would
    /// have to break one of them.
    @MainActor
    func testReplayingAKeyHandProducesAnEventTodaysTrainingCannotBeToldFrom() async throws {
        let played = try await SessionReviewFixture.play(seed: seed, handCount: handCount)
        let scenarioID = try XCTUnwrap(
            try played.review(handIndex: coveredHandIndex).replayScenarioID
        )
        let scenario = try XCTUnwrap(
            played.pack.scenarios.first { $0.id == scenarioID }
        )

        let (fromReplay, replayStore) = try await Self.submit(
            scenarioID: scenarioID,
            pack: played.pack
        )
        let (fromToday, _) = try await Self.submit(
            scenarioID: scenarioID,
            pack: played.pack
        )

        // Everything the contract carries, other than the three fields that
        // identify *this* answering of it.
        XCTAssertNotEqual(fromReplay.id, fromToday.id)
        XCTAssertEqual(fromReplay.scenarioID, fromToday.scenarioID)
        XCTAssertEqual(fromReplay.strategyPackID, fromToday.strategyPackID)
        XCTAssertEqual(fromReplay.strategyContentVersion, fromToday.strategyContentVersion)
        XCTAssertEqual(fromReplay.abilityDimension, fromToday.abilityDimension)
        XCTAssertEqual(fromReplay.submission, fromToday.submission)
        // `DecisionGrade` is not Equatable, so the grade is compared field by
        // field rather than skipped — it is the half of the event that carries
        // the scoring, and "indistinguishable" is empty without it.
        XCTAssertEqual(fromReplay.grade.selectedAction, fromToday.grade.selectedAction)
        XCTAssertEqual(
            fromReplay.grade.selectedFrequencyBasisPoints,
            fromToday.grade.selectedFrequencyBasisPoints
        )
        XCTAssertEqual(fromReplay.grade.selectedEV, fromToday.grade.selectedEV)
        XCTAssertEqual(fromReplay.grade.bestEV, fromToday.grade.bestEV)
        XCTAssertEqual(fromReplay.grade.evLoss, fromToday.grade.evLoss)
        XCTAssertEqual(
            fromReplay.grade.lossRateBasisPoints,
            fromToday.grade.lossRateBasisPoints
        )
        XCTAssertEqual(fromReplay.grade.score, fromToday.grade.score)
        XCTAssertEqual(fromReplay.grade.quality, fromToday.grade.quality)
        XCTAssertEqual(
            fromReplay.grade.isStrategicallyAvailable,
            fromToday.grade.isStrategicallyAvailable
        )
        XCTAssertEqual(fromReplay.localUserID, fromToday.localUserID)

        // And the values themselves are the content's, not something the
        // session invented.
        XCTAssertEqual(fromReplay.scenarioID, scenarioID)
        XCTAssertEqual(fromReplay.abilityDimension, scenario.abilityDimension)
        XCTAssertEqual(fromReplay.strategyPackID, played.pack.manifest.id)
        XCTAssertEqual(
            fromReplay.strategyContentVersion,
            played.pack.manifest.contentVersion
        )
        XCTAssertEqual(fromReplay.submission.confidence, .unsure)

        // One event, stored.
        let stored = try await replayStore.allEvents()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first, fromReplay)

        // There is no field on the contract that could say "this came from a
        // session", so there is nothing to be set.
        let labels = Set(Mirror(reflecting: fromReplay).children.compactMap(\.label))
        XCTAssertEqual(
            labels,
            [
                "id", "localUserID", "deviceID", "occurredAt", "scenarioID",
                "strategyPackID", "strategyContentVersion", "abilityDimension",
                "submission", "grade",
            ],
            "TrainingEvent 的字段集合变了，重打事件可能带上了来源标记"
        )
    }

    /// Nothing is shown until the event is on disk.
    ///
    /// Observed at the moment of the write rather than after it: the state when
    /// `append` is called must not already be `.feedback`. Checking only the
    /// state afterwards cannot tell "stored, then shown" from "shown, then
    /// stored" — with a failing store both end in `.failed`, and with a working
    /// one both end in `.feedback`.
    @MainActor
    func testTheReplayStoresTheEventBeforeItShowsAnyFeedback() async throws {
        let played = try await SessionReviewFixture.play(seed: seed, handCount: handCount)
        let scenarioID = try XCTUnwrap(
            try played.review(handIndex: coveredHandIndex).replayScenarioID
        )

        let store = StateObservingEventStore()
        let dependencies = AppDependencies.availableContent(
            eventStore: store,
            strategyPack: played.pack,
            strategyContentAvailability: .reviewedContentAvailable
        )
        let viewModel = dependencies.makeDecisionSessionViewModel(scenarioID: scenarioID)
        store.observation = { viewModel.state }

        await viewModel.load()
        viewModel.select(action: try XCTUnwrap(viewModel.legalActions.first))
        viewModel.setConfidence(.verySure)
        await viewModel.submit()

        XCTAssertEqual(store.appended.count, 1, "重打没有产生事件，顺序断言是空转的")
        XCTAssertEqual(viewModel.state, .feedback)
        XCTAssertNotEqual(
            store.stateAtAppend,
            .feedback,
            "事件落库时反馈已经在屏幕上了"
        )
        XCTAssertEqual(store.stateAtAppend, .answering)
    }

    /// And when the write fails, no feedback appears at all.
    @MainActor
    func testTheReplayShowsNoFeedbackWhenTheEventCannotBeStored() async throws {
        let played = try await SessionReviewFixture.play(seed: seed, handCount: handCount)
        let scenarioID = try XCTUnwrap(
            try played.review(handIndex: coveredHandIndex).replayScenarioID
        )

        let dependencies = AppDependencies.availableContent(
            eventStore: FailingEventStore(),
            strategyPack: played.pack,
            strategyContentAvailability: .reviewedContentAvailable
        )
        let viewModel = dependencies.makeDecisionSessionViewModel(scenarioID: scenarioID)
        await viewModel.load()
        XCTAssertEqual(viewModel.state, .answering)
        viewModel.select(action: try XCTUnwrap(viewModel.legalActions.first))
        viewModel.setConfidence(.verySure)
        await viewModel.submit()

        XCTAssertNotEqual(viewModel.state, .feedback, "事件没有落库，反馈却已经出来了")
        if case .failed = viewModel.state {} else {
            XCTFail("保存失败后状态是 \(viewModel.state)")
        }
    }

    /// A replay of a scenario the installed content does not have gets no
    /// feedback and writes nothing — the guard behind "the replay entry appears
    /// only where a comparison does".
    @MainActor
    func testReplayingAScenarioTheContentDoesNotHaveWritesNothing() async throws {
        let played = try await SessionReviewFixture.play(seed: seed, handCount: handCount)
        let store = try FileTrainingEventStore(
            directory: SessionReviewFixture.temporaryDirectory()
        )
        let dependencies = AppDependencies.availableContent(
            eventStore: store,
            strategyPack: played.pack,
            strategyContentAvailability: .reviewedContentAvailable
        )

        let viewModel = dependencies.makeDecisionSessionViewModel(
            scenarioID: "no-such-scenario"
        )
        await viewModel.load()

        if case .failed = viewModel.state {} else {
            XCTFail("不存在的场景加载成功了：\(viewModel.state)")
        }
        let stored = try await store.allEvents()
        XCTAssertTrue(stored.isEmpty)
    }

    /// The range-table name for an action, read off what the screen printed.
    ///
    /// Written out here rather than taken from `RangeBaseline.actionKey`: an
    /// expectation computed by the function under test agrees with it whatever
    /// it does.
    private static func rangeKey(displayTitle: String) -> String? {
        switch true {
        case displayTitle.hasPrefix("弃牌"): "fold"
        case displayTitle.hasPrefix("跟注"): "call"
        case displayTitle.hasPrefix("下注"), displayTitle.hasPrefix("加注"),
             displayTitle.hasPrefix("全下"): "raise"
        default: nil
        }
    }

    /// Answers a scenario the way a user would, and hands back the one event
    /// that produced.
    @MainActor
    private static func submit(
        scenarioID: String,
        pack: StrategyPack
    ) async throws -> (TrainingEvent, FileTrainingEventStore) {
        let store = try FileTrainingEventStore(
            directory: SessionReviewFixture.temporaryDirectory()
        )
        let dependencies = AppDependencies.availableContent(
            eventStore: store,
            strategyPack: pack,
            strategyContentAvailability: .reviewedContentAvailable
        )
        let viewModel = dependencies.makeDecisionSessionViewModel(scenarioID: scenarioID)
        await viewModel.load()
        XCTAssertEqual(viewModel.state, .answering)

        // Action and confidence together, which is the whole of what makes an
        // event gradeable.
        viewModel.select(action: try XCTUnwrap(viewModel.legalActions.first))
        viewModel.setConfidence(.unsure)
        await viewModel.submit()
        XCTAssertEqual(viewModel.state, .feedback)

        let events = try await store.allEvents()
        return (try XCTUnwrap(events.first), store)
    }
}

/// A store that cannot write.
private actor FailingEventStore: TrainingEventStore {
    struct Failure: Error {}

    private var events: [TrainingEvent] = []

    func append(_ event: TrainingEvent) throws {
        throw Failure()
    }

    func allEvents() throws -> [TrainingEvent] { events }
    func events(after checkpoint: UUID?) throws -> [TrainingEvent] { events }
}

/// A store that records what the screen was showing when the write happened.
@MainActor
private final class StateObservingEventStore: TrainingEventStore {
    private(set) var appended: [TrainingEvent] = []
    private(set) var stateAtAppend: DecisionSessionState?

    /// Set after the view model exists, which is why it is a variable.
    var observation: (@MainActor () -> DecisionSessionState)?

    func append(_ event: TrainingEvent) async throws {
        stateAtAppend = observation?()
        appended.append(event)
    }

    func allEvents() async throws -> [TrainingEvent] { appended }
    func events(after checkpoint: UUID?) async throws -> [TrainingEvent] { appended }
}
