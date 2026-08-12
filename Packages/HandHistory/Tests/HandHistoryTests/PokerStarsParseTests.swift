import Foundation
import PokerCore
import Testing
@testable import HandHistory

/// Appendix A parsed into the pinned model.
@Suite("PokerStars 解析附录 A")
struct PokerStarsParseTests {
    private func parseAppendixA() throws -> ObservedHand {
        let text = try Fixtures.text("sample-ps-6max-nlhe.txt")
        let result = PokerStarsParser.parse(text)
        let pair = try #require(result.parsedPair, "附录 A 未解析为 .parsed")
        // Self-check: a parser that returned an empty shell would pass many of
        // the assertions below vacuously.
        #expect(!pair.hand.streets.isEmpty, "解析出的模型没有任何街")
        #expect(pair.conflicts.isEmpty, "清晰输入不应有冲突：\(pair.conflicts)")
        return pair.hand
    }

    @Test("附录 A 解析出与输入相符的模型")
    func modelMatchesInput() throws {
        let hand = try parseAppendixA()

        #expect(hand.site == .pokerStars)
        #expect(hand.tableSize == 6)
        #expect(hand.bigBlindCentiBB == 100)

        let hero = try #require(hand.seats.first { $0.seat == 1 })
        #expect(hero.seatOffsetFromButton == 0)
        #expect(hero.startingStackCentiBB == 10000)
        #expect(hero.holeCards == .known(Card(code: "Ah")!, Card(code: "Kd")!))

        for seat in hand.seats where seat.seat != 1 {
            #expect(seat.holeCards == .unknown, "座位 \(seat.seat) 底牌应为未知")
            #expect(seat.startingStackCentiBB == 10000)
        }

        #expect(hand.result.rakeCentiBB == 50)
    }

    @Test("强制下注单列为 SB 50 / BB 100，不计入自主行动")
    func forcedPosts() throws {
        let hand = try parseAppendixA()

        #expect(hand.forcedPosts == [
            ForcedPost(seat: 2, kind: .smallBlind, amountCentiBB: 50),
            ForcedPost(seat: 3, kind: .bigBlind, amountCentiBB: 100),
        ])
    }

    @Test("位置由按钮与座位顺序导出为 [BTN, SB, BB, UTG, HJ, CO]")
    func positionsDerivedFromButton() throws {
        let hand = try parseAppendixA()
        let labels = try hand.seats
            .sorted { $0.seat < $1.seat }
            .map { seat in
                try TablePosition(
                    tableSize: hand.tableSize,
                    heroSeatOffsetFromButton: seat.seatOffsetFromButton
                ).label
            }

        #expect(labels == ["BTN", "SB", "BB", "UTG", "HJ", "CO"])
    }

    @Test("非连续座位的 5 人局：偏移绕按钮排在座玩家，tableSize 为在座人数")
    func fiveHandedNonContiguousSeats() throws {
        let text = try Fixtures.text("sample-ps-6max-5handed.txt")
        let pair = try #require(PokerStarsParser.parse(text).parsedPair, "5 人局应为 .parsed")
        // Self-check: an empty shell would pass the position assertions vacuously.
        #expect(!pair.hand.streets.isEmpty, "解析出的模型没有任何街")
        let hand = pair.hand

        // Header says "6-max" but only five seats are dealt in (seat 3 empty).
        // The effective table size is the number of dealt-in players, not the
        // header capacity, so the invariant seats.count == tableSize holds.
        #expect(hand.tableSize == 5, "tableSize 应为在座人数 5，实际 \(hand.tableSize)")
        #expect(hand.seats.count == hand.tableSize, "seats.count 应等于 tableSize")

        let sorted = hand.seats.sorted { $0.seat < $1.seat }
        #expect(sorted.map(\.seat) == [1, 2, 4, 5, 6], "座位号应为 1,2,4,5,6")
        // Ranked clockwise from the button (seat 1): consecutive offsets 0...4,
        // NOT seat-minus-button arithmetic against the header capacity (which
        // would skip 2 for the empty seat 3).
        #expect(
            sorted.map(\.seatOffsetFromButton) == [0, 1, 2, 3, 4],
            "偏移应为绕按钮的连续 0...4，实际 \(sorted.map(\.seatOffsetFromButton))"
        )

        let labels = try sorted.map { seat in
            try TablePosition(
                tableSize: hand.tableSize,
                heroSeatOffsetFromButton: seat.seatOffsetFromButton
            ).label
        }
        #expect(labels == ["BTN", "SB", "BB", "HJ", "CO"], "5 人局标签应为 BTN,SB,BB,HJ,CO")
    }

    @Test("逐街行动按发生顺序完整还原")
    func actionsReconstructedPerStreet() throws {
        let hand = try parseAppendixA()

        func street(_ s: Street) throws -> ObservedStreet {
            try #require(hand.streets.first { $0.street == s }, "缺少 \(s) 街")
        }

        let preflop = try street(.preflop)
        #expect(preflop.board.isEmpty)
        #expect(preflop.actions == [
            ObservedAction(seat: 4, kind: .fold, amountCentiBB: nil),
            ObservedAction(seat: 5, kind: .fold, amountCentiBB: nil),
            ObservedAction(seat: 6, kind: .fold, amountCentiBB: nil),
            ObservedAction(seat: 1, kind: .raiseTo, amountCentiBB: 300),
            ObservedAction(seat: 2, kind: .fold, amountCentiBB: nil),
            ObservedAction(seat: 3, kind: .call, amountCentiBB: 300),
        ])

        let flop = try street(.flop)
        #expect(flop.board == ["Ac", "7h", "2s"].map { Card(code: $0)! })
        #expect(flop.actions == [
            ObservedAction(seat: 3, kind: .check, amountCentiBB: nil),
            ObservedAction(seat: 1, kind: .bet, amountCentiBB: 400),
            ObservedAction(seat: 3, kind: .call, amountCentiBB: 400),
        ])

        let turn = try street(.turn)
        #expect(turn.board == ["Ac", "7h", "2s", "Td"].map { Card(code: $0)! })
        #expect(turn.actions == [
            ObservedAction(seat: 3, kind: .check, amountCentiBB: nil),
            ObservedAction(seat: 1, kind: .check, amountCentiBB: nil),
        ])

        let river = try street(.river)
        #expect(river.board == ["Ac", "7h", "2s", "Td", "9c"].map { Card(code: $0)! })
        #expect(river.actions == [
            ObservedAction(seat: 3, kind: .check, amountCentiBB: nil),
            ObservedAction(seat: 1, kind: .bet, amountCentiBB: 800),
            ObservedAction(seat: 3, kind: .fold, amountCentiBB: nil),
        ])

        let total = hand.streets.reduce(0) { $0 + $1.actions.count }
        #expect(total == 14, "自主行动总数应为 14，实际 \(total)")
    }
}
