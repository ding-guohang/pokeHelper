import Foundation
import TrainingDomain
import TrainingPersistence
import XCTest
@testable import PokerCoach

@MainActor
final class SyncEngineTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(
            path: "SyncEngine-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // Upload before pull: this device's events must already be on the server
    // when the merged history comes back, so the reduction sees one set.
    func testSynchronizeReconcilesThenUploadsThenPulls() async throws {
        let harness = try Harness(directory: directory)
        try await harness.underlying.append(try ContractEventFixture.make())

        await harness.engine.synchronize(reason: .launch)

        XCTAssertEqual(harness.api.calls, ["upload", "pull"])
        let status = await harness.engine.status()
        guard case .upToDate = status else {
            return XCTFail("status = \(status), want upToDate")
        }
    }

    // An event that reached the log but never the queue is uploaded after
    // reconciliation, without any explicit repair step by the caller.
    func testAnUnqueuedLocalEventIsStillUploaded() async throws {
        let harness = try Harness(directory: directory)
        let orphan = try ContractEventFixture.make()
        try await harness.underlying.append(orphan)

        await harness.engine.synchronize(reason: .launch)

        XCTAssertEqual(harness.api.uploadedEventIDs, [orphan.id])
    }

    // A lost response must be retried with the identical bytes and key, or the
    // server would treat the replay as a new batch.
    func testALostResponseRetriesTheExactSameBytesAndKey() async throws {
        let harness = try Harness(directory: directory)
        try await harness.underlying.append(try ContractEventFixture.make())
        harness.api.uploadFailures = 1

        await harness.engine.synchronize(reason: .launch)
        let firstAttempt = harness.api.uploadAttempts

        await harness.engine.synchronize(reason: .manualRetry)

        XCTAssertEqual(firstAttempt.count, 1)
        XCTAssertEqual(harness.api.uploadAttempts.count, 2)
        XCTAssertEqual(
            harness.api.uploadAttempts[0].idempotencyKey,
            harness.api.uploadAttempts[1].idempotencyKey
        )
        XCTAssertEqual(
            harness.api.uploadAttempts[0].body,
            harness.api.uploadAttempts[1].body
        )
    }

    func testRemoteEventsAreMergedWithoutBeingUploadedBack() async throws {
        let harness = try Harness(directory: directory)
        let remote = try ContractEventFixture.make(id: UUID())
        harness.api.remotePages = [
            RemoteEventPage(events: [remote], checkpoint: 5, hasMore: false),
        ]

        await harness.engine.synchronize(reason: .launch)

        let events = try await harness.underlying.allEvents()
        XCTAssertEqual(events.map(\.id), [remote.id])
        XCTAssertTrue(
            harness.api.uploadedEventIDs.isEmpty,
            "a pulled event must not be uploaded back"
        )
        let pending = try await harness.outbox.pendingEventIDs()
        XCTAssertTrue(pending.isEmpty)
    }

    func testPagedPullMergesEveryPageAndAdvancesTheCheckpointOnce() async throws {
        let harness = try Harness(directory: directory)
        let first = try ContractEventFixture.make(id: UUID())
        let second = try ContractEventFixture.make(id: UUID())
        harness.api.remotePages = [
            RemoteEventPage(events: [first], checkpoint: 1, hasMore: true),
            RemoteEventPage(events: [second], checkpoint: 2, hasMore: false),
        ]

        await harness.engine.synchronize(reason: .launch)

        let events = try await harness.underlying.allEvents()
        XCTAssertEqual(Set(events.map(\.id)), [first.id, second.id])
        let checkpoint = try await harness.state.checkpoint()
        XCTAssertEqual(checkpoint, 2)
    }

    // An interrupted pull must replay its page rather than skip it.
    func testAFailedPullLeavesTheCheckpointWhereItWas() async throws {
        let harness = try Harness(directory: directory)
        harness.api.pullFailures = 1

        await harness.engine.synchronize(reason: .launch)

        let checkpoint = try await harness.state.checkpoint()
        XCTAssertEqual(checkpoint, 0)
        let status = await harness.engine.status()
        guard case .failed = status else {
            return XCTFail("status = \(status), want failed")
        }
    }

    func testADuplicateRemoteEventDoesNotDuplicateHistory() async throws {
        let harness = try Harness(directory: directory)
        let event = try ContractEventFixture.make()
        try await harness.underlying.append(event)
        harness.api.remotePages = [
            RemoteEventPage(events: [event], checkpoint: 1, hasMore: false),
        ]

        await harness.engine.synchronize(reason: .launch)

        let events = try await harness.underlying.allEvents()
        XCTAssertEqual(events.count, 1)
    }

    // Sync failing must never stop the user training.
    func testAFailedSynchronizationKeepsLocalHistoryIntact() async throws {
        let harness = try Harness(directory: directory)
        let local = try ContractEventFixture.make()
        try await harness.underlying.append(local)
        harness.api.uploadFailures = 1

        await harness.engine.synchronize(reason: .launch)

        let events = try await harness.underlying.allEvents()
        XCTAssertEqual(events.map(\.id), [local.id])
        let pending = try await harness.outbox.pendingEventIDs()
        XCTAssertEqual(pending, [local.id], "the event stays queued for the next attempt")
    }

    func testNetworkRecoveryUploadsWhatWasPending() async throws {
        let harness = try Harness(directory: directory)
        try await harness.underlying.append(try ContractEventFixture.make())
        harness.api.uploadFailures = 1
        await harness.engine.synchronize(reason: .launch)

        await harness.engine.synchronize(reason: .networkRestored)

        let status = await harness.engine.status()
        guard case .upToDate = status else {
            return XCTFail("status = \(status), want upToDate after recovery")
        }
        let pending = try await harness.outbox.pendingEventIDs()
        XCTAssertTrue(pending.isEmpty)
    }

    func testHistoryChangeIsPublishedOnlyWhenSomethingChanged() async throws {
        let counter = ChangeCounter()
        let harness = try Harness(directory: directory) { await counter.increment() }
        try await harness.underlying.append(try ContractEventFixture.make())

        await harness.engine.synchronize(reason: .launch)
        let afterUpload = await counter.value

        await harness.engine.synchronize(reason: .foreground)
        let afterIdle = await counter.value

        XCTAssertEqual(afterUpload, 1)
        XCTAssertEqual(afterIdle, 1, "an idle run must not churn the UI")
    }
}

