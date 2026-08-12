import PokerCore
import Testing
@testable import SessionSimulation

/// The pairing `SessionHandRecord.heroSpots` rests on.
///
/// A record stores the hero's spot signatures and the whole action log
/// separately, and pairing them is a `zip` — which is exactly the operation
/// that hides a length mismatch by silently truncating. If the two ever came
/// apart, the app layer would look up the weight of the *previous* decision's
/// action and a review screen would tell the user they deviated on a hand they
/// played straight. Nothing about that would be visible without this test.
@Suite("英雄决策与行动的配对")
struct SessionHandRecordTests {
    @Test("每个英雄决策点恰好对应一个英雄行动")
    func heroSignaturesAndActionsStayInStep() {
        var totalSpots = 0
        var handsWithSeveralHeroDecisions = 0
        var handsWithPostflopHeroDecisions = 0

        for seed in UInt64(1) ... 40 {
            for hand in SessionRunner(seed: seed).run(handCount: 30).hands.map(SessionHandRecord.init) {
                #expect(
                    hand.heroSpotSignatures.count == hand.heroActions.count,
                    "种子 \(seed) 第 \(hand.handIndex) 手：\(hand.heroSpotSignatures.count) 个决策点，\(hand.heroActions.count) 个行动"
                )

                let spots = hand.heroSpots
                #expect(spots.count == hand.heroSpotSignatures.count)
                totalSpots += spots.count
                if spots.count > 1 { handsWithSeveralHeroDecisions += 1 }

                // The streets have to line up too: equal counts alone would
                // survive a pairing that was off by a whole street, and a
                // preflop signature carrying a river action is the shape the
                // failure would take.
                let heroActionStreets = hand.actions
                    .filter { $0.seat == TableRules.heroSeat }
                    .map(\.street)
                #expect(spots.map(\.signature.street) == heroActionStreets)
                #expect(spots.map(\.action) == hand.heroActions)

                if spots.contains(where: { $0.signature.street != .preflop }) {
                    handsWithPostflopHeroDecisions += 1
                }
            }
        }

        // Without these the sweep above is satisfied by hands where the hero
        // never acted, or acted exactly once on one street — neither of which
        // exercises the alignment the pairing can get wrong.
        #expect(totalSpots > 0, "扫描里英雄一次都没行动，断言是空转的")
        #expect(handsWithSeveralHeroDecisions > 0, "没有一手英雄行动超过一次")
        #expect(handsWithPostflopHeroDecisions > 0, "没有一手英雄在翻后行动过")
    }
}
