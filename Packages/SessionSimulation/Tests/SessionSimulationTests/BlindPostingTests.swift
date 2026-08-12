import PokerCore
import Testing
@testable import SessionSimulation

/// The blinds are posted every hand, even when the seats that would normally
/// post them have busted.
///
/// The engine used to post the small and big blind from fixed offsets 1 and 2
/// after the button and silently skip a seat with no chips. When both blind
/// seats had busted, a hand was dealt with no blinds at all: a lone bet folded
/// around returned to its owner and all six stacks moved by zero. Real cash
/// play never deals without a big blind — the blinds pass to the next seats
/// that still hold chips, and with fewer than two such seats there is no hand.
@Suite("每一手都有盲注")
struct BlindPostingTests {
    private static func seatsWithChips(_ stacks: [BBAmount]) -> Int {
        stacks.count { $0.centiBB > 0 }
    }

    /// Button on seat 0, so seat 1 is the small blind and seat 2 the big
    /// blind. Bust seat 1 and the small blind must move to seat 2 and the big
    /// blind to seat 3 — not vanish.
    @Test("盲注位破产时盲注顺延")
    func aBustedBlindSeatPassesTheBlindOn() {
        let dealt = SessionDealer(seed: 42).deal(handIndex: 0)
        #expect(dealt.buttonSeat == 0, "本用例假设按钮在 0 号座位")

        var stacks = [BBAmount](repeating: TableRules.startingStack, count: TableRules.seatCount)
        stacks[1] = BBAmount(centiBB: 0) // the normal small-blind seat has busted

        let state = HandState(dealtHand: dealt, stacks: stacks)
        let committed = state.seats.map(\.committedThisStreet.centiBB)

        #expect(committed[1] == 0, "破产的座位不应贴任何盲注")
        #expect(
            committed[2] == TableRules.smallBlind.centiBB,
            "小盲应顺延到按钮后第一个有筹码的座位（座位 2），实际投入 \(committed[2])"
        )
        #expect(
            committed[3] == TableRules.bigBlind.centiBB,
            "大盲应顺延到其后第一个有筹码的座位（座位 3），实际投入 \(committed[3])"
        )
        #expect(
            state.pot.centiBB == TableRules.smallBlind.centiBB + TableRules.bigBlind.centiBB,
            "行动开始前底池应为两个盲注之和，实际 \(state.pot.centiBB)"
        )
    }

    /// A homogeneous maniac table busts seats fast, which is exactly the
    /// condition that used to leave a hand with no blinds. Every hand that had
    /// at least two seats with chips at the start must have a non-zero pot
    /// before anyone acts.
    @Test("每一手行动前都收到盲注")
    func everyPlayableHandHasBlindsInThePotBeforeAction() {
        let seedCount: UInt64 = 200
        let handsPerSeed = 15
        var checkedHands = 0
        var handsWithABustedBlindSeat = 0
        var violations: [String] = []

        for seed in 1 ... seedCount {
            let dealer = SessionDealer(seed: seed)
            let run = SessionRunner(seed: seed, policy: OpponentProfileTable.policy(.maniac))
                .run(handCount: handsPerSeed)

            for hand in run.hands where Self.seatsWithChips(hand.startingStacks) >= 2 {
                checkedHands += 1

                let button = hand.buttonSeat
                let sb = TableRules.seat(atOffset: 1, buttonSeat: button)
                let bb = TableRules.seat(atOffset: 2, buttonSeat: button)
                if hand.startingStacks[sb].centiBB == 0 || hand.startingStacks[bb].centiBB == 0 {
                    handsWithABustedBlindSeat += 1
                }

                // Rebuild the hand's opening state to read the pot before any
                // action. `result.potTotal` is the pot at the end; this is the
                // pot the blinds alone put there.
                let opening = HandState(
                    dealtHand: dealer.deal(handIndex: hand.handIndex),
                    stacks: hand.startingStacks
                )
                if opening.pot.centiBB <= 0 {
                    violations.append("种子 \(seed) 第 \(hand.handIndex) 手开局底池为 \(opening.pot.centiBB)")
                }
            }
        }

        #expect(violations.isEmpty, "\(violations.prefix(5).joined(separator: " | ")) …共 \(violations.count) 条")
        #expect(checkedHands > 1000, "只检查了 \(checkedHands) 手，样本不足")
        // Non-vacuity: the invariant is only meaningful because the sweep
        // actually contains hands whose normal blind seats had busted. Without
        // this the fix could be checked entirely on hands that never exercised
        // the pass-on.
        #expect(
            handsWithABustedBlindSeat > 0,
            "扫描里没有任何一手的盲注位破产，没有检验到顺延"
        )
    }
}
