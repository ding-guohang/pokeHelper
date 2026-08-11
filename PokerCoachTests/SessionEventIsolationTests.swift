import Foundation
import PokerCore
import SessionPersistence
import SessionSimulation
import StrategyContent
import TrainingDomain
import TrainingPersistence
import XCTest
@testable import PokerCoach

/// The milestone's load-bearing test: playing a session never writes a training
/// event.
///
/// Not an afterthought and not a formality. A session hand has no strategy
/// behind it — nobody authored frequencies for a randomly dealt spot — and it
/// never asks for the confidence that `explainable-decision-training` requires
/// alongside an action. An event manufactured from one would be a sample the
/// ability profile cannot tell from a real answer: it would inflate sample
/// counts and it would satisfy the mastery rules' repetition and transfer
/// signals, the second of which is supposed to mean "this held up on a spot you
/// had not seen".
///
/// So the assertion is made with content installed *and hitting*: hands whose
/// preflop spot is equivalent to a shipped scenario are played, matched, and
/// still produce nothing.
final class SessionEventIsolationTests: XCTestCase {
    /// Chosen when coverage was keyed on the whole spot signature, because 30
    /// hands from it contained exactly one spot the shipped pack covered. That
    /// premise is gone: coverage is keyed on the situation now, and the same
    /// thirty hands contain 22 covered ones. Both the covered and the uncovered
    /// count are asserted below rather than assumed — without the first the
    /// test proves nothing about matching hands, and without the second it
    /// proves nothing about the rest.
    private let seed: UInt64 = 18
    private let handCount = 30

    /// What the shipped pack covers in these thirty hands. Pinned as a value
    /// rather than as "at least one", because the number is the measurement
    /// that justified changing the key: it was 1 under the old signature key.
    private let expectedMatchedHandCount = 22

    @MainActor
    func testAFullSessionWithContentInstalledWritesNoTrainingEvent() async throws {
        // A non-empty installed content library — the real one the app ships.
        let installed = try BundledContentLoader(bundle: .main).loadPreferredPack()
        XCTAssertFalse(installed.pack.scenarios.isEmpty)

        // A non-empty event store. Comparing an empty store to an empty store
        // is satisfied by an app that cannot write events at all, which is not
        // the claim; the claim is that this store is untouched.
        let eventStore = try FileTrainingEventStore(directory: temporaryDirectory())
        let existing = try TrainingEventFixture.make(
            localUserID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            deviceID: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        )
        try await eventStore.append(existing)
        let before = try await eventStore.allEvents()
        XCTAssertEqual(before.count, 1)

        let sessionDirectory = temporaryDirectory()
        let store = try FileSessionRecordStore(directory: sessionDirectory)
        let sessionID = UUID(uuidString: "5E551000-0000-0000-0000-000000000030")!
        try await store.create(
            SessionRecord(id: sessionID, seed: seed, handCount: handCount)
        )

        // Driven through the app-layer coordinator, which holds the event store
        // and is therefore the type that could write to it.
        let summary = try await SessionRunCoordinator(
            sessionStore: store,
            eventStore: eventStore,
            scenarios: installed.pack.scenarios
        ).playToCompletion(sessionID: sessionID)
        let hands = summary.hands
        XCTAssertEqual(hands.count, handCount)

        let matched = hands.filter { summary.comparableHandIndices.contains($0.handIndex) }
        XCTAssertEqual(
            matched.count,
            expectedMatchedHandCount,
            "这 \(handCount) 手命中 \(matched.count) 次内容，与实测的 \(expectedMatchedHandCount) 不符"
        )
        XCTAssertLessThan(
            matched.count,
            hands.count,
            "每一手都命中内容，测试就没有覆盖「未命中内容也不产生事件」"
        )

        // The same thirty hands under the old key — the whole signature,
        // example hand and all — so the improvement this change exists for is
        // a number in the test rather than a claim in a commit message.
        let underTheOldSignatureKey = hands.count { hand in
            hand.heroSpotSignatures.contains { signature in
                installed.pack.scenarios.contains { $0.spotSignature == signature }
            }
        }
        XCTAssertEqual(underTheOldSignatureKey, 1, "旧键在这局的命中数不是 1，对照失去意义")
        XCTAssertGreaterThan(
            matched.count,
            underTheOldSignatureKey * 10,
            "改键之后命中数只有 \(matched.count)，没有量级上的改善"
        )

        // The whole session has been played, with content installed, and some
        // of its hands correspond to that content.
        let after = try await eventStore.allEvents()
        XCTAssertEqual(after.count, before.count)
        XCTAssertEqual(after, before)

        // And the hands are all in the session record, matched ones included:
        // "no event" must not have been achieved by dropping them.
        let stored = try await store.hands(for: sessionID)
        XCTAssertEqual(stored.count, handCount)
        for hand in matched {
            XCTAssertTrue(
                stored.contains(hand),
                "命中内容的第 \(hand.handIndex) 手不在 Session 记录里"
            )
        }
    }

