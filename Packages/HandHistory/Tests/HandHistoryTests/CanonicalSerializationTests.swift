import Foundation
import PokerCore
import Testing
@testable import HandHistory

/// The canonical serialization and the hand identity — neither of which needs
/// the parser, so they are exercised against a hand built by hand.
@Suite("规范序列化与身份")
struct CanonicalSerializationTests {
    /// A small but complete hand with every amount-bearing field populated.
    private func sampleHand() -> ObservedHand {
        ObservedHand(
            source: HandSource(rawText: "sample raw text\n"),
            site: .pokerStars,
            tableSize: 2,
            buttonSeat: 0,
            bigBlindCentiBB: 100,
            seats: [
                ObservedSeat(
                    seat: 1,
                    seatOffsetFromButton: 0,
                    startingStackCentiBB: 10000,
                    holeCards: .known(Card(code: "Ah")!, Card(code: "Kd")!)
                ),
                ObservedSeat(
                    seat: 2,
                    seatOffsetFromButton: 1,
                    startingStackCentiBB: 9000,
                    holeCards: .unknown
                ),
            ],
            forcedPosts: [
                ForcedPost(seat: 1, kind: .smallBlind, amountCentiBB: 50),
                ForcedPost(seat: 2, kind: .bigBlind, amountCentiBB: 100),
            ],
            streets: [
                ObservedStreet(
                    street: .preflop,
                    board: [],
                    actions: [
                        ObservedAction(seat: 1, kind: .raiseTo, amountCentiBB: 300),
                        ObservedAction(seat: 2, kind: .call, amountCentiBB: 300),
                    ]
                ),
            ],
            result: ObservedResult(rakeCentiBB: 50)
        )
    }

    @Test("金额字段名带单位，不含无单位的 stack/amount")
    func amountFieldNamesCarryUnits() throws {
        let json = String(decoding: try sampleHand().canonicalJSON(), as: UTF8.self)

        #expect(json.contains("startingStackCentiBB"))
        #expect(json.contains("amountCentiBB"))
        #expect(json.contains("rakeCentiBB"))
        #expect(json.contains("bigBlindCentiBB"))

        // The bare, unitless keys must not appear — a `"stack"` or `"amount"`
        // key would be exactly the ambiguity the units rule forbids. Checked as
        // JSON keys (quoted) so the substring inside "startingStackCentiBB" does
        // not trip it.
        #expect(!json.contains("\"stack\""))
        #expect(!json.contains("\"amount\""))
    }

    @Test("同一模型两次规范序列化逐字节相同")
    func twoSerializationsAreByteIdentical() throws {
        let hand = sampleHand()
        let first = try hand.canonicalJSON()
        let second = try hand.canonicalJSON()

        #expect(!first.isEmpty, "序列化产出为空")
        #expect(first == second, "同一模型两次序列化字节不同")
    }

    @Test("身份是原文行尾规范化后的 SHA-256")
    func identityIsNormalizedSHA256() {
        let crlf = HandSource(rawText: "a\r\nb")
        let lf = HandSource(rawText: "a\nb")
        let cr = HandSource(rawText: "a\rb")
        let different = HandSource(rawText: "a\nc")

        #expect(!lf.identity.isEmpty, "身份为空")
        #expect(crlf.identity == lf.identity, "CRLF 与 LF 身份不同")
        #expect(cr.identity == lf.identity, "CR 与 LF 身份不同")
        #expect(different.identity != lf.identity, "不同文本得到相同身份")
    }
}
