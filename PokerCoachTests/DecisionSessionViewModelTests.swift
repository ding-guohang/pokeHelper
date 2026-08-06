import Foundation
import PokerCore
import StrategyContent
import TrainingDomain
import XCTest
@testable import PokerCoach

@MainActor
final class DecisionSessionViewModelTests: XCTestCase {
    func testAnsweringAllowsSubmitAttemptBeforeSelections() async {
        let sut = DecisionSessionFixture.makeViewModel()

        await sut.load()

        XCTAssertEqual(sut.state, .answering)
        XCTAssertTrue(sut.canSubmit)
        XCTAssertFalse(sut.canRetry)
    }

    func testSubmitRequiresActionAndConfidence() async throws {
        let fixture = DecisionSessionFixture.make()
        await fixture.viewModel.load()

        XCTAssertEqual(fixture.viewModel.state, .answering)
        await fixture.viewModel.submit()

        XCTAssertEqual(
            fixture.viewModel.validationMessage,
            "请选择行动和信心程度"
        )
        let events = await fixture.store.allEvents()
        XCTAssertTrue(events.isEmpty)
    }

    func testIllegalActionCannotBecomeACompleteSubmission() async throws {
        let fixture = DecisionSessionFixture.make()
        await fixture.viewModel.load()

        fixture.viewModel.select(action: .check)
        fixture.viewModel.setConfidence(.verySure)
        await fixture.viewModel.submit()

        XCTAssertNil(fixture.viewModel.selectedAction)
        XCTAssertEqual(
            fixture.viewModel.validationMessage,
            "请选择行动和信心程度"
        )
        let events = await fixture.store.allEvents()
        XCTAssertTrue(events.isEmpty)
    }

    func testLoadExposesOnlyLegalActionsInStableDisplayOrder() async {
        let sut = DecisionSessionFixture.makeViewModel()

        await sut.load()

        XCTAssertEqual(
            sut.legalActions,
            [
                .fold,
                .call(to: BBAmount(centiBB: 200)),
                .raise(to: BBAmount(centiBB: 800)),
                .raise(to: BBAmount(centiBB: 1_200)),
                .allIn(to: BBAmount(centiBB: 10_000))
            ]
        )
    }

    func testM1ASixPlayerFixturePresentsDerivedButtonPosition() async {
        let fixture = DecisionSessionFixture.make()

        await fixture.viewModel.load()

        XCTAssertEqual(fixture.scenario.assumptions.tableSize, 6)
        XCTAssertEqual(fixture.scenario.heroSeatOffsetFromButton, 0)
        XCTAssertEqual(fixture.viewModel.positionLabel, "BTN")
        XCTAssertNotEqual(
            fixture.viewModel.positionLabel,
            fixture.scenario.title
        )
    }

    func testLoadRequestsExactlyOneScenarioByID() async {
        let pack = DecisionSessionFixture.makePack()
        let provider = RecordingStrategyProvider(pack: pack)
        let sut = DecisionSessionFixture.makeViewModel(
            provider: provider,
            store: InMemoryTrainingEventStore()
        )

        await sut.load()

        let requestedScenarioIDs = await provider.requestedScenarioIDs()
        XCTAssertEqual(
            requestedScenarioIDs,
            ["fixture-scenario"]
        )
    }

    func testValidSubmitGradesAndPersistsOneImmutableVersionedEvent() async throws {
        let fixture = DecisionSessionFixture.make()
        await fixture.viewModel.load()
        let action = fixture.scenario.options[0].action
        fixture.viewModel.select(action: action)
        fixture.viewModel.setConfidence(.verySure)

        await fixture.viewModel.submit()

        XCTAssertEqual(fixture.viewModel.state, .feedback)
        let savedEvents = await fixture.store.allEvents()
        let event = try XCTUnwrap(savedEvents.only)
        XCTAssertEqual(event.id, DecisionSessionFixture.eventID)
        XCTAssertEqual(event.localUserID, DecisionSessionFixture.localUserID)
        XCTAssertEqual(event.deviceID, DecisionSessionFixture.deviceID)
        XCTAssertEqual(event.occurredAt, DecisionSessionFixture.occurredAt)
        XCTAssertEqual(event.scenarioID, fixture.scenario.id)
        XCTAssertEqual(event.strategyPackID, "cash-pack")
        XCTAssertEqual(event.strategyContentVersion, "2026.08.06")
        XCTAssertEqual(
            event.abilityDimension,
            fixture.scenario.abilityDimension
        )
        XCTAssertEqual(event.submission.action, action)
        XCTAssertEqual(event.submission.confidence, .verySure)
        XCTAssertEqual(event.grade.selectedAction, action)

        await fixture.viewModel.submit()
        let eventsAfterDuplicateSubmit = await fixture.store.allEvents()
        XCTAssertEqual(eventsAfterDuplicateSubmit.count, 1)
    }

