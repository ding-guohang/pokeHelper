import Foundation
import PokerCore
import SessionPersistence
import SessionSimulation
import StrategyContent
import TrainingDomain
import XCTest
@testable import PokerCoach

/// One played session, prepared the way the app prepares it.
///
/// Real hands from a real seed against real installed content — not a
/// hand-built record. A constructed `SessionHandRecord` would let a test assert
/// whatever shape it had just written down; these assertions are about hands
/// the engine actually dealt.
@MainActor
enum SessionReviewFixture {
    struct Played {
        let pack: StrategyPack
        let record: SessionRecord
        let hands: [SessionHandRecord]
        let summary: SessionRunSummary
        let reviews: [KeyHandReview]

        func review(handIndex: Int) throws -> KeyHandReview {
            try XCTUnwrap(
                reviews.first { $0.handIndex == handIndex },
                "第 \(handIndex) 手不在关键手里，实际选出的是 \(reviews.map(\.handIndex))"
            )
        }

        func hand(_ handIndex: Int) throws -> SessionHandRecord {
            try XCTUnwrap(hands.first { $0.handIndex == handIndex })
        }
    }

    /// The reviewed pack the app ships.
    static func corePack() throws -> StrategyPack {
        try BundledContentLoader(bundle: .main).loadPreferredPack().pack
    }

    static func play(
        seed: UInt64,
        handCount: Int,
        pack: StrategyPack? = nil,
        eventStore: (any TrainingEventStore)? = nil
    ) async throws -> Played {
        let pack = try pack ?? corePack()
        let store = try FileSessionRecordStore(directory: temporaryDirectory())
        let sessionID = UUID()
        try await store.create(
            SessionRecord(id: sessionID, seed: seed, handCount: handCount)
        )
        let summary = try await SessionRunCoordinator(
            sessionStore: store,
            eventStore: eventStore ?? RefusingEventStore(),
            scenarios: pack.scenarios
        ).playToCompletion(sessionID: sessionID)
        let record = try await store.record(id: sessionID)

        return Played(
            pack: pack,
            record: record,
            hands: summary.hands,
            summary: summary,
            reviews: KeyHandReviewBuilder(scenarios: pack.scenarios)
                .reviews(from: summary, seating: record.seating)
        )
    }

    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }
}

/// Fails the test if a session path ever writes an event.
///
/// The coordinator has to be given a store, and giving it a working one would
/// turn "nothing was written" into something to check afterwards instead of at
/// the moment it happened.
actor RefusingEventStore: TrainingEventStore {
    func append(_ event: TrainingEvent) throws {
        XCTFail("Session 路径写入了 TrainingEvent \(event.id)")
    }

    func allEvents() throws -> [TrainingEvent] { [] }
    func events(after checkpoint: UUID?) throws -> [TrainingEvent] { [] }
}
