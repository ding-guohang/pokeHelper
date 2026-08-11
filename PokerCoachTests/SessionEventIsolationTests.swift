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
    /// Chosen because 30 hands from it contain at least one spot the shipped
    /// pack covers and many it does not. Both are asserted below rather than
    /// assumed: without the first the test proves nothing about matching hands,
    /// and without the second it proves nothing about the rest.
    private let seed: UInt64 = 18
    private let handCount = 30

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
        XCTAssertGreaterThanOrEqual(
            matched.count,
            1,
            "这 \(handCount) 手没有一手命中已安装内容，测试就没有覆盖「命中内容也不产生事件」"
        )
        XCTAssertLessThan(
            matched.count,
            hands.count,
            "每一手都命中内容，测试就没有覆盖「未命中内容也不产生事件」"
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

    /// The shipped pack covers exactly one of these thirty spots, which is what
    /// installed content honestly does today. This test asks the same question
    /// with content that covers *every* preflop spot the hero faced, so the
    /// matched branch runs on the whole session rather than on one hand.
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

    /// Scenarios built to match every preflop spot in these hands.
    ///
    /// Only the five fields a signature reads are set from the hand — street,
    /// seat offset, hand class, facing and stack depth. Everything else is
    /// copied from a fixture scenario, because none of it participates in the
    /// comparison and inventing frequencies would be inventing strategy.
    @MainActor
    private static func scenariosCovering(
        _ hands: [SessionHandRecord]
    ) throws -> [DecisionScenario] {
        let template = try DecisionSessionFixture.makePack().scenarios[0]
        var seen: Set<SpotSignature> = []
        var scenarios: [DecisionScenario] = []

        for hand in hands {
            for signature in hand.heroSpotSignatures
            where signature.street == .preflop && seen.insert(signature).inserted {
                let stack = representativeStack(for: signature.stackBucket)
                scenarios.append(
                    DecisionScenario(
                        id: "synthetic-\(scenarios.count)",
                        title: "合成对照场景",
                        abilityDimension: template.abilityDimension,
                        curriculumNodeID: template.curriculumNodeID,
                        heroSeatOffsetFromButton: signature.heroSeatOffsetFromButton,
                        facing: signature.facing,
                        heroCards: cards(for: signature.handClass),
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

    private static func cards(for handClass: HandClass) -> [Card] {
        switch handClass.suitedness {
        case .pair:
            [
                Card(rank: handClass.highRank, suit: .spades),
                Card(rank: handClass.lowRank, suit: .hearts),
            ]
        case .suited:
            [
                Card(rank: handClass.highRank, suit: .spades),
                Card(rank: handClass.lowRank, suit: .spades),
            ]
        case .offsuit:
            [
                Card(rank: handClass.highRank, suit: .spades),
                Card(rank: handClass.lowRank, suit: .hearts),
            ]
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }
}

