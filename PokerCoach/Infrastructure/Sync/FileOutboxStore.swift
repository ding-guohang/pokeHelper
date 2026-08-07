import Foundation
import TrainingDomain

/// Recoverable upload queue.
///
/// State is replaced atomically, so a crash leaves either the previous state or
/// the new one, never a partial file. An in-flight batch is kept verbatim until
/// the server acknowledges it, which is what makes a retry idempotent.
actor FileOutboxStore: OutboxStore {
    private struct State: Codable, Sendable {
        var queued: [UUID]
        var inFlight: OutboxBatch?
    }

    private let file: URL
    private let makeUUID: @Sendable () -> UUID
    private let now: @Sendable () -> Date

    init(
        directory: URL,
        makeUUID: @escaping @Sendable () -> UUID = UUID.init,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        file = directory.appending(path: "outbox.json", directoryHint: .notDirectory)
        self.makeUUID = makeUUID
        self.now = now
    }

    func pendingEventIDs() throws -> Set<UUID> {
        let current = try state()
        return Set(current.queued).union(current.inFlight?.eventIDs ?? [])
    }

    func enqueue(_ eventID: UUID) throws {
        var current = try state()
        guard !current.queued.contains(eventID) else {
            return
        }
        guard !(current.inFlight?.eventIDs.contains(eventID) ?? false) else {
            return
        }
        current.queued.append(eventID)
        try save(current)
    }

    func inFlightBatch() throws -> OutboxBatch? {
        try state().inFlight
    }

    /// Returns the batch to send, reusing the existing in-flight batch when one
    /// survived a crash.
    ///
    /// Events are resolved into the batch before it is persisted, so a later
    /// retry replays stored bytes and never needs to look events up again.
    func beginBatch(
        eventsByID: [UUID: TrainingEvent],
        limit: Int
    ) throws -> OutboxBatch? {
        var current = try state()
        if let existing = current.inFlight {
            return existing
        }
        guard limit > 0 else {
            return nil
        }

        let selected = current.queued.prefix(limit).compactMap { id in
            eventsByID[id].map { (id, $0) }
        }
        guard !selected.isEmpty else {
            return nil
        }

        let body = try UploadEncoding.canonicalBody(events: selected.map(\.1))
        let batch = OutboxBatch(
            idempotencyKey: makeUUID(),
            eventIDs: selected.map(\.0),
            requestBody: body,
            requestHash: UploadEncoding.hash(body),
            createdAt: now(),
            state: .inFlight
        )

        current.queued.removeAll { batch.eventIDs.contains($0) }
        current.inFlight = batch
        try save(current)
        return batch
    }

    func acknowledge(_ batch: OutboxBatch, eventIDs: Set<UUID>) throws {
        var current = try state()
        guard current.inFlight?.idempotencyKey == batch.idempotencyKey else {
            return
        }
        // Anything the server did not confirm goes back to the queue rather
        // than being dropped.
        let unconfirmed = batch.eventIDs.filter { !eventIDs.contains($0) }
        current.inFlight = nil
        current.queued.insert(contentsOf: unconfirmed, at: 0)
        try save(current)
    }

    /// Re-queues events that exist locally but are neither acknowledged nor
    /// already queued. This repairs the gap left when the app dies between
    /// writing an event and enqueuing it.
    func reconcile(
        localEventIDs: [UUID],
        acknowledged: Set<UUID>
    ) throws -> [UUID] {
        let known = try pendingEventIDs().union(acknowledged)
        let missing = localEventIDs.filter { !known.contains($0) }
        guard !missing.isEmpty else {
            return []
        }
        var current = try state()
        current.queued.append(contentsOf: missing)
        try save(current)
        return missing
    }

    private func state() throws -> State {
        guard
            let data = try? Data(contentsOf: file),
            let decoded = try? JSONDecoder().decode(State.self, from: data)
        else {
            return State(queued: [], inFlight: nil)
        }
        return decoded
    }

    private func save(_ state: State) throws {
        try JSONEncoder().encode(state).write(to: file, options: .atomic)
    }
}