private actor ChangeCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

@MainActor
private struct Harness {
    let underlying: FileTrainingEventStore
    let outbox: FileOutboxStore
    let state: FileSyncStateStore
    let api: SyncAPIDouble
    let engine: SyncEngine

    init(
        directory: URL,
        onHistoryChanged: @escaping @Sendable () async -> Void = {}
    ) throws {
        underlying = try FileTrainingEventStore(directory: directory)
        outbox = try FileOutboxStore(directory: directory)
        state = try FileSyncStateStore(directory: directory)
        api = SyncAPIDouble()

        let store = SyncTrackingTrainingEventStore(underlying: underlying, outbox: outbox)
        let credentials = KeychainCredentialStore(vault: InMemoryVault())
        engine = SyncEngine(
            store: store,
            outbox: outbox,
            state: state,
            api: api,
            authorizer: SessionAuthorizer(
                store: AlwaysAuthorizedCredentialStore(),
                api: StubAccountAPI()
            ),
            now: { Date(timeIntervalSince1970: 1_786_200_000) },
            onHistoryChanged: onHistoryChanged
        )
        _ = credentials
    }
}

private struct AlwaysAuthorizedCredentialStore: CredentialStore {
    func loadActive() async throws -> StoredSession? { .fixture() }
    func saveActive(_ session: StoredSession) async throws {}
    func replaceActive(expectedRefreshToken: String, with session: StoredSession) async throws {}
    func clearActive() async throws {}
    func moveRefreshToPendingRevocation() async throws {}
    func loadPendingRevocation() async throws -> PendingSessionRevocation? { nil }
    func clearPendingRevocation() async throws {}
}


private final class SyncAPIDouble: SyncAPI, @unchecked Sendable {
    private(set) var calls: [String] = []
    private(set) var uploadAttempts: [UploadBatch] = []
    private(set) var uploadedEventIDs: [UUID] = []
    var remotePages: [RemoteEventPage] = []
    var uploadFailures = 0
    var pullFailures = 0

    private var pullIndex = 0

    func upload(
        _ batch: UploadBatch,
        accessToken: String
    ) async throws -> UploadAcknowledgement {
        uploadAttempts.append(batch)
        if uploadFailures > 0 {
            uploadFailures -= 1
            throw APIError.offline
        }
        calls.append("upload")

        let decoded = try JSONDecoder().decode(UploadBodyProbe.self, from: batch.body)
        let ids = decoded.events.map(\.id)
        uploadedEventIDs.append(contentsOf: ids)
        return UploadAcknowledgement(acceptedEventIDs: ids, checkpoint: UInt64(ids.count))
    }

