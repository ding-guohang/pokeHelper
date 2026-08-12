import Foundation
import HandHistory
import HandHistoryPersistence
import StrategyContent
import TrainingDomain
import TrainingPersistence
import XCTest
@testable import PokerCoach

/// Analyzing an imported hand never writes a training event.
///
/// An imported hand is not a graded answer: nobody authored frequencies for a
/// stranger's hand, and analysis asks for no confidence and produces no grade.
/// An event manufactured from one would be a sample the ability profile cannot
/// tell from a real answer. The analysis coordinator *holds* the event store —
/// it is the type that could write one — and driving a real analysis through it,
/// on a hand with a genuine deviation, leaves the store untouched.
final class HandAnalysisEventIsolationTests: XCTestCase {
    @MainActor
    func testAnalyzingAHandWritesNoTrainingEvent() async throws {
        // A non-empty event store, so "unchanged" is a claim about this store
        // rather than one satisfied by an app that cannot write events at all.
        let eventStore = try FileTrainingEventStore(directory: temporaryDirectory())
        try await eventStore.append(
            try TrainingEventFixture.make(
                localUserID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                deviceID: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
            )
        )
        let before = try await eventStore.allEvents()
        XCTAssertEqual(before.count, 1)

        // Adopt appendix G — the hero opens 32o from the button, a deviation the
        // shipped pack has something to say about — through the import path.
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
        let keyNodes = try await coordinator.analyze(identity: hand.source.identity)

        // The analysis actually did something — "no event" was not achieved by
        // returning nothing.
        XCTAssertFalse(keyNodes.isEmpty, "附录 G 含偏离，分析应产出关键节点")
        XCTAssertTrue(
            keyNodes.contains { $0.reason == .deviation },
            "附录 G 的 32o 开池应被标为偏离"
        )

        // And the event store is byte-for-byte what it was.
        let after = try await eventStore.allEvents()
        XCTAssertEqual(after.count, before.count)
        XCTAssertEqual(after, before)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }
}