    /// The other half of the claim: an ability profile reduced from the store
    /// is the same profile afterwards.
    ///
    /// Separate from the event comparison above because it is what the user
    /// actually feels — a sample count that grew without anybody answering
    /// anything — and because a future write path that filtered events out of
    /// `allEvents()` rather than never creating them would pass the first
    /// assertion and fail this one.
    @MainActor
    func testAFullSessionLeavesTheAbilityProfileUnchanged() async throws {
        let eventStore = try FileTrainingEventStore(directory: temporaryDirectory())
        try await eventStore.append(
            try TrainingEventFixture.make(
                localUserID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                deviceID: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
            )
        )
        let before = PlayerModelReducer().reduce(
            events: try await eventStore.allEvents()
        )
        XCTAssertEqual(before["bet-sizing"]?.sampleCount, 1)

        let store = try FileSessionRecordStore(directory: temporaryDirectory())
        let sessionID = UUID(uuidString: "5E551000-0000-0000-0000-000000000031")!
        try await store.create(
            SessionRecord(id: sessionID, seed: seed, handCount: handCount)
        )
        _ = try await SessionRunCoordinator(
            sessionStore: store,
            eventStore: eventStore,
            scenarios: try BundledContentLoader(bundle: .main).loadPreferredPack().pack.scenarios
        ).playToCompletion(sessionID: sessionID)

        let after = PlayerModelReducer().reduce(
            events: try await eventStore.allEvents()
        )
        XCTAssertEqual(after["bet-sizing"]?.sampleCount, 1)
        XCTAssertEqual(after, before)
    }

    /// The shipped pack covers 22 of these thirty hands. This test asks the
    /// same question with content that covers *every* preflop spot the hero
    /// faced, so the matched branch runs on the whole session rather than on
    /// most of it.
    @MainActor
    func testASessionWhoseEverySpotMatchesContentStillWritesNoTrainingEvent() async throws {
        let eventStore = try FileTrainingEventStore(directory: temporaryDirectory())
        try await eventStore.append(
            try TrainingEventFixture.make(
                localUserID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                deviceID: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
            )
        )
        let before = try await eventStore.allEvents()

        let store = try FileSessionRecordStore(directory: temporaryDirectory())
        let sessionID = UUID(uuidString: "5E551000-0000-0000-0000-000000000032")!
        try await store.create(
            SessionRecord(id: sessionID, seed: seed, handCount: handCount)
        )
        // Played once to learn the spots, then replayed through a coordinator
        // whose content covers every one of them.
        let dealt = try await SessionPlaythrough.play(sessionID: sessionID, store: store)
        let summary = try await SessionRunCoordinator(
            sessionStore: store,
            eventStore: eventStore,
            scenarios: try Self.scenariosCovering(dealt)
        ).playToCompletion(sessionID: sessionID)
        let hands = summary.hands

        let matched = hands.filter { summary.comparableHandIndices.contains($0.handIndex) }
        let handsWithAPreflopDecision = hands.filter { hand in
            hand.heroSpotSignatures.contains { $0.street == .preflop }
        }
        XCTAssertGreaterThan(handsWithAPreflopDecision.count, 20)
        XCTAssertEqual(matched.count, handsWithAPreflopDecision.count)

        let after = try await eventStore.allEvents()
        XCTAssertEqual(after, before)
    }

    /// Scenarios built to cover every preflop situation in these hands.
    ///
    /// Only the four fields a coverage key reads are set from the hand —
    /// street, seat offset, facing and stack depth. The example hand is fixed,
    /// deliberately: it does not participate in coverage, and varying it would
    /// suggest it did. Everything else is copied from a fixture scenario,
    /// because none of it participates in the comparison either and inventing
    /// frequencies would be inventing strategy.
    @MainActor
    private static func scenariosCovering(
        _ hands: [SessionHandRecord]
    ) throws -> [DecisionScenario] {
        let template = try DecisionSessionFixture.makePack().scenarios[0]
        var seen: Set<SpotCoverageKey> = []
        var scenarios: [DecisionScenario] = []

        for hand in hands {
            for signature in hand.heroSpotSignatures
            where signature.street == .preflop && seen.insert(signature.coverageKey).inserted {
                let stack = representativeStack(for: signature.stackBucket)
                scenarios.append(
                    DecisionScenario(
                        id: "synthetic-\(scenarios.count)",
                        title: "合成对照场景",
                        abilityDimension: template.abilityDimension,
                        curriculumNodeID: template.curriculumNodeID,
                        heroSeatOffsetFromButton: signature.heroSeatOffsetFromButton,
                        facing: signature.facing,
                        heroCards: [
                            Card(rank: .ace, suit: .spades),
                            Card(rank: .king, suit: .hearts),
                        ],
                        board: [],
                        decision: BettingDecisionContext(
                            pot: BBAmount(centiBB: 150),
                            effectiveStack: stack,
                            amountToCall: BBAmount(centiBB: 100),
                            minimumRaiseTo: BBAmount(centiBB: 200),
                            configuredBetSizes: []
                        ),
                        options: template.options,
                        rangeCells: template.rangeCells,
                        assumptions: template.assumptions,
                        explanation: template.explanation
                    )
                )
            }
        }
        return scenarios
    }

    private static func representativeStack(for bucket: StackBucket) -> BBAmount {
        let stack = switch bucket {
        case .short: BBAmount(centiBB: 1_000)
        case .medium: BBAmount(centiBB: 4_000)
        case .deep: BBAmount(centiBB: 10_000)
        case .veryDeep: BBAmount(centiBB: 15_000)
        }
        // The scenario has to land back in the bucket it was built from,
        // otherwise this helper silently stops covering anything.
        precondition(StackBucket(effectiveStack: stack) == bucket)
        return stack
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }
}

