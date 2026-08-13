import Foundation
import HandHistory
import HandHistoryPersistence
import PokerCore
import StrategyContent
import TrainingDomain
import TrainingPersistence
import XCTest
@testable import PokerCoach

/// Building and saving a constructed spot writes no training event; completing a
/// remediation drill on a covered one writes exactly one, a plain training event.
///
/// A hand-built spot is not a training answer, so the builder's save path reaches
/// only `FileConstructedSpotStore`. The event store is left byte-for-byte, and a
/// non-empty one proves that is a claim about this store rather than about an app
/// that cannot write events. The positive control drives the covered spot's
/// remediation to completion so "unchanged" is not achieved by a builder that
/// simply never trains anything.
final class ScenarioBuilderIsolationTests: XCTestCase {
    private let localUserID = UUID(uuidString: "10000000-0000-0000-0000-0000000000C1")!
    private let deviceID = UUID(uuidString: "20000000-0000-0000-0000-0000000000C1")!

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    @MainActor
    func testBuildingAndSavingWritesNoEventWhileRemediationRecordsExactlyOne() async throws {
        // A non-empty store, so "unchanged" is a claim about this store rather
        // than one satisfied by an app that cannot write events at all.
        let eventStore = try FileTrainingEventStore(directory: temporaryDirectory())
        try await eventStore.append(
            try TrainingEventFixture.make(localUserID: localUserID, deviceID: deviceID)
        )
        let before = try await eventStore.allEvents()
        XCTAssertEqual(before.count, 1)

        // The reviewed pack, judged and trained against the same way the app does.
        let pack = try BundledContentLoader(bundle: .main).loadPreferredPack().pack
        let provider = InMemoryStrategyPackProvider(pack: pack)
        let spotStore = try FileConstructedSpotStore(directory: temporaryDirectory())

        let viewModel = ScenarioBuilderViewModel(
            matcher: ImportedHandContentMatcher(scenarios: pack.scenarios),
            store: spotStore,
            makeRemediationSession: { scenarioID in
                DecisionSessionViewModel(
                    scenarioID: scenarioID,
                    strategyProvider: provider,
                    scorer: DecisionScorer(),
                    eventStore: eventStore,
                    localUserID: self.localUserID,
                    deviceID: self.deviceID,
                    makeEventID: { UUID(uuidString: "30000000-0000-0000-0000-0000000000C1")! },
                    now: { Date(timeIntervalSince1970: 1_786_000_300) }
                )
            }
        )

        // A covered BTN open: 100BB deep, AA, unopened, raising — the shipped
        // `rfi-btn` scenario.
        viewModel.heroSeatOffsetFromButton = 0
        viewModel.firstCardCode = "As"
        viewModel.secondCardCode = "Ad"
        viewModel.facing = .unopened
        viewModel.effectiveStackBB = 100
        viewModel.actionVerb = .raise
        viewModel.actionToBB = 2.5

        viewModel.build()
        XCTAssertEqual(viewModel.remediationScenarioID, "rfi-btn", "构造的 BTN 开池应被 rfi-btn 覆盖")

        // Save the spot — persistence only, no drill.
        await viewModel.save()
        XCTAssertNotNil(viewModel.savedIdentity)
        let savedSpots = try await spotStore.spots()
        XCTAssertEqual(savedSpots.count, 1, "构造 spot 应落进构造存储")

        // The event store is byte-for-byte what it was: building and saving
        // records nothing.
        let afterSave = try await eventStore.allEvents()
        XCTAssertEqual(afterSave.count, before.count)
        XCTAssertEqual(afterSave, before)

        // Positive control: completing the covered spot's remediation drill
        // appends exactly one ordinary training event.
        let session = try XCTUnwrap(viewModel.remediationSession())
        await session.load()
        XCTAssertEqual(session.state, .answering)
        let scenario = try XCTUnwrap(session.scenario)
        let action = try XCTUnwrap(
            scenario.options.map(\.action).first { session.legalActions.contains($0) },
            "rfi-btn 应有一个既合法又在策略选项中的行动"
        )
        session.select(action: action)
        session.setConfidence(.verySure)
        await session.submit()
        session.continueSession()
        XCTAssertEqual(session.state, .completed)

        let afterDrill = try await eventStore.allEvents()
        XCTAssertEqual(afterDrill.count, before.count + 1, "完成一道补救应恰增一条事件")
    }
}
