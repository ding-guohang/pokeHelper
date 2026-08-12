import PokerCore
import Testing
@testable import SessionSimulation

/// Settlement invariants over many seeds rather than one.
///
/// The fixed-seed settlement test passes on its seed and would have passed on
/// a wrong assertion: only a fraction of hands are chops, so a short run has a
/// real chance of containing none of them. A property claimed to hold for every
/// hand has to be exercised on enough hands for its rare shapes to appear, and
/// a green fixed-seed test is not evidence the property is true.
///
/// This suite also stands guard over the blinds. Every hand that is dealt has
/// two blinds in it, so it has at least two contributors — a hand with fewer is
/// the blindless hand this milestone had to fix, and it used to hide here as a
/// zero-delta "walk" (a lone bet folded around, returned to its owner). That
/// shape can no longer occur: a session with fewer than two funded seats ends
/// instead of dealing a hand nobody can post a blind into, so a run may stop
/// short of `handsPerSeed`.
@Suite("结算不变量的多种子扫描")
struct SettlementSweepTests {
    private static let seedCount: UInt64 = 200
    private static let handsPerSeed = 15

    @Test("每一手都有两个盲注、每层底池都有赢家、底池被完整发出、筹码守恒")
    func settlementHoldsAcrossManySeeds() {
        var hands = 0
        var chops = 0
        var endedEarlySessions = 0
        var violations: [String] = []

        for seed in 1 ... Self.seedCount {
            let run = SessionRunner(seed: seed).run(handCount: Self.handsPerSeed)
            if run.endedEarly {
                endedEarlySessions += 1
            }
            for hand in run.hands {
                hands += 1
                let result = hand.result
                let deltas = result.stackDeltasCentiBB
                let paid = result.payouts.reduce(0) { $0 + $1.centiBB }
                let contributed = result.contributions.reduce(0) { $0 + $1.centiBB }
                let contributors = result.contributions.count { $0.centiBB > 0 }
                let where_ = "种子 \(seed) 第 \(hand.handIndex) 手"

                if deltas.reduce(0, +) != 0 {
                    violations.append("\(where_)：筹码变化之和 \(deltas.reduce(0, +))")
                }
                if paid != contributed || contributed != result.potTotal.centiBB {
                    violations.append("\(where_)：投入 \(contributed) 发出 \(paid) 底池 \(result.potTotal.centiBB)")
                }
                if result.rake.centiBB != 0 {
                    violations.append("\(where_)：抽水 \(result.rake.centiBB)")
                }
                // Two blinds are always posted, so a dealt hand always has at
                // least two seats with chips in the pot. This is the assertion
                // the blindless hand fails.
                if contributors < 2 {
                    violations.append("\(where_)：只有 \(contributors) 个投入者，盲注没有全部贴出")
                }
                for layer in result.pots where layer.winningSeats.isEmpty {
                    violations.append("\(where_)：一层底池 \(layer.amount.centiBB) 无人赢得")
                }

                guard !deltas.contains(where: { $0 > 0 }) else { continue }
                // A hand where nobody gained can now only be an even chop:
                // everyone got back exactly what they put in. A walk pays the
                // big blind the dead small blind, so it is not zero-delta, and
                // the blindless shape that used to land here no longer exists.
                let winners = Set(result.pots.flatMap(\.winningSeats))
                if winners.count > 1 {
                    chops += 1
                } else {
                    violations.append(
                        "\(where_)：无人获利却不是平分——投入者 \(contributors) 赢家 \(winners) 底池 \(result.potTotal.centiBB)"
                    )
                }
            }
        }

        #expect(hands <= Int(Self.seedCount) * Self.handsPerSeed)
        #expect(hands >= Int(Self.seedCount) * 10, "只打了 \(hands) 手，样本不足")
        #expect(violations.isEmpty, "\(violations.prefix(5).joined(separator: " | ")) …共 \(violations.count) 条")

        // The rare shape has to actually occur, or the zero-delta branch proves
        // nothing.
        #expect(chops > 0, "扫描里一次平分都没出现，样本不足以检验零增量的解释")
        // And a session that ran out of funded seats has to actually occur, or
        // the early-stop path is never exercised by this sweep.
        #expect(endedEarlySessions > 0, "扫描里没有任何一局因筹码耗尽而提前结束")
    }
}
