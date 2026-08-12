import Foundation
import TrainingDomain
import XCTest
@testable import PokerCoach

@MainActor
final class FileOutboxStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(
            path: "Outbox-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // The upload bytes are the contract the server hashes. If Swift and Go
    // disagree by one byte, every idempotent retry looks like a new request.
    func testCanonicalEncodingMatchesTheSharedContractFixtureAndHash() throws {
        let event = try contractEvent()

        let body = try UploadEncoding.canonicalBody(events: [event])

        let fixtureURL = contractsDirectory.appending(
            path: "training-event-upload-v1.json",
            directoryHint: .notDirectory
        )
        let expectedBody = try Data(contentsOf: fixtureURL)
        XCTAssertEqual(
            String(decoding: body, as: UTF8.self),
            String(decoding: expectedBody, as: UTF8.self)
        )

        let hashURL = contractsDirectory.appending(
            path: "training-event-upload-v1.sha256",
            directoryHint: .notDirectory
        )
        let expectedHash = try String(contentsOf: hashURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(UploadEncoding.hash(body), expectedHash)
    }

    func testEnqueueingIsIdempotent() async throws {
        let store = try FileOutboxStore(directory: directory)
        let id = UUID()

        try await store.enqueue(id)
        try await store.enqueue(id)

        let pending = try await store.pendingEventIDs()
        XCTAssertEqual(pending, [id])
    }

    func testBeginBatchFreezesOrderBytesAndHash() async throws {
        let store = try FileOutboxStore(directory: directory)
        let events = [try contractEvent(), try contractEvent(id: UUID())]
        for event in events {
            try await store.enqueue(event.id)
        }

        let batch = try await store.beginBatch(
            eventsByID: Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) }),
            limit: 10
        )

        let unwrapped = try XCTUnwrap(batch)
        XCTAssertEqual(unwrapped.eventIDs, events.map(\.id))
        XCTAssertEqual(unwrapped.requestHash, UploadEncoding.hash(unwrapped.requestBody))
        XCTAssertEqual(unwrapped.state, .inFlight)
    }

    // A crash after sending must replay the identical request, so the server
    // recognizes it through the same idempotency key and body hash.
    func testAnInFlightBatchIsReplayedVerbatimAfterAReopen() async throws {
        let store = try FileOutboxStore(directory: directory)
        let event = try contractEvent()
        try await store.enqueue(event.id)
        let started = try await store.beginBatch(eventsByID: [event.id: event], limit: 10)
        let original = try XCTUnwrap(started)

        let reopened = try FileOutboxStore(directory: directory)
        let resumed = try await reopened.beginBatch(eventsByID: [:], limit: 10)
        let replayed = try XCTUnwrap(resumed)

        XCTAssertEqual(replayed.idempotencyKey, original.idempotencyKey)
        XCTAssertEqual(replayed.requestBody, original.requestBody)
        XCTAssertEqual(replayed.requestHash, original.requestHash)
        XCTAssertEqual(replayed.eventIDs, original.eventIDs)
    }

    func testAcknowledgementClearsConfirmedEventsAndRequeuesTheRest() async throws {
        let store = try FileOutboxStore(directory: directory)
        let confirmed = try contractEvent()
        let unconfirmed = try contractEvent(id: UUID())
        for event in [confirmed, unconfirmed] {
            try await store.enqueue(event.id)
        }
        let started = try await store.beginBatch(
            eventsByID: [confirmed.id: confirmed, unconfirmed.id: unconfirmed],
            limit: 10
        )
        let batch = try XCTUnwrap(started)

        try await store.acknowledge(batch, eventIDs: [confirmed.id])

        let pending = try await store.pendingEventIDs()
        XCTAssertEqual(pending, [unconfirmed.id])
        let inFlight = try await store.inFlightBatch()
        XCTAssertNil(inFlight)
    }

    func testBatchRespectsItsLimit() async throws {
        let store = try FileOutboxStore(directory: directory)
        let events = try (0 ..< 5).map { _ in try contractEvent(id: UUID()) }
        for event in events {
            try await store.enqueue(event.id)
        }

        let batch = try await store.beginBatch(
            eventsByID: Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) }),
            limit: 2
        )

        XCTAssertEqual(batch?.eventIDs.count, 2)
    }

    private var contractsDirectory: URL {
        // PokerCoachTests runs from a bundle, so walk to the repository copy of
        // the contract shared with the Go service.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Contracts", directoryHint: .isDirectory)
    }

    private func contractEvent() throws -> TrainingEvent {
        try ContractEventFixture.make()
    }

    private func contractEvent(id: UUID) throws -> TrainingEvent {
        try ContractEventFixture.make(id: id)
    }
}
