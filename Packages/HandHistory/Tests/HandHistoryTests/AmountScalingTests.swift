import Foundation
import PokerCore
import Testing
@testable import HandHistory

/// Conversion to centi-BB is a function of the hand's stated big blind, not a
/// hardcoded `dollars * 100`. Appendix A ($1 BB) and a variant with every dollar
/// amount doubled ($2 BB) must both yield hero stack 10000 and big blind 100 —
/// which a constant multiplier cannot do for both.
@Suite("换算是大盲的函数")
struct AmountScalingTests {
    /// Doubles every `$N` / `$N.NN` amount in the text, preserving whether it had
    /// cents. Pure string replacement, done in-test so the variant is provably
    /// appendix A with amounts scaled and nothing else.
    private func doublingAllDollarAmounts(in text: String) -> String {
        let regex = try! NSRegularExpression(pattern: #"\$[0-9]+(\.[0-9]+)?"#)
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))

        var result = text
        for match in matches.reversed() {
            let token = ns.substring(with: match.range) // e.g. "$0.50" or "$1"
            let body = String(token.dropFirst())         // "0.50" or "1"
            let hadCents = body.contains(".")
            let cents: Int = {
                if hadCents {
                    let parts = body.split(separator: ".")
                    let dollars = Int(parts[0]) ?? 0
                    let fraction = String(parts[1]).padding(toLength: 2, withPad: "0", startingAt: 0)
                    return dollars * 100 + (Int(fraction) ?? 0)
                } else {
                    return (Int(body) ?? 0) * 100
                }
            }()
            let doubled = cents * 2
            let replacement = hadCents
                ? String(format: "$%d.%02d", doubled / 100, doubled % 100)
                : "$\(doubled / 100)"
            let swiftRange = Range(match.range, in: result)!
            result.replaceSubrange(swiftRange, with: replacement)
        }
        return result
    }

    @Test("附录 A 与其金额翻倍变体都得到大盲 100、英雄起始筹码 10000")
    func conversionScalesWithBigBlind() throws {
        let a = try Fixtures.text("sample-ps-6max-nlhe.txt")
        let doubled = doublingAllDollarAmounts(in: a)

        // The variant really doubled the stakes, else this proves nothing.
        #expect(a.contains("($0.50/$1.00 USD)"))
        #expect(doubled.contains("($1.00/$2.00 USD)"), "变体大盲未翻倍：\(doubled.prefix(120))")
        #expect(doubled.contains("Hero ($200 in chips)"), "变体筹码未翻倍")

        func heroStackAndBB(_ text: String) throws -> (stack: Int, bb: Int) {
            let hand = try #require(PokerStarsParser.parse(text).parsedPair, "未解析").hand
            let hero = try #require(hand.seats.first { $0.seat == 1 })
            return (hero.startingStackCentiBB, hand.bigBlindCentiBB)
        }

        let base = try heroStackAndBB(a)
        let scaled = try heroStackAndBB(doubled)

        #expect(base.stack == 10000)
        #expect(base.bb == 100)
        #expect(scaled.stack == 10000, "翻倍变体英雄筹码 \(scaled.stack)，硬编码常量会在此失败")
        #expect(scaled.bb == 100)
    }
}
