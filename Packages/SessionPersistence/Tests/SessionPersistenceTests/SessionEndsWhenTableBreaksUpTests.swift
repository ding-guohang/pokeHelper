import Foundation
import PokerCore
import Testing
@testable import SessionPersistence
@testable import SessionSimulation

/// Resuming a session whose table has broken up deals nothing.
///
/// The playthrough loop reads the carried stacks and stops when fewer than two
/// seats hold chips, rather than dealing hand after hand that has no blind to
/// post. Written against a stored state with one funded seat because no seed
/// reaches that state in the handful of hands a fast test can play.
@Suite("牌桌散台后续打不再发牌")
struct SessionEndsWhenTableBreaksUpTests {
    private static let sessionID = UUID(uuidString: "5E551000-0000-0000-0000-0000000000C2")!

    private static func brokenHand() -> SessionHandRecord {
        let cards = Array(Deck.ordered.prefix(2 * TableRules.seatCount))
        let holeCards = (0 ..< TableRules.seatCount).map { [cards[$0 * 2], cards[$0 * 2 + 1]] }

        // Seat 0 holds every chip on the table; the rest have busted.
        let endingStacks = (0 ..< TableRules.seatCount).map { seat in
            BBAmount(centiBB: seat == 0 ? TableRules.seatCount * TableRules.startingStack.centiBB : 0)
        }
        let zeros = [BBAmount](repeating: BBAmount(centiBB: 0), count: TableRules.seatCount)
        let result = HandResult(
            streetReached: .preflop,
            board: [],
            potTotal: BBAmount(centiBB: 0),
            contributions: zeros,
            payouts: zeros,
            stackDeltasCentiBB: [Int](repeating: 0, count: TableRules.seatCount),
            showdownSeats: [],
            pots: [],
            rake: BBAmount(centiBB: 0)
        )
        return SessionHandRecord(
            PlayedHand(
                handIndex: 0,
                buttonSeat: 0,
                holeCards: holeCards,
                board: [],
                actions: [],
                result: result,
                startingStacks: SessionRunner.initialStacks,
                endingStacks: endingStacks,
                decisions: []
            )
        )
    }

    @Test("续打一个只剩一个有筹码座位的记录，不再发出任何一手")
    func resumingABrokenUpTableDealsNothing() async throws {
        let directory = SessionFixture.temporaryDirectory()
        let store = try FileSessionRecordStore(directory: directory)
        try await store.create(SessionRecord(id: Self.sessionID, seed: 1, handCount: 30))
        try await store.appendHand(Self.brokenHand(), to: Self.sessionID)

        let dealt = try await SessionPlaythrough.play(sessionID: Self.sessionID, store: store)

        #expect(dealt.isEmpty, "牌桌只剩一个有筹码座位，续打却仍发出了 \(dealt.count) 手")

        let progress = try await store.progress(for: Self.sessionID)
        #expect(progress.playedHands.count == 1, "记录里应仍只有那一手")
        #expect(progress.isComplete, "散台的 Session 应判定为已结束")
        #expect(progress.endedEarly, "提前结束应被明确标示")
    }
}
