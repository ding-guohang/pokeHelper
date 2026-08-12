import PokerCore
import Testing
@testable import SessionSimulation

/// Settlement invariants over many seeds rather than one.
///
/// The fixed-seed settlement test passes on its seed and would have passed on
/// a wrong assertion: about 4% of hands are walks or chops, so a 30-hand run
/// has roughly a one-in-four chance of containing none of them. That is what
/// happened — the original "some player's delta is strictly positive" assertion
/// was green for 30 hands and false for 130 hands out of 3,000.
///
/// The lesson is not "add more seeds everywhere". It is that a property claimed
/// to hold for every hand has to be exercised on enough hands for its rare
/// shapes to appear, and that a green fixed-seed test is not evidence the
/// property is true.
@Suite("结算不变量的多种子扫描")
struct SettlementSweepTests {
    private static let seedCount: UInt64 = 200
    private static let handsPerSeed = 15

    @Test("3000 手内每层底池都有赢家、底池被完整发出、筹码守恒")
    func settlementHoldsAcrossManySeeds() {
        var hands = 0
        var walks = 0
        var chops = 0
        var violations: [String] = []

        for seed in 1 ... Self.seedCount {
            for hand in SessionRunner(seed: seed).run(handCount: Self.handsPerSeed).hands {
                hands += 1
                let result = hand.result
                let deltas = result.stackDeltasCentiBB
                let paid = result.payouts.reduce(0) { $0 + $1.centiBB }
                let contributed = result.contributions.reduce(0) { $0 + $1.centiBB }
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
                for layer in result.pots where layer.winningSeats.isEmpty {
                    violations.append("\(where_)：一层底池 \(layer.amount.centiBB) 无人赢得")
                }

                guard !deltas.contains(where: { $0 > 0 }) else { continue }
                // Every all-zero hand must be explicable. An unexplained one is
                // a pot that evaporated.
                let contributors = result.contributions.count { $0.centiBB > 0 }
                let winners = Set(result.pots.flatMap(\.winningSeats))
                if contributors == 1 {
                    walks += 1
                } else if winners.count > 1 {
                    chops += 1
                } else {
                    violations.append(
                        "\(where_)：无人获利且既非 walk 也非平分——投入者 \(contributors) 赢家 \(winners) 底池 \(result.potTotal.centiBB)"
                    )
                }
            }
        }

        #expect(hands == Int(Self.seedCount) * Self.handsPerSeed)
        #expect(violations.isEmpty, "\(violations.prefix(5).joined(separator: " | ")) …共 \(violations.count) 条")

        // The rare shapes have to actually occur, or this suite proves nothing
        // the single-seed test did not already cover.
        #expect(walks > 0, "扫描里一次 walk 都没出现，样本不足以检验零增量的解释")
        #expect(chops > 0, "扫描里一次平分都没出现，样本不足以检验零增量的解释")
    }
}