    func testSaveFailureCanRetryWithoutGradingOrCreatingANewEvent() async throws {
        let pack = DecisionSessionFixture.makePack()
        let store = FailFirstTrainingEventStore()
        var gradeCount = 0
        let scorer = DecisionScorer()
        let sut = DecisionSessionFixture.makeViewModel(
            provider: InMemoryStrategyPackProvider(pack: pack),
            store: store,
            grader: { submission, scenario in
                gradeCount += 1
                return try scorer.grade(
                    submission: submission,
                    scenario: scenario
                )
            }
        )
        await sut.load()
        sut.select(action: pack.scenarios[0].options[0].action)
        sut.setConfidence(.guessing)

        await sut.submit()

        XCTAssertEqual(
            sut.state,
            .failed(message: "保存失败，请重试")
        )
        XCTAssertEqual(gradeCount, 1)

        await sut.submit()

        XCTAssertEqual(sut.state, .feedback)
        XCTAssertEqual(gradeCount, 1)
        let attemptedEventIDs = await store.attemptedEventIDs()
        XCTAssertEqual(attemptedEventIDs, [
            DecisionSessionFixture.eventID,
            DecisionSessionFixture.eventID
        ])
        let events = await store.allEvents()
        XCTAssertEqual(events.count, 1)
    }

    func testScoringFailureReturnsToEditableAnsweringAndCanSubmitAgain() async {
        enum GradingFailure: Error {
            case unavailable
        }

        let pack = DecisionSessionFixture.makePack()
        let store = InMemoryTrainingEventStore()
        let scorer = DecisionScorer()
        var gradeCount = 0
        let sut = DecisionSessionFixture.makeViewModel(
            provider: InMemoryStrategyPackProvider(pack: pack),
            store: store,
            grader: { submission, scenario in
                gradeCount += 1
                guard gradeCount > 1 else {
                    throw GradingFailure.unavailable
                }
                return try scorer.grade(
                    submission: submission,
                    scenario: scenario
                )
            }
        )
        await sut.load()
        let action = pack.scenarios[0].options[0].action
        sut.select(action: action)
        sut.setConfidence(.verySure)

        await sut.submit()

        XCTAssertEqual(sut.state, .answering)
        XCTAssertEqual(sut.validationMessage, "评分失败，请重试")
        XCTAssertEqual(sut.selectedAction, action)
        XCTAssertEqual(sut.selectedConfidence?.rawValue, "verySure")
        XCTAssertTrue(sut.canSubmit)
        XCTAssertFalse(sut.canRetry)
        let eventsAfterFailure = await store.allEvents()
        XCTAssertTrue(eventsAfterFailure.isEmpty)

        await sut.submit()

        XCTAssertEqual(sut.state, .feedback)
        XCTAssertEqual(gradeCount, 2)
        let eventsAfterRetry = await store.allEvents()
        XCTAssertEqual(eventsAfterRetry.count, 1)
    }

    func testLoadFailureSurfacesChineseRetryMessageAndCanRetry() async {
        let provider = FailFirstStrategyProvider(
            pack: DecisionSessionFixture.makePack()
        )
        let sut = DecisionSessionFixture.makeViewModel(
            provider: provider,
            store: InMemoryTrainingEventStore()
        )

        await sut.load()
        XCTAssertEqual(
            sut.state,
            .failed(message: "场景加载失败，请重试")
        )
        XCTAssertTrue(sut.canRetry)

        await sut.load()
        XCTAssertEqual(sut.state, .answering)
        XCTAssertFalse(sut.canRetry)
    }

    func testSubmissionIsDisabledWhileSavingAndConcurrentSubmitIsIgnored() async {
        let pack = DecisionSessionFixture.makePack()
        let store = SuspendedTrainingEventStore()
        let sut = DecisionSessionFixture.makeViewModel(
            provider: InMemoryStrategyPackProvider(pack: pack),
            store: store
        )
        await sut.load()
        sut.select(action: pack.scenarios[0].options[0].action)
        sut.setConfidence(.unsure)

        let firstSubmit = Task { await sut.submit() }
        await store.waitUntilAppendStarts()

        XCTAssertTrue(sut.isSaving)
        XCTAssertFalse(sut.canSubmit)
        await sut.submit()
        let appendCallCount = await store.appendCallCount()
        XCTAssertEqual(appendCallCount, 1)

        await store.resumeAppend()
        await firstSubmit.value
        XCTAssertEqual(sut.state, .feedback)
    }

    func testSaveRetryIsDisabledWhileRetryIsInFlight() async {
        let pack = DecisionSessionFixture.makePack()
        let store = FailThenSuspendTrainingEventStore()
        let sut = DecisionSessionFixture.makeViewModel(
            provider: InMemoryStrategyPackProvider(pack: pack),
            store: store
        )
        await sut.load()
        sut.select(action: pack.scenarios[0].options[0].action)
        sut.setConfidence(.unsure)
        await sut.submit()

        XCTAssertEqual(
            sut.state,
            .failed(message: "保存失败，请重试")
        )
        XCTAssertTrue(sut.canRetry)

        let retry = Task { await sut.submit() }
        await store.waitUntilRetryStarts()

        XCTAssertTrue(sut.isSaving)
        XCTAssertFalse(sut.canSubmit)
        XCTAssertFalse(sut.canRetry)
        await sut.submit()
        let appendCallCount = await store.appendCallCount()
        XCTAssertEqual(appendCallCount, 2)

        await store.resumeRetry()
        await retry.value
        XCTAssertEqual(sut.state, .feedback)
        XCTAssertFalse(sut.canRetry)
    }

