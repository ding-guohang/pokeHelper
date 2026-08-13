import Foundation
import HandHistory
import HandHistoryPersistence
import PokerCore
import StrategyContent
import TrainingDomain
import TrainingPersistence
import XCTest
@testable import PokerCoach

/// Replaying an imported hand and reading every node's counterfactual writes no
/// training event; only completing a remediation drill from a covered node does.
///
/// A replay is a read: nobody authored frequencies for a stranger's hand, and
/// browsing the counterfactuals asks for no confidence and produces no grade. The
/// remediation the replay can start is the ordinary training flow, so completing
/// one records exactly one plain training event — the imported hand chose *which*
/// spot to drill, not whether the browse itself banks a sample.
final class HandReplayIsolationTests: XCTestCase {
    private let localUserID = UUID(uuidString: "10000000-0000-0000-0000-0000000000C1")!

    @MainActor
    func testBrowsingCounterfactualsWritesNothingThenRemediationAddsOne() async throws {
        // A non-empty event store, so "unchanged" is a claim about this store
        // rather than one satisfied by an app that cannot write events at all.
        let eventStore = try FileTrainingEventStore(directory: temporaryDirectory())
        try await eventStore.append(
            try TrainingEventFixture.make(
                localUserID: localUserID,
                deviceID: UUID(uuidString: "20000000-0000-0000-0000-0000000000C1")!
            )
        )
        let before = try await eventStore.allEvents()
        XCTAssertEqual(before.count, 1)

        // Adopt appendix A through the real import path.
        let libraryStore = try FileHandLibraryStore(directory: temporaryDirectory())
        let importer = HandImportCoordinator(libraryStore: libraryStore, eventStore: eventStore)
        let outcome = try await importer.importAndAccept(text: HandImportFixtureText.appendixA)
        guard case let .accepted(hand) = outcome else {
            return XCTFail("附录 A 应被采纳，实际：\(outcome)")
        }

        // The replay judges lines against the shipped content and its remediation
        // trains that same content — the wiring a real Hand Lab replay uses.
        let installed = try BundledContentLoader(bundle: .main).loadPreferredPack()
        let matcher = ImportedHandContentMatcher(scenarios: installed.pack.scenarios)
        let provider = InMemoryStrategyPackProvider(pack: installed.pack)

        let drillEventID = UUID(uuidString: "30000000-0000-0000-0000-0000000000C1")!
        let drillNow = Date(timeIntervalSince1970: 1_786_000_500)
        let drillDeviceID = UUID(uuidString: "20000000-0000-0000-0000-0000000000C2")!

        let viewModel = HandReplayViewModel(
            libraryStore: libraryStore,
            identity: hand.source.identity,
            tableSize: hand.tableSize,
            matcher: matcher,
            makeRemediationSession: { scenarioID in
                DecisionSessionViewModel(
                    scenarioID: scenarioID,
                    strategyProvider: provider,
                    scorer: DecisionScorer(),
                    eventStore: eventStore,
                    localUserID: self.localUserID,
                    deviceID: drillDeviceID,
                    makeEventID: { drillEventID },
                    now: { drillNow }
                )
            }
        )

        await viewModel.load()

        // The replay actually produced streets and hero nodes — "no event" is not
        // achieved by the surface having nothing to show.
        XCTAssertFalse((viewModel.streets ?? []).isEmpty, "回放应产出街")
        let counterfactuals = viewModel.counterfactuals
        XCTAssertFalse(counterfactuals.isEmpty, "回放应产出英雄节点")
        // Read every node's counterfactual and remediation id — a full browse.
        for node in counterfactuals {
            _ = node.weightBasisPoints
            _ = node.remediationScenarioID
        }

        // Browsing wrote nothing: the store is byte-for-byte what it was.
        let afterBrowse = try await eventStore.allEvents()
        XCTAssertEqual(afterBrowse.count, before.count)
        XCTAssertEqual(afterBrowse, before)

        // Now complete a remediation from a covered node — a live link, reached
        // exactly as a user would by tapping "练这个漏洞".
        let covered = try XCTUnwrap(
            counterfactuals.first { $0.remediationScenarioID != nil },
            "附录 A 应有命中内容的节点可补救"
        )
        let scenarioID = try XCTUnwrap(covered.remediationScenarioID)

        let session = viewModel.remediationSession(for: scenarioID)
        await session.load()
        XCTAssertEqual(session.state, .answering)
        let scenario = try XCTUnwrap(session.scenario)
        let action = try XCTUnwrap(
            scenario.options
                .map(\.action)
                .first { session.legalActions.contains($0) },
            "覆盖场景应有一个既合法又在策略选项中的行动"
        )
        session.select(action: action)
        session.setConfidence(.verySure)
        await session.submit()
        session.continueSession()
        XCTAssertEqual(session.state, .completed)

        // Exactly one new event — the drill, not the browse.
        let afterDrill = try await eventStore.allEvents()
        XCTAssertEqual(afterDrill.count, before.count + 1)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }
}
