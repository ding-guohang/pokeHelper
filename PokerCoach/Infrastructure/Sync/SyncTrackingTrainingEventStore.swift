import Foundation
import TrainingDomain

/// Wraps the local event store so every locally created event is also queued
/// for upload.
///
/// The local write happens first and its result is what the caller sees. If
/// enqueuing then fails, the event is still safely recorded and reconciliation
/// picks it up on the next launch — losing an upload is recoverable, losing a
/// hand the user actually trained is not.
actor SyncTrackingTrainingEventStore: TrainingEventStore {
    private let underlying: any TrainingEventStore
    private let outbox: FileOutboxStore

    init(underlying: any TrainingEventStore, outbox: FileOutboxStore) {
        self.underlying = underlying
        self.outbox = outbox
    }

    func append(_ event: TrainingEvent) async throws {
        try await underlying.append(event)
        try? await outbox.enqueue(event.id)
    }

    /// Stores an event pulled from another device.
    ///
    /// Remote events are never enqueued: the server already has them, and
    /// uploading them back would create a pointless round trip.
    func appendRemote(_ event: TrainingEvent) async throws {
        try await underlying.append(event)
    }

    func allEvents() async throws -> [TrainingEvent] {
        try await underlying.allEvents()
    }

    func events(after checkpoint: UUID?) async throws -> [TrainingEvent] {
        try await underlying.events(after: checkpoint)
    }

    /// Re-queues local events the outbox has never seen.
    func reconcileOutbox(acknowledged: Set<UUID>) async throws -> [UUID] {
        let local = try await underlying.allEvents().map(\.id)
        return try await outbox.reconcile(localEventIDs: local, acknowledged: acknowledged)
    }
}
