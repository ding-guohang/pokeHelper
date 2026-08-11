import PokerCore
import Testing
@testable import SessionSimulation

@Suite("发牌")
struct DealingTests {
    private static let seed: UInt64 = 42
    private static let handCount = 30

    @Test("整副牌是 52 张互不相同的牌")
    func theDeckIsWhatADeckIs() {
        #expect(Deck.ordered.count == 52)
        #expect(Set(Deck.ordered).count == 52, "牌堆里有重复")
    }

    @Test("洗牌是一个排列，且不等于原序")
    func shufflingPermutesRatherThanInvents() {
        var rng = SplitMix64(seed: Self.seed)
        let shuffled = Deck.shuffled(using: &rng)

        #expect(shuffled.count == 52)
        #expect(Set(shuffled) == Set(Deck.ordered), "洗牌改变了牌的集合")
        #expect(shuffled != Deck.ordered, "洗牌没有动过任何一张牌")
    }

    @Test("相同种子洗出相同的牌堆，不同种子洗出不同的牌堆")
    func shufflingIsAFunctionOfTheSeed() {
        var first = SplitMix64(seed: Self.seed)
        var second = SplitMix64(seed: Self.seed)
        var other = SplitMix64(seed: Self.seed + 1)

        #expect(Deck.shuffled(using: &first) == Deck.shuffled(using: &second))
        #expect(Deck.shuffled(using: &first) != Deck.shuffled(using: &other))
    }

    /// The spec counts hero and opponents separately, so this does too rather
    /// than checking a total of twelve — twelve cards dealt entirely to the
    /// hero would satisfy the total.
    @Test("每手恰好 2 张英雄底牌与 10 张对手底牌")
    func everyHandDealsTwoToTheHeroAndTenToTheOpponents() {
        let dealer = SessionDealer(seed: Self.seed)

        for handIndex in 0 ..< Self.handCount {
            let hand = dealer.deal(handIndex: handIndex)

            #expect(
                hand.holeCards[TableRules.heroSeat].count == 2,
                "第 \(handIndex) 手英雄拿到 \(hand.holeCards[TableRules.heroSeat].count) 张"
            )

            let opponentCards = (0 ..< TableRules.seatCount)
                .filter { $0 != TableRules.heroSeat }
                .flatMap { hand.holeCards[$0] }
            #expect(opponentCards.count == 10, "第 \(handIndex) 手对手共 \(opponentCards.count) 张")

            for seat in 0 ..< TableRules.seatCount {
                #expect(hand.holeCards[seat].count == 2, "座位 \(seat) 不是两张牌")
            }
        }
    }

    @Test("同一手内十七张牌互不相同")
    func noCardIsDealtTwiceWithinAHand() {
        let dealer = SessionDealer(seed: Self.seed)

        for handIndex in 0 ..< Self.handCount {
            let hand = dealer.deal(handIndex: handIndex)
            let cards = hand.allCards

            #expect(cards.count == 17, "第 \(handIndex) 手发出 \(cards.count) 张牌")
            #expect(
                Set(cards).count == 17,
                "第 \(handIndex) 手有重复牌：\(cards.map(\.code).sorted())"
            )
        }
    }

    /// The spec ties board size to the street reached, so the assertion has to
    /// be about the pair. `board.count <= 5` would be satisfied by a hand that
    /// never deals a board at all.
    @Test("公共牌张数按该手到达的街道恰为 0、3、4 或 5")
    func theBoardMatchesTheStreetTheHandReached() throws {
        let run = SessionRunner(seed: Self.seed).run(handCount: Self.handCount)
        #expect(run.hands.count == Self.handCount)

        var seenCounts: Set<Int> = []
        for hand in run.hands {
            let expected = hand.result.streetReached.boardCardCount
            #expect([0, 3, 4, 5].contains(hand.board.count), "板面 \(hand.board.count) 张")
            #expect(
                hand.board.count == expected,
                "第 \(hand.handIndex) 手到 \(hand.result.streetReached)，板面却是 \(hand.board.count) 张"
            )
            #expect(hand.board == hand.result.board)
            seenCounts.insert(hand.board.count)
        }

        // Without this the assertion above is satisfied by 30 hands that all
        // ended preflop with an empty board — which is exactly what a broken
        // street machine produces.
        #expect(seenCounts.count >= 3, "30 手只出现了 \(seenCounts.sorted()) 这些板面张数")
        #expect(seenCounts.contains(5), "没有任何一手打到河牌")
    }

    @Test("整局中每一手的十七张牌都互不相同")
    func noHandInAWholeSessionRepeatsACard() {
        let run = SessionRunner(seed: Self.seed).run(handCount: Self.handCount)

        for hand in run.hands {
            let cards = hand.holeCards.flatMap(\.self) + hand.board
            #expect(
                Set(cards).count == cards.count,
                "第 \(hand.handIndex) 手有重复牌：\(cards.map(\.code))"
            )
            #expect(cards.count == 12 + hand.board.count)
        }
    }

    /// The spec asks for at least 29 of 30 hero hands to differ between seeds
    /// 42 and 43. A dealer that ignored its seed would fail here and pass every
    /// same-seed assertion above.
    @Test("不同种子产生不同牌局")
    func differentSeedsDealDifferentHands() {
        let first = SessionDealer(seed: 42)
        let second = SessionDealer(seed: 43)

        let differing = (0 ..< Self.handCount).count { handIndex in
            first.deal(handIndex: handIndex).holeCards[TableRules.heroSeat]
                != second.deal(handIndex: handIndex).holeCards[TableRules.heroSeat]
        }
        #expect(differing >= 29, "只有 \(differing) 手英雄手牌不同")
    }

    @Test("按钮每手前移一位，英雄六手轮遍六个位置")
    func theButtonMovesOneSeatPerHand() throws {
        var labels: [String] = []
        for handIndex in 0 ..< TableRules.seatCount {
            let buttonSeat = TableRules.buttonSeat(handIndex: handIndex)
            #expect(buttonSeat == handIndex)
            labels.append(
                try TableRules.position(seat: TableRules.heroSeat, buttonSeat: buttonSeat).label
            )
        }

        #expect(labels == ["BTN", "CO", "HJ", "UTG", "BB", "SB"], "实际是 \(labels)")
        #expect(Set(labels).count == TableRules.seatCount)
    }
}
