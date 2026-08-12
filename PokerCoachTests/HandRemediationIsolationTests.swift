import Foundation
import HandHistory
import HandHistoryPersistence
import StrategyContent
import TrainingDomain
import TrainingPersistence
import XCTest
@testable import PokerCoach

/// Opening analysis and reading its remediation entries writes no training
/// event.
///
/// A training event is recorded only when the user *completes* a remediation
/// drill through the ordinary session flow. Reaching the analysis — running the
/// coordinator and asking each key node for the scenario a drill would run — is
/// a read: it decides which spots offer "练这个漏洞", and touches the event store
/// for none of them. The coordinator holds the store, so this is a claim about
/// the path a real analysis takes, not about a type with no access.
final class HandRemediationIsolationTests: XCTestCase {
    @MainActor
    func testReadingRemediationEntriesWritesNoTrainingEvent() async throws {
        // A non-empty store, so "unchanged" is a claim about this store rather
        // than one satisfied by an app that cannot write events at all.
        let eventStore = try FileTrainingEventStore(directory: temporaryDirectory())
        try await eventStore.append(
            try TrainingEventFixture.make(
                localUserID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                deviceID: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
            )
        )
        let before = try await eventStore.allEvents()
        XCTAssertEqual(before.count, 1)

        // Adopt appendix G — a genuine covered deviation — through the import path.
        let libraryStore = try FileHandLibraryStore(directory: temporaryDirectory())
        let importer = HandImportCoordinator(libraryStore: libraryStore, eventStore: eventStore)
        let outcome = try await importer.importAndAccept(text: HandImportFixtureText.btnOpenTrash)
        guard case let .accepted(hand) = outcome else {
            return XCTFail("附录 G 应被采纳，实际：\(outcome)")
        }

        let installed = try BundledContentLoader(bundle: .main).loadPreferredPack()
        let coordinator = HandAnalysisCoordinator(
            libraryStore: libraryStore,
            eventStore: eventStore,
            matcher: ImportedHandContentMatcher(scenarios: installed.pack.scenarios)
        )

        // Drive the analysis path and the remediation bridge over its nodes,
        // without starting any drill.
        let keyNodes = try await coordinator.analyze(identity: hand.source.identity)
        let remediationIDs = keyNodes.map { remediationScenarioID(for: $0) }

        // The read actually did something — a covered deviation offered a
        // remediation, so "no event" was not achieved by finding nothing.
        XCTAssertTrue(
            remediationIDs.contains { $0 != nil },
            "附录 G 的偏离节点应暴露一个补救场景"
        )

        // And the store is byte-for-byte what it was: reading remediation entries
        // records nothing.
        let after = try await eventStore.allEvents()
        XCTAssertEqual(after.count, before.count)
        XCTAssertEqual(after, before)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }
}