    func testContinueSessionMovesFeedbackToCompleted() async {
        let fixture = DecisionSessionFixture.make()
        await fixture.viewModel.load()
        fixture.viewModel.select(
            action: fixture.scenario.options[0].action
        )
        fixture.viewModel.setConfidence(.unsure)
        await fixture.viewModel.submit()

        fixture.viewModel.continueSession()

        XCTAssertEqual(fixture.viewModel.state, .completed)
    }
}

private actor FailThenSuspendTrainingEventStore: TrainingEventStore {
    enum Failure: Error {
        case unavailable
    }

    private var events: [TrainingEvent] = []
    private var appendCount = 0
    private var retryStarted: CheckedContinuation<Void, Never>?
    private var retryRelease: CheckedContinuation<Void, Never>?

    func append(_ event: TrainingEvent) async throws {
        appendCount += 1
        guard appendCount > 1 else {
            throw Failure.unavailable
        }

        retryStarted?.resume()
        retryStarted = nil
        await withCheckedContinuation { continuation in
            retryRelease = continuation
        }
        events.append(event)
    }

    func allEvents() -> [TrainingEvent] {
        events
    }

    func events(after checkpoint: UUID?) -> [TrainingEvent] {
        events
    }

    func waitUntilRetryStarts() async {
        guard appendCount < 2 else {
            return
        }
        await withCheckedContinuation { continuation in
            retryStarted = continuation
        }
    }

    func resumeRetry() {
        retryRelease?.resume()
        retryRelease = nil
    }

    func appendCallCount() -> Int {
        appendCount
    }
}

private actor RecordingStrategyProvider: StrategyPackProviding {
    let packValue: StrategyPack
    var requests: [String] = []

    init(pack: StrategyPack) {
        packValue = pack
    }

    func pack() -> StrategyPack {
        packValue
    }

    func scenario(id: String) throws -> DecisionScenario {
        requests.append(id)
        guard let scenario = packValue.scenarios.first(where: {
            $0.id == id
        }) else {
            throw StrategyPackLookupError.scenarioNotFound(id: id)
        }
        return scenario
    }

    func requestedScenarioIDs() -> [String] {
        requests
    }
}

private actor FailFirstStrategyProvider: StrategyPackProviding {
    enum Failure: Error {
        case unavailable
    }

    let packValue: StrategyPack
    var scenarioRequestCount = 0

    init(pack: StrategyPack) {
        packValue = pack
    }

    func pack() -> StrategyPack {
        packValue
    }

    func scenario(id: String) throws -> DecisionScenario {
        scenarioRequestCount += 1
        guard scenarioRequestCount > 1 else {
            throw Failure.unavailable
        }
        guard let scenario = packValue.scenarios.first(where: {
            $0.id == id
        }) else {
            throw StrategyPackLookupError.scenarioNotFound(id: id)
        }
        return scenario
    }
}

private actor FailFirstTrainingEventStore: TrainingEventStore {
    enum Failure: Error {
        case unavailable
    }

    var attempts: [UUID] = []
    var events: [TrainingEvent] = []

    func append(_ event: TrainingEvent) throws {
        attempts.append(event.id)
        guard attempts.count > 1 else {
            throw Failure.unavailable
        }
        guard !events.contains(where: { $0.id == event.id }) else {
            return
        }
        events.append(event)
    }

    func allEvents() -> [TrainingEvent] {
        events
    }

    func events(after checkpoint: UUID?) -> [TrainingEvent] {
        events
    }

    func attemptedEventIDs() -> [UUID] {
        attempts
    }
}

private actor SuspendedTrainingEventStore: TrainingEventStore {
    var events: [TrainingEvent] = []
    var appendCount = 0
    var appendStarted: CheckedContinuation<Void, Never>?
    var appendRelease: CheckedContinuation<Void, Never>?

    func append(_ event: TrainingEvent) async {
        appendCount += 1
        appendStarted?.resume()
        appendStarted = nil
        await withCheckedContinuation { continuation in
            appendRelease = continuation
        }
        events.append(event)
    }

    func allEvents() -> [TrainingEvent] {
        events
    }

    func events(after checkpoint: UUID?) -> [TrainingEvent] {
        events
    }

    func waitUntilAppendStarts() async {
        guard appendCount == 0 else {
            return
        }
        await withCheckedContinuation { continuation in
            appendStarted = continuation
        }
    }

    func resumeAppend() {
        appendRelease?.resume()
        appendRelease = nil
    }

    func appendCallCount() -> Int {
        appendCount
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? self[0] : nil
    }
}
