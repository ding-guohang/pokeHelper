import PokerCore
import Testing
@testable import SessionSimulation

/// The evaluator decides who the pot goes to, so a bug here is invisible to
/// every conservation assertion: the chips still add up, they just go to the
/// wrong seat.
@Suite("摊牌比较")
struct HandEvaluatorTests {
    private static func cards(_ codes: String...) -> [Card] {
        codes.map { code in
            guard let card = Card(code: code) else {
                fatalError("测试写错了牌面代码：\(code)")
            }
            return card
        }
    }

    private static func rank(_ codes: String...) -> HandRanking {
        HandEvaluator.evaluate(cards: codes.map { code in
            guard let card = Card(code: code) else {
                fatalError("测试写错了牌面代码：\(code)")
            }
            return card
        })
    }

    @Test("九个类别各自被正确识别")
    func recognisesEveryCategory() {
        #expect(Self.rank("As", "Kd", "9h", "7c", "3s", "2d", "4h").category == .highCard)
        #expect(Self.rank("As", "Ad", "9h", "7c", "3s", "2d", "4h").category == .pair)
        #expect(Self.rank("As", "Ad", "9h", "9c", "3s", "2d", "4h").category == .twoPair)
        #expect(Self.rank("As", "Ad", "Ah", "9c", "3s", "2d", "4h").category == .threeOfAKind)
        #expect(Self.rank("5s", "6d", "7h", "8c", "9s", "2d", "3h").category == .straight)
        #expect(Self.rank("2s", "5s", "9s", "Js", "Ks", "3d", "4h").category == .flush)
        #expect(Self.rank("As", "Ad", "Ah", "9c", "9s", "2d", "4h").category == .fullHouse)
        #expect(Self.rank("As", "Ad", "Ah", "Ac", "9s", "2d", "4h").category == .fourOfAKind)
        #expect(Self.rank("5s", "6s", "7s", "8s", "9s", "2d", "3h").category == .straightFlush)
    }

    @Test("类别之间的强弱顺序")
    func strongerCategoriesBeatWeakerOnes() {
        let ordered: [HandRanking] = [
            Self.rank("As", "Kd", "9h", "7c", "3s", "2d", "4h"),
            Self.rank("As", "Ad", "9h", "7c", "3s", "2d", "4h"),
            Self.rank("As", "Ad", "9h", "9c", "3s", "2d", "4h"),
            Self.rank("As", "Ad", "Ah", "9c", "3s", "2d", "4h"),
            Self.rank("5s", "6d", "7h", "8c", "9s", "2d", "3h"),
            Self.rank("2s", "5s", "9s", "Js", "Ks", "3d", "4h"),
            Self.rank("As", "Ad", "Ah", "9c", "9s", "2d", "4h"),
            Self.rank("As", "Ad", "Ah", "Ac", "9s", "2d", "4h"),
            Self.rank("5s", "6s", "7s", "8s", "9s", "2d", "3h"),
        ]

        #expect(ordered.count == HandRanking.Category.allCases.count)
        for (index, weaker) in ordered.enumerated().dropLast() {
            #expect(weaker < ordered[index + 1], "\(weaker) 没有输给 \(ordered[index + 1])")
        }
    }

    /// A full house beats a flush. The evaluator finds the flush first, so this
    /// is the one ordering it could plausibly get backwards.
    @Test("同时成花与葫芦时按葫芦计")
    func aFullHouseBeatsAFlushEvenWhenBothArePresent() {
        let hand = Self.rank("As", "Ad", "Ah", "9s", "5s", "2s", "9c")
        #expect(hand.category == .fullHouse)
        #expect(hand.tiebreakers == [12, 7], "实际 \(hand.tiebreakers)")
    }

    @Test("同时成花与同花顺时按同花顺计")
    func aStraightFlushBeatsItsOwnFlush() {
        let hand = Self.rank("2s", "3s", "4s", "5s", "6s", "Ks", "9d")
        #expect(hand.category == .straightFlush)
        #expect(hand.tiebreakers == [4], "同花顺应以 6 为头，实际 \(hand.tiebreakers)")
    }

    @Test("A2345 是最小的顺子，A 当作 1")
    func theWheelIsTheWeakestStraight() {
        let wheel = Self.rank("As", "2d", "3h", "4c", "5s", "Kd", "9h")
        #expect(wheel.category == .straight)
        #expect(wheel.tiebreakers == [3], "轮子的头应是 5，实际 \(wheel.tiebreakers)")

        let sixHigh = Self.rank("2s", "3d", "4h", "5c", "6s", "Kd", "9h")
        #expect(wheel < sixHigh, "轮子没有输给 6 高顺")
    }

    @Test("A 高顺子高于其他顺子")
    func broadwayIsTheStrongestStraight() {
        let broadway = Self.rank("As", "Kd", "Qh", "Jc", "Ts", "2d", "3h")
        #expect(broadway.category == .straight)
        #expect(broadway.tiebreakers == [12])
        #expect(Self.rank("9s", "Td", "Jh", "Qc", "Ks", "2d", "3h") < broadway)
    }

    @Test("同类别内按踢脚分高下")
    func kickersDecideInsideACategory() {
        let higherKicker = Self.rank("As", "Ad", "Kh", "7c", "3s", "2d", "4h")
        let lowerKicker = Self.rank("As", "Ad", "Qh", "7c", "3s", "2d", "4h")
        #expect(lowerKicker < higherKicker)

        let higherPair = Self.rank("Ks", "Kd", "2h", "7c", "3s", "2d", "4h")
        let lowerPair = Self.rank("Qs", "Qd", "Ah", "7c", "3s", "2d", "4h")
        #expect(lowerPair < higherPair, "高对没有压过带 A 踢脚的低对")
    }

    @Test("两手完全等值的牌比较为相等")
    func identicalHandsTie() {
        let left = HandEvaluator.evaluate(
            holeCards: Self.cards("As", "Kd"),
            board: Self.cards("Ah", "Kc", "9s", "4d", "2h")
        )
        let right = HandEvaluator.evaluate(
            holeCards: Self.cards("Ac", "Kh"),
            board: Self.cards("Ah", "Kc", "9s", "4d", "2h")
        )
        #expect(left == right)
        #expect(!(left < right) && !(right < left))
        #expect(left.category == .twoPair)
    }

    @Test("同一手牌的两种给定顺序得到同一个结果")
    func evaluationIgnoresCardOrder() {
        let forwards = Self.rank("As", "Kd", "Qh", "Jc", "Ts", "2d", "3h")
        let backwards = Self.rank("3h", "2d", "Ts", "Jc", "Qh", "Kd", "As")
        #expect(forwards == backwards)
    }

    @Test("七张牌里取最好的五张，而不是前五张")
    func picksTheBestFiveOfSeven() {
        // The first five cards make a pair of deuces; the best five make aces
        // full.
        let hand = Self.rank("2s", "2d", "7h", "8c", "9s", "As", "Ad")
        #expect(hand.category == .twoPair)
        #expect(hand.tiebreakers == [12, 0, 7], "实际 \(hand.tiebreakers)")
    }
}
