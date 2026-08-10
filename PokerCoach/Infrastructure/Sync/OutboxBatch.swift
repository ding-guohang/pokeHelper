import Foundation
import TrainingDomain

/// An upload attempt that has been handed to the network at least once.
///
/// A batch is immutable once created: its idempotency key, event order, encoded
/// bytes, and hash are fixed, so retrying after a crash replays exactly the
/// same request the server may already have accepted.
struct OutboxBatch: Codable, Sendable, Equatable {
    enum State: String, Codable, Sendable {
        case inFlight
        case acknowledged
    }

    let idempotencyKey: UUID
    let eventIDs: [UUID]
    let requestBody: Data
    let requestHash: String
    let createdAt: Date
    var state: State
    /// How many times the server has rejected this batch outright. A retryable
    /// failure (offline, timeout, 5xx) does not count.
    var rejectionCount: Int = 0
}

protocol OutboxStore: Sendable {
    func pendingEventIDs() async throws -> Set<UUID>
    func enqueue(_ eventID: UUID) async throws
    func beginBatch(
        eventsByID: [UUID: TrainingEvent],
        limit: Int
    ) async throws -> OutboxBatch?
    func acknowledge(_ batch: OutboxBatch, eventIDs: Set<UUID>) async throws
    func inFlightBatch() async throws -> OutboxBatch?
}

/// Canonical encoding of an upload request.
///
/// The bytes are the contract: the server hashes exactly what it receives, so
/// key order, whitespace, and the date format must match the Go side or every
/// idempotent retry would look like a different request.
enum UploadEncoding {
    static let schemaVersion = 1

    struct Body: Encodable, Sendable {
        let events: [TrainingEvent]
        let schemaVersion: Int
    }

    static func canonicalBody(events: [TrainingEvent]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(UploadDateFormat.string(from: date))
        }
        return try encoder.encode(Body(events: events, schemaVersion: schemaVersion))
    }

    static func hash(_ body: Data) -> String {
        SHA256Digest.hexString(of: body)
    }
}

/// UTC RFC 3339 with exactly millisecond precision and a `Z` suffix, matching
/// the canonical fixture the server verifies against.
enum UploadDateFormat {
    static func string(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: date
        )
        let milliseconds = Int((Double(parts.nanosecond ?? 0) / 1_000_000).rounded(.down))
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0,
            milliseconds
        )
    }
}
