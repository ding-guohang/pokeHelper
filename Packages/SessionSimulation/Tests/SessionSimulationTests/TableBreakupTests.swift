import Foundation
import PokerCore
import Testing
@testable import SessionSimulation

/// A session with fewer than two funded seats has no hand to deal, so it ends
/// on the hands it has rather than dealing a blindless one.
@Suite("有筹码的座位少于两个时不再发牌")
struct TableBreakupTests {
    /// Builds a stored progress whose last hand left the table with only the
    /// given number of funded seats, without playing a real session to that
    /// state — which no seed reaches inside a handful of hands.
    private static func progress(
        fundedSeats: Int,
        handsPlayed: Int,
        plannedHandCount: Int
    ) -> SessionProgress {
        precondition((1 ... TableRules.seatCount).contains(fundedSeats))
        precondition(handsPlayed >= 1)

        let cards = Array(Deck.ordered.prefix(2 * TableRules.seatCount))
        let holeCards = (0 ..< TableRules.seatCount).map { [cards[$0 * 2], cards[$0 * 2 + 1]] }

        // All the chips pile onto the funded seats; the rest sit at zero.
        let perFunded = TableRules.seatCount * TableRules.startingStack.centiBB / fundedSeats
        let endingStacks = (0 ..< TableRules.seatCount).map { seat in
            BBAmount(centiBB: seat < fundedSeats ? perFunded : 0)
        }

        let result = HandResult(
            streetReached: .preflop,
            board: [],
            potTotal: BBAmount(centiBB: 0),
            contributions: [BBAmount](repeating: BBAmount(centiBB: 0), count: TableRules.seatCount),
            payouts: [BBAmount](repeating: BBAmount(centiBB: 0), count: TableRules.seatCount),
            stackDeltasCentiBB: [Int](repeating: 0, count: TableRules.seatCount),
            showdownSeats: [],
            pots: [],
            rake: BBAmount(centiBB: 0)
        )

        let played = (0 ..< handsPlayed).map { index in
            SessionHandRecord(
                PlayedHand(
                    handIndex: index,
                    buttonSeat: TableRules.buttonSeat(handIndex: index),
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

        let record = SessionRecord(
            id: UUID(uuidString: "5E551000-0000-0000-0000-0000000000B1")!,
            seed: 1,
            handCount: plannedHandCount
        )
        return SessionProgress(record: record, playedHands: played)
    }

    @Test("只剩一个有筹码的座位时，Session 判定为已结束且明确标示提前结束")
    func aTableWithOneFundedSeatIsCompleteAndFlaggedEarly() {
        let progress = Self.progress(fundedSeats: 1, handsPlayed: 5, plannedHandCount: 30)

        #expect(!progress.tableCanContinue, "只剩一个有筹码的座位，不该还能发牌")
        #expect(progress.isComplete, "牌桌散了，Session 应判定为已结束")
        #expect(progress.endedEarly, "提前结束应被明确标示")
        #expect(progress.playedHands.count < progress.record.handCount, "记录手数应少于原定手数")
    }

    @Test("两个及以上有筹码的座位时，未打满的 Session 仍是进行中而非提前结束")
    func aTableWithTwoFundedSeatsIsStillInProgress() {
        let progress = Self.progress(fundedSeats: 2, handsPlayed: 5, plannedHandCount: 30)

        #expect(progress.tableCanContinue, "两个有筹码的座位仍可发牌")
        #expect(!progress.isComplete, "还没打满且牌桌未散，应仍是进行中")
        #expect(!progress.endedEarly, "牌桌未散，不该标为提前结束")
    }

    /// Over the fixed seed set, at least one run actually breaks up, and no run
    /// ever deals a hand that started with fewer than two funded seats.
    @Test("扫描种子：提前结束的 Session 确实出现，且从不发出无盲注的手牌")
    func someSessionsBreakUpAndNoneDealABlindlessHand() {
        var endedEarly = 0
        var brokeUpAtFewerThanFifteen = false

        for seed in 1 ... UInt64(300) {
            let run = SessionRunner(seed: seed).run(handCount: 15)
            if run.endedEarly {
                endedEarly += 1
                if run.hands.count < 15 {
                    brokeUpAtFewerThanFifteen = true
                }
                // A run that ended early must actually have run out of seats.
                #expect(
                    SessionRunner.seatsWithChips(run.finalStacks) < SessionRunner.minimumSeatsToDeal,
                    "种子 \(seed) 标为提前结束，末态却仍有 \(SessionRunner.seatsWithChips(run.finalStacks)) 个有筹码的座位"
                )
            }
            // Every dealt hand had two seats to post blinds into.
            for hand in run.hands {
                #expect(
                    SessionRunner.seatsWithChips(hand.startingStacks) >= SessionRunner.minimumSeatsToDeal,
                    "种子 \(seed) 第 \(hand.handIndex) 手在只有不到两个有筹码座位时仍被发出"
                )
            }
        }

        #expect(endedEarly > 0, "扫描 300 个种子没有任何一局提前结束，早停路径未被触发")
        #expect(brokeUpAtFewerThanFifteen, "没有任何一局在打满 15 手前散台")
    }
}