    func pull(
        after checkpoint: UInt64,
        limit: Int,
        accessToken: String
    ) async throws -> RemoteEventPage {
        if pullFailures > 0 {
            pullFailures -= 1
            throw APIError.offline
        }
        calls.append("pull")
        guard pullIndex < remotePages.count else {
            return RemoteEventPage(events: [], checkpoint: checkpoint, hasMore: false)
        }
        let page = remotePages[pullIndex]
        pullIndex += 1
        return page
    }

    private struct UploadBodyProbe: Decodable {
        struct Event: Decodable {
            let id: UUID
        }

        let events: [Event]
    }
}

/// A batch the server calls too large must be split, not discarded: the events
/// are fine, only the request size is wrong.
@MainActor
final class OversizedBatchTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(
            path: "Oversized-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testAnOversizedBatchIsHalvedUntilItFitsAndNoEventIsLost() async throws {
        let underlying = try FileTrainingEventStore(directory: directory)
        let outbox = try FileOutboxStore(directory: directory)
        let state = try FileSyncStateStore(directory: directory)
        let store = SyncTrackingTrainingEventStore(underlying: underlying, outbox: outbox)

        let events = try (0 ..< 4).map { _ in try ContractEventFixture.make(id: UUID()) }
        for event in events {
            try await store.append(event)
        }

        let api = SizeLimitedSyncAPI(maximumEventsPerBatch: 1)
        let engine = SyncEngine(
            store: store,
            outbox: outbox,
            state: state,
            api: api,
            authorizer: SessionAuthorizer(
                store: OversizedCredentialStore(),
                api: StubAccountAPI()
            ),
            now: { Date(timeIntervalSince1970: 1_786_200_000) }
        )

        await engine.synchronize(reason: .launch)

        let status = await engine.status()
        guard case .upToDate = status else {
            return XCTFail("status = \(status), want upToDate")
        }
        XCTAssertEqual(
            Set(api.acceptedEventIDs),
            Set(events.map(\.id)),
            "every event must arrive, just in smaller batches"
        )
        let pending = try await outbox.pendingEventIDs()
        XCTAssertTrue(pending.isEmpty)
        let quarantined = try await outbox.quarantinedEventIDs()
        XCTAssertTrue(quarantined.isEmpty, "an oversized batch must not be discarded")
    }
}

/// Rejects any batch above a fixed event count, the way the server rejects one
/// above its byte limit.
private final class SizeLimitedSyncAPI: SyncAPI, @unchecked Sendable {
    private let maximumEventsPerBatch: Int
    private(set) var acceptedEventIDs: [UUID] = []

    init(maximumEventsPerBatch: Int) {
        self.maximumEventsPerBatch = maximumEventsPerBatch
    }

    func upload(
        _ batch: UploadBatch,
        accessToken: String
    ) async throws -> UploadAcknowledgement {
        let decoded = try JSONDecoder().decode(Probe.self, from: batch.body)
        let ids = decoded.events.map(\.id)
        if ids.count > maximumEventsPerBatch {
            throw APIError.batchTooLarge
        }
        acceptedEventIDs.append(contentsOf: ids)
        return UploadAcknowledgement(
            acceptedEventIDs: ids,
            checkpoint: UInt64(acceptedEventIDs.count)
        )
    }

    func pull(
        after checkpoint: UInt64,
        limit: Int,
        accessToken: String
    ) async throws -> RemoteEventPage {
        RemoteEventPage(events: [], checkpoint: checkpoint, hasMore: false)
    }

    private struct Probe: Decodable {
        struct Event: Decodable {
            let id: UUID
        }

        let events: [Event]
    }
}

private struct OversizedCredentialStore: CredentialStore {
    func loadActive() async throws -> StoredSession? { .fixture() }
    func saveActive(_ session: StoredSession) async throws {}
    func replaceActive(expectedRefreshToken: String, with session: StoredSession) async throws {}
    func clearActive() async throws {}
    func moveRefreshToPendingRevocation() async throws {}
    func loadPendingRevocation() async throws -> PendingSessionRevocation? { nil }
    func clearPendingRevocation() async throws {}
}
