import Foundation
import TrainingDomain

/// Drives one synchronization cycle at a time.
///
/// Being an actor is the serialization mechanism: launch, foreground, and a
/// finished decision can all fire at once, and overlapping runs would upload
/// the same batch twice under different keys.
actor SyncEngine {
    private let store: SyncTrackingTrainingEventStore
    private let outbox: FileOutboxStore
    private let state: FileSyncStateStore
    private let api: any SyncAPI
    private let authorizer: SessionAuthorizer
    private let now: @Sendable () -> Date
    private let onHistoryChanged: @Sendable () async -> Void

    private var currentStatus: SyncStatus = .idle

    /// Pull one page at a time. The checkpoint only advances after a page has
    /// been fully merged, so an interrupted pull replays that page instead of
    /// skipping it.
    private let pullLimit = 100
    private let uploadLimit = 100

    /// A batch the server refuses is retried this many times before being set
    /// aside. Retrying forever would block every later event and, because
    /// upload runs before pull, would also stop this device receiving anything.
    private let maxBatchRejections = 3

    init(
        store: SyncTrackingTrainingEventStore,
        outbox: FileOutboxStore,
        state: FileSyncStateStore,
        api: any SyncAPI,
        authorizer: SessionAuthorizer,
        now: @escaping @Sendable () -> Date = Date.init,
        onHistoryChanged: @escaping @Sendable () async -> Void = {}
    ) {
        self.store = store
        self.outbox = outbox
        self.state = state
        self.api = api
        self.authorizer = authorizer
        self.now = now
        self.onHistoryChanged = onHistoryChanged
    }

    func status() -> SyncStatus {
        currentStatus
    }

    func retry() async {
        await synchronize(reason: .manualRetry)
    }

    /// Runs reconcile, upload, then pull.
    ///
    /// Reconciling first re-queues anything a crash left unqueued. Uploading
    /// before pulling means this device's own events are already on the server
    /// when the merged history comes back, so the reduction sees one
    /// consistent set. A failure at any step leaves training untouched.
    func synchronize(reason: SyncReason) async {
        currentStatus = .syncing
        do {
            let acknowledged = try await state.acknowledgedEventIDs()
            _ = try await store.reconcileOutbox(acknowledged: acknowledged)

            var changed = try await uploadPending()
            changed = try await pullRemote() || changed

            currentStatus = .upToDate(at: now())
            if changed {
                await onHistoryChanged()
            }
        } catch {
            currentStatus = .failed(message: Self.message(for: error))
        }
    }

    private func uploadPending() async throws -> Bool {
        var uploadedAnything = false
        // Halved whenever the server says a batch is too large. The events are
        // fine; only the request size is wrong, so the fix is to send fewer at
        // a time rather than to drop any.
        var limit = uploadLimit
        while true {
            let eventsByID = try await currentEventsByID()
            guard let batch = try await outbox.beginBatch(
                eventsByID: eventsByID,
                limit: limit
            ) else {
                return uploadedAnything
            }

            let acknowledgement: UploadAcknowledgement
            do {
                acknowledgement = try await authorizer.authorize { accessToken in
                    try await self.api.upload(
                        UploadBatch(
                            idempotencyKey: batch.idempotencyKey,
                            body: batch.requestBody
                        ),
                        accessToken: accessToken
                    )
                }
            } catch APIError.batchTooLarge where batch.eventIDs.count > 1 {
                limit = max(1, batch.eventIDs.count / 2)
                try await outbox.discardInFlightBatch()
                continue
            } catch let error as APIError where error.isServerRefusal {
                // The server judged this batch invalid, so resending the same
                // bytes will always fail the same way.
                let setAside = try await outbox.quarantineRejectedBatch(
                    batch,
                    maxRejections: maxBatchRejections
                )
                if setAside.isEmpty {
                    throw error
                }
                continue
            }

            try await outbox.acknowledge(batch, eventIDs: Set(acknowledgement.acceptedEventIDs))
            try await state.markAcknowledged(Set(acknowledgement.acceptedEventIDs))
            uploadedAnything = true
        }
    }

    private func pullRemote() async throws -> Bool {
        var mergedAnything = false
        while true {
            let checkpoint = try await state.checkpoint()
            let page = try await authorizer.authorize { accessToken in
                try await self.api.pull(
                    after: checkpoint,
                    limit: self.pullLimit,
                    accessToken: accessToken
                )
            }

            for event in page.events {
                // Remote events are appended without being queued; the server
                // already has them.
                try await store.appendRemote(event)
                mergedAnything = true
            }

            // Advancing only after the whole page merged is what makes an
            // interrupted pull replay rather than skip.
            try await state.setCheckpoint(page.checkpoint)

            if !page.hasMore {
                return mergedAnything
            }
        }
    }

    private func currentEventsByID() async throws -> [UUID: TrainingEvent] {
        let events = try await store.allEvents()
        return Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func message(for error: Error) -> String {
        switch error {
        case let error as APIError:
            error.recoverySuggestion
        case let error as CredentialStoreError:
            error.recoverySuggestion
        default:
            "同步未能完成，训练记录仍保存在本机，稍后会自动重试。"
        }
    }
}
