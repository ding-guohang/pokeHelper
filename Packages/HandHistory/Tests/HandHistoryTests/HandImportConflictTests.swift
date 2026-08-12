import Foundation
import PokerCore
import Testing
@testable import HandHistory

/// Conflicts and unsupported text. Appendix A and appendix B differ by exactly
/// one line (verified below), which is what makes "always conflict" and "never
/// conflict" implementations both fail: A must be clean and B must flag exactly
/// that line, so no constant or unrelated-proxy detector can satisfy both.
@Suite("冲突与不支持")
struct HandImportConflictTests {
    @Test("附录 C 锦标赛被判为不受支持，并指向触发行")
    func tournamentIsUnsupported() throws {
        let text = try Fixtures.text("sample-ps-tournament.txt")
        let result = PokerStarsParser.parse(text)

        #expect(result.parsedPair == nil, "锦标赛不应产生 .parsed 模型")
        let line = try #require(result.unsupportedLine, "未返回 .unsupported")

        // The trigger is the header line that carries "Tournament".
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines[line - 1].contains("Tournament"), "sourceLine \(line) 不是锦标赛标识行")
    }

    @Test("附录 B 恰在被改动的那一行报出一个冲突")
    func appendixBFlagsExactlyTheChangedLine() throws {
        // A and B differ by exactly one line; the difference is the unknown verb.
        let a = try Fixtures.text("sample-ps-6max-nlhe.txt")
        let b = try Fixtures.text("sample-ps-6max-nlhe-unknown-action.txt")
        let aLines = a.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let bLines = b.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let differing = zip(aLines, bLines).enumerated().filter { $0.element.0 != $0.element.1 }
        #expect(differing.count == 1, "A 与 B 应恰好差一行，实际差 \(differing.count) 行")
        let changedLine = try #require(differing.first).offset + 1

        let pair = try #require(PokerStarsParser.parse(b).parsedPair, "附录 B 应为 .parsed")
        #expect(pair.conflicts.count == 1, "附录 B 应恰有一条冲突，实际 \(pair.conflicts)")
        let conflict = try #require(pair.conflicts.first)
        #expect(conflict.sourceLine == changedLine, "冲突行 \(conflict.sourceLine) 应为被改行 \(changedLine)")

        // The flagged action must not have been given a guessed value: no
        // preflop action on that seat carries the raise it would have been.
        let preflop = try #require(pair.hand.streets.first { $0.street == .preflop })
        #expect(
            !preflop.actions.contains { $0.seat == 1 && $0.kind == .raiseTo },
            "被标记的动作被赋予了猜测值"
        )
    }

    @Test("附录 A 清晰输入零冲突（与附录 B 成对）")
    func appendixAHasNoConflicts() throws {
        // Paired with the test above: A and B differ by one line only, so a
        // detector keyed on anything but that line's grammar fails one of the two.
        let pair = try #require(
            PokerStarsParser.parse(try Fixtures.text("sample-ps-6max-nlhe.txt")).parsedPair,
            "附录 A 应为 .parsed"
        )
        #expect(!pair.hand.streets.isEmpty, "夹具未产出模型")
        #expect(pair.conflicts.isEmpty, "附录 A 不应有冲突：\(pair.conflicts)")
    }

    @Test("摊牌底牌被读出，未摊底牌记为未知")
    func shownCardsReadUnshownUnknown() throws {
        let pair = try #require(
            PokerStarsParser.parse(try Fixtures.text("sample-ps-6max-nlhe.txt")).parsedPair
        )
        let hero = try #require(pair.hand.seats.first { $0.seat == 1 })
        // "always unknown" fails here.
        #expect(hero.holeCards == .known(Card(code: "Ah")!, Card(code: "Kd")!))

        let villain = try #require(pair.hand.seats.first { $0.seat == 2 })
        // "copy the hero's two cards" fails here.
        #expect(villain.holeCards == .unknown)
    }

    @Test("金额不能被大盲整除时报冲突而非四舍五入")
    func nonDivisibleAmountConflicts() throws {
        let text = try Fixtures.text("sample-ps-6max-rake-fraction.txt")
        let pair = try #require(PokerStarsParser.parse(text).parsedPair, "附录 D 应为 .parsed")

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let rakeLine = try #require(
            lines.firstIndex(where: { $0.contains("Rake") }).map { $0 + 1 },
            "夹具缺少 Rake 行"
        )
        // $0.01 at a $0.06 big blind is 100/6 centi-BB — not an integer.
        let conflict = try #require(
            pair.conflicts.first { $0.sourceLine == rakeLine },
            "不整除金额那行未报冲突：\(pair.conflicts)"
        )
        #expect(conflict.field.hasPrefix("amount"), "冲突字段 \(conflict.field) 不指向金额")

        // No rounded value is stored: neither floor (16) nor round (17) of 100/6.
        #expect(pair.hand.result.rakeCentiBB != 16, "抽水被向下取整")
        #expect(pair.hand.result.rakeCentiBB != 17, "抽水被四舍五入")
    }

    @Test("straddle 行登记为 straddle 冲突")
    func straddleConflicts() throws {
        // Constructed: appendix A with a straddle post inserted before HOLE CARDS.
        let base = try Fixtures.text("sample-ps-6max-nlhe.txt")
        let withStraddle = base.replacingOccurrences(
            of: "*** HOLE CARDS ***",
            with: "Villain4: posts straddle $2\n*** HOLE CARDS ***"
        )
        #expect(withStraddle != base, "straddle 行未插入")

        let pair = try #require(PokerStarsParser.parse(withStraddle).parsedPair)
        #expect(
            pair.conflicts.contains { $0.field == "straddle" },
            "未登记 straddle 冲突：\(pair.conflicts)"
        )
    }
}
