import Foundation
import PokerCore
import SessionPersistence
import SessionSimulation
import StrategyContent
import TrainingDomain
import TrainingPersistence
import XCTest
@testable import PokerCoach

/// The key hands a finished session opens review with, as the app actually
/// computes them.
///
/// `KeyHandSelection` is tested in `SessionSimulation` on constructed facts,
/// which is where the score table belongs. What cannot be tested there is the
/// one input the engine is not allowed to compute: how much weight installed
/// content gives the line the hero took. That crosses the layer boundary, so it
/// is asserted here, on real hands against the real shipped pack.
final class SessionKeyHandReviewTests: XCTestCase {
    private let handCount = 30

    /// `.deviation` is reachable on real sessions against real content.
    ///
    /// This is the assertion the reason it replaced did not survive:
    /// `.trainable` scored a flat 1000 against `.bigPot`'s guaranteed five
    /// candidates at 2000 or more, so it could never be the reason shown. A
    /// reason that cannot appear is not a feature, and a table can carry one
    /// for a long time without anybody noticing.
    @MainActor
    func testDeviationIsTheDisplayedReasonOnRealSessions() async throws {
        let installed = try BundledContentLoader(bundle: .main).loadPreferredPack()
        XCTAssertFalse(installed.pack.scenarios.isEmpty)

        var sessionsWithADeviation = 0
        var sessionsExamined = 0
        var reasonsSeen: Set<KeyHandReason> = []

        for seed in UInt64(1) ... 12 {
            let summary = try await Self.play(
                seed: seed,
                handCount: handCount,
                scenarios: installed.pack.scenarios
            )
            sessionsExamined += 1

            XCTAssertGreaterThanOrEqual(summary.keyHands.count, 3)
            XCTAssertLessThanOrEqual(summary.keyHands.count, 5)
            reasonsSeen.formUnion(summary.keyHands.map(\.reason))
            if summary.keyHands.contains(where: { $0.reason == .deviation }) {
                sessionsWithADeviation += 1
            }
        }

        XCTAssertEqual(sessionsExamined, 12)
        XCTAssertGreaterThan(
            sessionsWithADeviation,
            0,
            "12 局里没有一局把 .deviation 作为展示原因，它和被它替换掉的 .trainable 一样够不着"
        )
        // Not every hand: a table where deviation swamped everything would be
        // as uninformative as one where it never appeared.
        XCTAssertTrue(reasonsSeen.contains(.bigPot) || reasonsSeen.contains(.allIn))
    }

    /// A hand shown as `.deviation` really is one content covers and really is
    /// one the hero played against the range's weight. Checked against the
    /// matcher rather than against the selector's own input, so that a
    /// coordinator that handed in the wrong dictionary fails here.
    @MainActor
    func testEveryDeviationIsCoveredAndBelowTheThreshold() async throws {
        let installed = try BundledContentLoader(bundle: .main).loadPreferredPack()
        let matcher = SessionContentMatcher(scenarios: installed.pack.scenarios)
        var checked = 0

        for seed in UInt64(1) ... 12 {
            let summary = try await Self.play(
                seed: seed,
                handCount: handCount,
                scenarios: installed.pack.scenarios
            )
            let handsByIndex = Dictionary(
                uniqueKeysWithValues: summary.hands.map { ($0.handIndex, $0) }
            )

            for key in summary.keyHands where key.reason == .deviation {
                let hand = try XCTUnwrap(handsByIndex[key.handIndex])
                let matches = matcher.matches(in: hand)
                XCTAssertFalse(matches.isEmpty, "种子 \(seed) 第 \(key.handIndex) 手被标为偏离，却没有被内容覆盖")

                let weights = matches.compactMap(\.heroActionWeightBasisPoints)
                let lowest = try XCTUnwrap(weights.min())
                // 5000 spelled out rather than read from
                // `KeyHandSelection.deviationWeightThresholdBasisPoints`: an
                // expected value taken from the constant under test moves with
                // it, and this assertion exists to notice it moving.
                XCTAssertLessThan(
                    lowest,
                    5_000,
                    "种子 \(seed) 第 \(key.handIndex) 手被标为偏离，最低权重却是 \(lowest)"
                )
                XCTAssertEqual(key.score, 5_000 + (10_000 - lowest))
                checked += 1
            }
        }

        XCTAssertGreaterThan(checked, 0, "12 局里一条偏离都没有，上面的循环是空转的")
    }

    /// The hands review opens with are not the hands the ability profile is
    /// built from, and selecting them writes nothing. Stated here as well as in
    /// `SessionEventIsolationTests` because this is the path that now reads
    /// content in order to score, and reading content is the step that could
    /// grow a write.
    @MainActor
    func testSelectingKeyHandsWritesNoTrainingEvent() async throws {
        let installed = try BundledContentLoader(bundle: .main).loadPreferredPack()
        let eventStore = try FileTrainingEventStore(directory: Self.temporaryDirectory())
        try await eventStore.append(
            try TrainingEventFixture.make(
                localUserID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                deviceID: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
            )
        )
        let before = try await eventStore.allEvents()

        let store = try FileSessionRecordStore(directory: Self.temporaryDirectory())
        let sessionID = UUID(uuidString: "5E551000-0000-0000-0000-000000000040")!
        try await store.create(SessionRecord(id: sessionID, seed: 49, handCount: handCount))
        let summary = try await SessionRunCoordinator(
            sessionStore: store,
            eventStore: eventStore,
            scenarios: installed.pack.scenarios
        ).playToCompletion(sessionID: sessionID)

        XCTAssertFalse(summary.keyHands.isEmpty, "没有选出关键手，断言是空转的")
        XCTAssertFalse(summary.contentMatches.isEmpty, "没有一手命中内容，断言是空转的")
        let after = try await eventStore.allEvents()
        XCTAssertEqual(after, before)
    }

    @MainActor
    private static func play(
        seed: UInt64,
        handCount: Int,
        scenarios: [DecisionScenario]
    ) async throws -> SessionRunSummary {
        let store = try FileSessionRecordStore(directory: temporaryDirectory())
        let sessionID = UUID()
        try await store.create(
            SessionRecord(id: sessionID, seed: seed, handCount: handCount)
        )
        return try await SessionRunCoordinator(
            sessionStore: store,
            eventStore: UnwritableEventStore(),
            scenarios: scenarios
        ).playToCompletion(sessionID: sessionID)
    }

    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }
}

/// An event store that fails the test if anything reaches it.
///
/// The coordinator has to be handed one, and handing it a working store would
/// make "nothing was written" a claim to check afterwards rather than at the
/// moment it happened.
private actor UnwritableEventStore: TrainingEventStore {
    func append(_ event: TrainingEvent) throws {
        XCTFail("Session 路径写入了 TrainingEvent \(event.id)")
    }

    func allEvents() throws -> [TrainingEvent] { [] }

    func events(after checkpoint: UUID?) throws -> [TrainingEvent] { [] }
}
