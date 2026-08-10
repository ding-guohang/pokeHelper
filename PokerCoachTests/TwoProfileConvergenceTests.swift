import Foundation
import TrainingDomain
import XCTest
@testable import PokerCoach

/// Two installations of the same account must converge on one history and
/// reduce it to the same ability profile, regardless of who trained what first.
@MainActor
final class TwoProfileConvergenceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "Convergence-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testTwoDevicesConvergeOnTheSameDeduplicatedHistory() async throws {
        let server = SharedServerDouble()
        let phone = try Device(name: "phone", root: root, server: server)
        let tablet = try Device(name: "tablet", root: root, server: server)

        let phoneEvent = ContractEventFixture.make(id: UUID())
        let tabletEvent = ContractEventFixture.make(id: UUID())
        try await phone.store.append(phoneEvent)
        try await tablet.store.append(tabletEvent)

        // Each device uploads, then both pull what the other wrote.
        await phone.engine.synchronize(reason: .decisionCompleted)
        await tablet.engine.synchronize(reason: .decisionCompleted)
        await phone.engine.synchronize(reason: .foreground)

        let phoneHistory = try await phone.store.allEvents().map(\.id).sorted()
        let tabletHistory = try await tablet.store.allEvents().map(\.id).sorted()

        XCTAssertEqual(phoneHistory, [phoneEvent.id, tabletEvent.id].sorted())
        XCTAssertEqual(phoneHistory, tabletHistory)
    }

    func testConvergedHistoryReducesToTheSameProfileOnBothDevices() async throws {
        let server = SharedServerDouble()
        let phone = try Device(name: "phone", root: root, server: server)
        let tablet = try Device(name: "tablet", root: root, server: server)

        for _ in 0 ..< 3 {
            try await phone.store.append(ContractEventFixture.make(id: UUID()))
        }
        try await tablet.store.append(ContractEventFixture.make(id: UUID()))

        await phone.engine.synchronize(reason: .decisionCompleted)
        await tablet.engine.synchronize(reason: .decisionCompleted)
        await phone.engine.synchronize(reason: .foreground)

        let reducer = PlayerModelReducer()
        let phoneModel = reducer.reduce(events: try await phone.store.allEvents())
        let tabletModel = reducer.reduce(events: try await tablet.store.allEvents())

        // The reduction is deterministic over the deduplicated union, so both
        // devices must agree on every dimension and every sample count.
        XCTAssertEqual(phoneModel, tabletModel)
        let samples = phoneModel.abilities.values.reduce(0) { $0 + $1.sampleCount }
        XCTAssertEqual(samples, 4)
    }

    // Syncing repeatedly must be a no-op once converged.
    func testRepeatedSynchronizationIsStable() async throws {
        let server = SharedServerDouble()
        let phone = try Device(name: "phone", root: root, server: server)
        try await phone.store.append(ContractEventFixture.make())

        for _ in 0 ..< 3 {
            await phone.engine.synchronize(reason: .foreground)
        }

        let events = try await phone.store.allEvents()
        XCTAssertEqual(events.count, 1)
    }
}

@MainActor
private struct Device {
    let store: SyncTrackingTrainingEventStore
    let engine: SyncEngine

    init(name: String, root: URL, server: SharedServerDouble) throws {
        let directory = root.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let underlying = try FileTrainingEventStore(directory: directory)
        let outbox = try FileOutboxStore(directory: directory)
        let state = try FileSyncStateStore(directory: directory)
        store = SyncTrackingTrainingEventStore(underlying: underlying, outbox: outbox)
        engine = SyncEngine(
            store: store,
            outbox: outbox,
            state: state,
            api: DeviceSyncAPI(server: server),
            authorizer: SessionAuthorizer(
                store: ConvergenceCredentialStore(),
                api: StubAccountAPI()
            ),
            now: { Date(timeIntervalSince1970: 1_786_200_000) }
        )
    }
}

/// An in-memory stand-in for the sync service: one ordered log per account,
/// with the same monotonic-sequence and idempotency semantics the MySQL store
/// enforces.
private final class SharedServerDouble: @unchecked Sendable {
    private let mutex = NSLock()
    private var events: [(sequence: UInt64, event: TrainingEvent)] = []
    private var acceptedIDs: Set<UUID> = []

    func upload(_ events: [TrainingEvent]) -> UploadAcknowledgement {
        mutex.withLock {
            for event in events where !acceptedIDs.contains(event.id) {
                acceptedIDs.insert(event.id)
                self.events.append((UInt64(self.events.count + 1), event))
            }
            return UploadAcknowledgement(
                acceptedEventIDs: events.map(\.id),
                checkpoint: UInt64(self.events.count)
            )
        }
    }

    func pull(after checkpoint: UInt64, limit: Int) -> RemoteEventPage {
        mutex.withLock {
            let pending = events.filter { $0.sequence > checkpoint }
            let page = Array(pending.prefix(limit))
            return RemoteEventPage(
                events: page.map(\.event),
                checkpoint: page.last?.sequence ?? checkpoint,
                hasMore: pending.count > page.count
            )
        }
    }
}

private struct DeviceSyncAPI: SyncAPI {
    let server: SharedServerDouble

    func upload(
        _ batch: UploadBatch,
        accessToken: String
    ) async throws -> UploadAcknowledgement {
        let decoded = try SyncEventCoding.decoder().decode(
            UploadBodyDTO.self,
            from: batch.body
        )
        return server.upload(decoded.events)
    }

    func pull(
        after checkpoint: UInt64,
        limit: Int,
        accessToken: String
    ) async throws -> RemoteEventPage {
        server.pull(after: checkpoint, limit: limit)
    }

    private struct UploadBodyDTO: Decodable {
        let events: [TrainingEvent]
    }
}

private struct ConvergenceCredentialStore: CredentialStore {
    func loadActive() async throws -> StoredSession? { .fixture() }
    func saveActive(_ session: StoredSession) async throws {}
    func replaceActive(expectedRefreshToken: String, with session: StoredSession) async throws {}
    func clearActive() async throws {}
    func moveRefreshToPendingRevocation() async throws {}
    func loadPendingRevocation() async throws -> PendingSessionRevocation? { nil }
    func clearPendingRevocation() async throws {}
}
