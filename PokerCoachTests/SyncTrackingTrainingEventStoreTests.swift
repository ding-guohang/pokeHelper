import Foundation
import TrainingDomain
import XCTest
@testable import PokerCoach

@MainActor
final class SyncTrackingTrainingEventStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(
            path: "SyncTracking-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLocalAppendWritesTheEventAndQueuesIt() async throws {
        let (store, outbox, _) = try makeStore()
        let event = try ContractEventFixture.make()

        try await store.append(event)

        let events = try await store.allEvents()
        XCTAssertEqual(events.map(\.id), [event.id])
        let pending = try await outbox.pendingEventIDs()
        XCTAssertEqual(pending, [event.id])
    }

    // Recording the hand is what matters; queuing it is recoverable. A failed
    // enqueue must therefore never fail the append.
    func testAFailedEnqueueStillKeepsTheEvent() async throws {
        let underlying = try FileTrainingEventStore(directory: directory)
        let unwritableOutbox = try FileOutboxStore(
            directory: directory.appending(path: "outbox", directoryHint: .isDirectory)
        )
        // Replace the outbox directory with a file so its writes fail.
        try? FileManager.default.removeItem(
            at: directory.appending(path: "outbox", directoryHint: .isDirectory)
        )
        try Data("blocked".utf8).write(
            to: directory.appending(path: "outbox", directoryHint: .notDirectory)
        )
        let store = SyncTrackingTrainingEventStore(
            underlying: underlying,
            outbox: unwritableOutbox
        )
        let event = try ContractEventFixture.make()

        try await store.append(event)

        let events = try await store.allEvents()
        XCTAssertEqual(events.map(\.id), [event.id], "the hand must survive a queue failure")
    }

    // A pulled event is already on the server. Enqueuing it would upload it
    // straight back.
    func testAppendRemoteNeverEnqueues() async throws {
        let (store, outbox, _) = try makeStore()
        let event = try ContractEventFixture.make()

        try await store.appendRemote(event)

        let events = try await store.allEvents()
        XCTAssertEqual(events.map(\.id), [event.id])
        let pending = try await outbox.pendingEventIDs()
        XCTAssertTrue(pending.isEmpty)
    }

    func testDuplicateAppendStaysASingleEvent() async throws {
        let (store, outbox, _) = try makeStore()
        let event = try ContractEventFixture.make()

        try await store.append(event)
        try await store.append(event)

        let events = try await store.allEvents()
        XCTAssertEqual(events.count, 1)
        let pending = try await outbox.pendingEventIDs()
        XCTAssertEqual(pending, [event.id])
    }

    // Corruption must stay a typed, line-numbered failure so the app can offer
    // the same backup-and-repair recovery M1A shipped.
    func testCorruptedHistoryStillReportsItsLineNumber() async throws {
        let (store, _, _) = try makeStore()
        try await store.append(try ContractEventFixture.make())
        let log = directory.appending(
            path: "training-events.jsonl",
            directoryHint: .notDirectory
        )
        let existing = try String(contentsOf: log, encoding: .utf8)
        try (existing + "not json\n").write(to: log, atomically: true, encoding: .utf8)

        do {
            _ = try await store.allEvents()
            XCTFail("corrupted history must not decode")
        } catch {
            XCTAssertEqual(error as? TrainingEventStoreError, .corruptedLine(2))
        }
    }

    private func makeStore() throws -> (
        SyncTrackingTrainingEventStore,
        FileOutboxStore,
        FileSyncStateStore
    ) {
        let underlying = try FileTrainingEventStore(directory: directory)
        let outbox = try FileOutboxStore(directory: directory)
        let state = try FileSyncStateStore(directory: directory)
        return (
            SyncTrackingTrainingEventStore(underlying: underlying, outbox: outbox),
            outbox,
            state
        )
    }
}

@MainActor
final class OutboxReconciliationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(
            path: "Reconcile-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // The crash window: an event reached the log but never reached the queue.
    // Reconciliation is what makes that recoverable.
    func testReconciliationQueuesLocalEventsThatNeverReachedTheOutbox() async throws {
        let underlying = try FileTrainingEventStore(directory: directory)
        let orphan = try ContractEventFixture.make()
        try await underlying.append(orphan)

        let outbox = try FileOutboxStore(directory: directory)
        let store = SyncTrackingTrainingEventStore(underlying: underlying, outbox: outbox)

        let requeued = try await store.reconcileOutbox(acknowledged: [])

        XCTAssertEqual(requeued, [orphan.id])
        let pending = try await outbox.pendingEventIDs()
        XCTAssertEqual(pending, [orphan.id])
    }

    func testReconciliationIsAllLocalMinusAcknowledgedMinusQueued() async throws {
        let underlying = try FileTrainingEventStore(directory: directory)
        let acknowledged = try ContractEventFixture.make(id: UUID())
        let queued = try ContractEventFixture.make(id: UUID())
        let orphan = try ContractEventFixture.make(id: UUID())
        for event in [acknowledged, queued, orphan] {
            try await underlying.append(event)
        }

        let outbox = try FileOutboxStore(directory: directory)
        try await outbox.enqueue(queued.id)
        let store = SyncTrackingTrainingEventStore(underlying: underlying, outbox: outbox)

        let requeued = try await store.reconcileOutbox(acknowledged: [acknowledged.id])

        XCTAssertEqual(requeued, [orphan.id])
        let pending = try await outbox.pendingEventIDs()
        XCTAssertEqual(pending, [queued.id, orphan.id])
    }

    func testReconciliationIsIdempotent() async throws {
        let underlying = try FileTrainingEventStore(directory: directory)
        let orphan = try ContractEventFixture.make()
        try await underlying.append(orphan)
        let outbox = try FileOutboxStore(directory: directory)
        let store = SyncTrackingTrainingEventStore(underlying: underlying, outbox: outbox)

        _ = try await store.reconcileOutbox(acknowledged: [])
        let second = try await store.reconcileOutbox(acknowledged: [])

        XCTAssertTrue(second.isEmpty)
        let pending = try await outbox.pendingEventIDs()
        XCTAssertEqual(pending, [orphan.id])
    }

    func testCheckpointsOnlyMoveForward() async throws {
        let state = try FileSyncStateStore(directory: directory)

        try await state.setCheckpoint(10)
        try await state.setCheckpoint(4)

        let checkpoint = try await state.checkpoint()
        XCTAssertEqual(checkpoint, 10, "a late response must not rewind the pull cursor")
    }
}
