import Foundation
import PokerCore
import Testing
@testable import HandHistory

/// The hero's decision-point signatures, rebuilt deterministically from an
/// observed hand's betting.
@Suite("英雄决策点签名")
struct HeroDecisionSignatureTests {
    private func parseHand(_ fixture: String) throws -> ObservedHand {
        let text = try Fixtures.text(fixture)
        let hand = try #require(PokerStarsParser.parse(text).parsedPair?.hand)
        return hand
    }

    @Test("附录A四节点逐街：street、handClass、offset、facing、stackBucket 全部钉死")
    func appendixAFourNodesByStreet() throws {
        let hand = try parseHand("sample-ps-6max-nlhe.txt")
        let sigs = hand.heroDecisionSignatures()

        // The fixture really produced decisions.
        #expect(!sigs.isEmpty)
        #expect(sigs.count == 4)

        let expectedStreets: [Street] = [.preflop, .flop, .turn, .river]
        #expect(sigs.map(\.street) == expectedStreets)

        let ako = HandClass(Card(code: "Ah")!, Card(code: "Kd")!)
        for sig in sigs {
            #expect(sig.signature.handClass == ako)
            #expect(sig.signature.heroSeatOffsetFromButton == 0)
            #expect(sig.signature.facing == FacingAction(priorRaiseCount: 0))
        }

        // Effective stack falls each street as the hero commits chips.
        let expectedEffectiveStacks = [10_000, 9_700, 9_300, 9_300]
        let expectedBuckets = expectedEffectiveStacks.map {
            StackBucket(effectiveStack: BBAmount(centiBB: $0))
        }
        #expect(sigs.map(\.signature.stackBucket) == expectedBuckets)
    }

    @Test("面对加注：翻前面对恰一次加注得出 singleRaise，与附录 A 的 unopened 成对")
    func facingASingleRaise() throws {
        let hand = try parseHand("sample-ps-6max-vs-raise.txt")
        let sigs = hand.heroDecisionSignatures()

        // The fixture really produced a hero decision.
        #expect(!sigs.isEmpty)

        let preflop = try #require(sigs.first { $0.street == .preflop })
        #expect(preflop.signature.facing == FacingAction(priorRaiseCount: 1))

        // Paired with appendix A, whose sole preflop decision faces no raise.
        let appendixA = try parseHand("sample-ps-6max-nlhe.txt")
        let aPreflop = try #require(appendixA.heroDecisionSignatures().first { $0.street == .preflop })
        #expect(aPreflop.signature.facing == FacingAction(priorRaiseCount: 0))
        #expect(preflop.signature.facing != aPreflop.signature.facing)
    }

    @Test("跨筹码分桶：短筹英雄逐街加注，剩余有效筹码跨越分桶边界")
    func crossesStackBuckets() throws {
        // Appendix A's four decisions all sit at 100/97/93/93 BB — the same
        // `deep` bucket — so a derivation that always returns one bucket would
        // still pass that test. This hand starts the hero short ($40 = 4000
        // centi-BB) and has the hero build commitment across streets so the
        // remaining effective stack falls into a different bucket.
        let hand = try parseHand("sample-ps-6max-short-crossing.txt")
        let sigs = hand.heroDecisionSignatures()

        // The fixture really produced multiple hero decisions.
        #expect(!sigs.isEmpty)
        #expect(sigs.count >= 2)

        // The decisions do not all land in a single bucket — the property a
        // constant-bucket implementation cannot satisfy.
        #expect(Set(sigs.map(\.signature.stackBucket)).count >= 2)

        // The first decision (preflop 3-bet) still has the full 40 BB behind:
        // 4000 centi-BB → medium bucket.
        let first = try #require(sigs.first)
        #expect(first.street == .preflop)
        #expect(
            first.signature.stackBucket
                == StackBucket(effectiveStack: BBAmount(centiBB: 4_000))
        )
        #expect(first.signature.stackBucket == .medium)

        // By the turn the hero has committed $24 across preflop ($12) and flop
        // ($12), leaving 1600 centi-BB before the turn bet — across the 2000
        // boundary into the short bucket.
        let turn = try #require(sigs.first { $0.street == .turn })
        #expect(
            turn.signature.stackBucket
                == StackBucket(effectiveStack: BBAmount(centiBB: 1_600))
        )
        #expect(turn.signature.stackBucket == .short)

        // The two pinned decisions really disagree on bucket.
        #expect(first.signature.stackBucket != turn.signature.stackBucket)
    }
}
