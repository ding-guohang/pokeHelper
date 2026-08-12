import Foundation
import HandHistory
import HandHistoryPersistence
import TrainingDomain
import TrainingPersistence
import XCTest
@testable import PokerCoach

/// The slice's load-bearing test: importing and adopting a hand never writes a
/// training event.
///
/// A personal hand is not a graded answer. Nobody authored frequencies for a
/// stranger's hand, and importing it asks for no confidence and produces no
/// grade. An event manufactured from an import would be a sample the ability
/// profile cannot tell from a real answer, inflating counts and satisfying the
/// mastery rules' repetition signal for a spot the user never actually decided.
///
/// `HandHistoryPersistence` cannot reach a `TrainingEvent` at all, so the
/// structural half of the guarantee is free. This test guards the other half:
/// the app-layer coordinator *holds* the event store — it is the type that could
/// write one — and driving a real import through it leaves the store untouched.
final class HandImportEventIsolationTests: XCTestCase {
    @MainActor
    func testImportingAndAcceptingAHandWritesNoTrainingEvent() async throws {
        // A non-empty event store. Comparing an empty store to an empty store is
        // satisfied by an app that cannot write events at all, which is not the
        // claim; the claim is that this store is untouched.
        let eventStore = try FileTrainingEventStore(directory: temporaryDirectory())
        try await eventStore.append(
            try TrainingEventFixture.make(
                localUserID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                deviceID: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
            )
        )
        let before = try await eventStore.allEvents()
        XCTAssertEqual(before.count, 1)

        // An empty library, so "count increased by one" measures an import that
        // actually happened rather than a store that was already full.
        let libraryStore = try FileHandLibraryStore(directory: temporaryDirectory())
        let handsBefore = try await libraryStore.hands()
        XCTAssertEqual(handsBefore.count, 0)

        // Driven through the app-layer coordinator, which holds the event store
        // and is therefore the type that could write to it.
        let coordinator = HandImportCoordinator(
            libraryStore: libraryStore,
            eventStore: eventStore
        )
        let outcome = try await coordinator.importAndAccept(text: HandImportFixtureText.appendixA)

        // The import succeeded and the hand is on disk — "no event" must not have
        // been achieved by doing nothing.
        guard case .accepted = outcome else {
            return XCTFail("干净牌谱应当被采纳，实际结果：\(outcome)")
        }
        let handsAfter = try await libraryStore.hands()
        XCTAssertEqual(handsAfter.count, 1, "采纳后牌库应当多出一手")

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
