import PokerCore
import Testing
@testable import SessionSimulation

/// Which hands a finished session offers up for review.
///
/// The score table is fixed in design.md decision 4 and reproduced in
/// `KeyHandSelection`. These tests are about the two things a scoring table can
/// get wrong and still look right: picking hands for a reason other than the one
/// it reports, and degenerating into "the first five hands" — the failure the
/// proposal's risk list names by name.
@Suite("关键手选择")
struct KeyHandSelectionTests {
    private static let seed: UInt64 = 42
    private static let handCount = 30

    private func session(handCount: Int = handCount) -> [SessionHandRecord] {
        SessionRunner(seed: Self.seed)
            .run(handCount: handCount)
            .hands
            .map(SessionHandRecord.init)
    }

    // GIVEN 一局已完成的 30 手 Session
    // WHEN 打开复盘
    // THEN 列出 3 到 5 手关键手
    // AND 标记 .bigPot 的手，其底池必须是该 Session 底池最大的 5 手之一
    @Test("完成 Session 后给出 3 到 5 手关键手")
    func aFinishedSessionYieldsBetweenThreeAndFiveKeyHands() {
        let hands = session()
        #expect(hands.count == Self.handCount, "夹具只打了 \(hands.count) 手")

        let selected = KeyHandSelection.select(from: hands, heroActionWeightsBasisPoints: [:])

        #expect(selected.count >= 3, "只选出 \(selected.count) 手")
        #expect(selected.count <= 5, "选出了 \(selected.count) 手")
        #expect(
            Set(selected.map(\.handIndex)).count == selected.count,
            "同一手被选了两次：\(selected.map(\.handIndex))"
        )
        #expect(
            selected.allSatisfy { key in hands.contains { $0.handIndex == key.handIndex } },
            "选出了不属于这局 Session 的手牌编号"
        )

        // Descending by score, which is the order the review screen shows.
        #expect(
            selected.map(\.score) == selected.map(\.score).sorted(by: >),
            "分数不是降序：\(selected.map(\.score))"
        )

        let biggestPots = Set(
            hands
                .sorted { lhs, rhs in
                    lhs.result.potTotal != rhs.result.potTotal
                        ? lhs.result.potTotal > rhs.result.potTotal
                        : lhs.handIndex < rhs.handIndex
                }
                .prefix(5)
                .map(\.handIndex)
        )
        let markedBigPot = selected.filter { $0.reason == .bigPot }
        // Without this the implication below is satisfied by a selection that
        // never marks anything `.bigPot` at all.
        #expect(!markedBigPot.isEmpty, "这局没有一手以 .bigPot 入选，下面的断言是空转的")
        for key in markedBigPot {
            #expect(
                biggestPots.contains(key.handIndex),
                "第 \(key.handIndex) 手标记为 .bigPot，但它的底池不在最大的 5 手里"
            )
        }
    }

    // AND 标记 .bigSwing 的手，其英雄筹码变化绝对值不小于 20BB
    //
    // Built rather than drawn from a session: swept 300 seeds × 30 hands and
    // `.bigSwing` was the displayed reason in none of them, because a hand that
    // swings 20BB almost always also carries an all-in or a top-five pot, both
    // of which outscore it. Asserting the rule on a real session would be
    // asserting it over an empty set.
    @Test("标记 bigSwing 的手，英雄筹码变化不小于 20BB")
    func aHandMarkedBigSwingReallySwung() {
        let facts = [
            KeyHandFacts(handIndex: 0, potTotalCentiBB: 3_000, sawAllIn: false, heroStackDeltaCentiBB: -2_500),
            KeyHandFacts(handIndex: 1, potTotalCentiBB: 1_000, sawAllIn: false, heroStackDeltaCentiBB: 0),
            KeyHandFacts(handIndex: 2, potTotalCentiBB: 1_100, sawAllIn: false, heroStackDeltaCentiBB: 0),
            KeyHandFacts(handIndex: 3, potTotalCentiBB: 1_200, sawAllIn: false, heroStackDeltaCentiBB: 0),
            KeyHandFacts(handIndex: 4, potTotalCentiBB: 1_300, sawAllIn: false, heroStackDeltaCentiBB: 0),
            KeyHandFacts(handIndex: 5, potTotalCentiBB: 100, sawAllIn: false, heroStackDeltaCentiBB: 0),
        ]

        let selected = KeyHandSelection.select(from: facts)
        let swings = selected.filter { $0.reason == .bigSwing }
        #expect(!swings.isEmpty, "夹具没有产生任何 .bigSwing 入选，断言是空转的")

        for key in swings {
            let fact = facts.first { $0.handIndex == key.handIndex }
            #expect(
                abs(fact?.heroStackDeltaCentiBB ?? 0) >= 2_000,
                "第 \(key.handIndex) 手标记为 .bigSwing，变化却只有 \(fact?.heroStackDeltaCentiBB ?? 0)"
            )
        }
    }

    // GIVEN 一局 15 手 Session，每手底池均不超过 3BB，第 4 手 3.0BB 为全局最大、第 9 手 2.9BB 次之
    // WHEN 打开复盘
    // THEN 列表非空，按选择分数降序排列
    // AND 首项为第 4 手
    //
    // "第 4 手" is the fourth hand, which the records index as 3.
    @Test("全部小底池的 Session 仍然给出关键手")
    func aSessionOfNothingButSmallPotsStillHasKeyHands() {
        let pots = [100, 150, 200, 300, 120, 130, 140, 160, 290, 110, 170, 180, 190, 210, 220]
        let facts = pots.enumerated().map { index, pot in
            KeyHandFacts(
                handIndex: index,
                potTotalCentiBB: pot,
                sawAllIn: false,
                heroStackDeltaCentiBB: 0
            )
        }
        #expect(pots.allSatisfy { $0 <= 300 }, "夹具的底池超过了 3BB")
        #expect(pots.max() == pots[3], "夹具里最大的底池不是第 4 手")

        let selected = KeyHandSelection.select(from: facts)

        #expect(!selected.isEmpty)
        #expect(selected.count >= 3 && selected.count <= 5, "选出了 \(selected.count) 手")
        #expect(selected.map(\.score) == selected.map(\.score).sorted(by: >))
        #expect(selected.first?.handIndex == 3, "首项是第 \(selected.first?.handIndex ?? -1) 号手牌")
        #expect(selected.dropFirst().first?.handIndex == 8, "次项不是次大底池的第 9 手")
    }

    // GIVEN 两局同种子 Session，第二局把第 11 至 15 手的底池放大
    // WHEN 分别打开复盘
    // THEN 两次选出的手牌编号集合不同
    // AND 第二次选出的手牌至少包含第 11 至 15 手中的两手
    @Test("关键手不是「取前五手」")
    func enlargingTheLateHandsChangesTheSelection() {
        let hands = session(handCount: 15)
        #expect(hands.count == 15)

        let asPlayed = hands.map { KeyHandFacts($0, heroActionWeightBasisPoints: nil) }
        // The eleventh through fifteenth hands, which the records index 10–14.
        let lateIndices = Set(10 ... 14)
        let enlarged = asPlayed.map { fact in
            guard lateIndices.contains(fact.handIndex) else {
                return fact
            }
            return KeyHandFacts(
                handIndex: fact.handIndex,
                potTotalCentiBB: fact.potTotalCentiBB + 12_000,
                sawAllIn: fact.sawAllIn,
                heroStackDeltaCentiBB: fact.heroStackDeltaCentiBB
            )
        }
        // The second session really is the first one with bigger late pots and
        // nothing else changed.
        for (before, after) in zip(asPlayed, enlarged) {
            #expect(before.handIndex == after.handIndex)
            #expect(before.sawAllIn == after.sawAllIn)
            #expect(before.heroStackDeltaCentiBB == after.heroStackDeltaCentiBB)
            if lateIndices.contains(before.handIndex) {
                #expect(after.potTotalCentiBB > before.potTotalCentiBB, "第 \(before.handIndex) 手的底池没有变大")
            } else {
                #expect(after.potTotalCentiBB == before.potTotalCentiBB)
            }
        }

        let first = Set(KeyHandSelection.select(from: asPlayed).map(\.handIndex))
        let second = Set(KeyHandSelection.select(from: enlarged).map(\.handIndex))

        #expect(first != second, "放大后五手的底池之后，选出的仍然是同一批手牌 \(first)")
        #expect(
            second.intersection(lateIndices).count >= 2,
            "第二次只选出了 \(second.intersection(lateIndices).count) 手第 11 至 15 手"
        )
        // The failure mode the scenario is named after.
        #expect(first != Set(0 ... 4), "第一次选的就是前五手")
        #expect(second != Set(0 ... 4), "第二次选的就是前五手")
    }

    @Test("并列时按手牌序号升序，且与输入顺序无关")
    func tiesBreakOnTheHandIndex() {
        let facts = (0 ..< 8).map { index in
            KeyHandFacts(
                handIndex: index,
                potTotalCentiBB: 500,
                sawAllIn: false,
                heroStackDeltaCentiBB: 0
            )
        }

        let selected = KeyHandSelection.select(from: facts)
        #expect(
            Set(selected.map(\.score)).count == 1,
            "夹具没有产生并列，无法检验 tie-break：\(selected.map(\.score))"
        )
        #expect(selected.map(\.handIndex) == [0, 1, 2, 3, 4], "并列时选出的是 \(selected.map(\.handIndex))")

        // Same hands, handed over in another order. A selection that fell back
        // on input order, dictionary order or `hashValue` would move here.
        let shuffled = Array(facts.reversed())
        #expect(
            KeyHandSelection.select(from: shuffled) == selected,
            "换一个输入顺序就选出了 \(KeyHandSelection.select(from: shuffled).map(\.handIndex))"
        )
    }

    // 不足 3 手时取全部。
    @Test("手数少于 3 时取全部，否则取 3 到 5 手")
    func theCountFollowsTheSessionLength() {
        for handCount in 0 ... 8 {
            let facts = (0 ..< handCount).map { index in
                KeyHandFacts(
                    handIndex: index,
                    potTotalCentiBB: 100 + index * 10,
                    sawAllIn: false,
                    heroStackDeltaCentiBB: 0
                )
            }
            let selected = KeyHandSelection.select(from: facts)

            #expect(selected.count == min(handCount, 5), "\(handCount) 手的 Session 选出了 \(selected.count) 手")
            if handCount < 3 {
                #expect(selected.count == handCount, "\(handCount) 手的 Session 没有全部选出")
            } else {
                #expect(selected.count >= 3 && selected.count <= 5)
            }
        }
    }

    // AND 每一手的入选原因为 .deviation、.allIn、.bigSwing、.bigPot 之一——当一手同时
    // 满足多个判据时，展示的是分数最高的那个。
    @Test("一手命中多个判据时展示分数最高的原因")
    func aHandThatQualifiesTwiceReportsItsHighestScoringReason() {
        // Qualifies on all four rows. 5000 + (10000 − 4000) = 11000 for the
        // deviation, 4000 + 8000 = 12000 for the all-in, 3000 + 7000 = 10000
        // for the swing, 2000 + 8000 = 10000 for the pot. The all-in wins, so
        // `.deviation` being written at the top of the table is not by itself
        // what decides the reason.
        let everything = KeyHandFacts(
            handIndex: 0,
            potTotalCentiBB: 8_000,
            sawAllIn: true,
            heroStackDeltaCentiBB: -7_000,
            heroActionWeightBasisPoints: 4_000
        )
        // 3000 + 2500 = 5500 for the swing, 2000 + 10000 = 12000 for the pot:
        // the bigger pot wins even though the swing is listed above it in the
        // table. This is what makes the rule "highest score" rather than
        // "first matching row".
        let deepPotSmallSwing = KeyHandFacts(
            handIndex: 1,
            potTotalCentiBB: 10_000,
            sawAllIn: false,
            heroStackDeltaCentiBB: -2_500
        )
        let facts = [everything, deepPotSmallSwing]
            + (2 ... 4).map {
                KeyHandFacts(handIndex: $0, potTotalCentiBB: 200, sawAllIn: false, heroStackDeltaCentiBB: 0)
            }

        let selected = KeyHandSelection.select(from: facts)
        let byIndex = Dictionary(uniqueKeysWithValues: selected.map { ($0.handIndex, $0) })

        #expect(byIndex[0]?.reason == .allIn, "同时命中四项时展示的是 \(String(describing: byIndex[0]?.reason))")
        #expect(byIndex[0]?.score == 12_000)
        #expect(byIndex[1]?.reason == .bigPot, "底池分数更高时展示的是 \(String(describing: byIndex[1]?.reason))")
        #expect(byIndex[1]?.score == 12_000)
    }

    // GIVEN 一局 Session 中，第 3 手英雄在被内容覆盖的局面上做出了范围表权重为 0 的行动，
    //       第 8 手是全局最大底池但英雄的行动与范围表一致
    // WHEN 打开复盘
    // THEN 第 3 手排在第 8 手之前
    // AND 第 3 手的原因为 .deviation，第 8 手不是
    //
    // "第 3 手" and "第 8 手" are the third and eighth hands, indexed 2 and 7.
    @Test("偏离内容范围的手排在纯粹大底池之前")
    func aDeviationOutranksAPotThatWasMerelyLarge() throws {
        let deviatingIndex = 2
        let biggestPotIndex = 7
        let facts = (0 ..< 15).map { index in
            KeyHandFacts(
                handIndex: index,
                potTotalCentiBB: index == biggestPotIndex ? 6_000 : 300 + index * 10,
                sawAllIn: false,
                heroStackDeltaCentiBB: 0,
                // Covered either way. The third hand took a line the range
                // never takes; the eighth took the one it always takes.
                heroActionWeightBasisPoints: index == deviatingIndex
                    ? 0
                    : (index == biggestPotIndex ? 10_000 : nil)
            )
        }

        // The fixture really is the shape the scenario describes: the eighth
        // hand has the session's largest pot, the third hand's is unremarkable,
        // and only the third hand departed from the range.
        let deviating = try #require(facts.first { $0.handIndex == deviatingIndex })
        let biggest = try #require(facts.first { $0.handIndex == biggestPotIndex })
        #expect(biggest.potTotalCentiBB == facts.map(\.potTotalCentiBB).max())
        #expect(deviating.potTotalCentiBB < biggest.potTotalCentiBB)
        #expect(deviating.heroActionWeightBasisPoints == 0)
        #expect(biggest.heroActionWeightBasisPoints == 10_000)
        #expect(!deviating.sawAllIn && !biggest.sawAllIn)
        #expect(abs(deviating.heroStackDeltaCentiBB) < KeyHandSelection.bigSwingThresholdCentiBB)

        let selected = KeyHandSelection.select(from: facts)
        let order = selected.map(\.handIndex)
        let byIndex = Dictionary(uniqueKeysWithValues: selected.map { ($0.handIndex, $0) })

        // Both are on the list, otherwise "before" is a statement about
        // something that is not being shown.
        let deviatingPlace = try #require(order.firstIndex(of: deviatingIndex), "偏离的第 3 手没有入选：\(order)")
        let biggestPlace = try #require(order.firstIndex(of: biggestPotIndex), "最大底池的第 8 手没有入选：\(order)")
        #expect(deviatingPlace < biggestPlace, "第 3 手排在第 8 手之后：\(order)")
        #expect(byIndex[deviatingIndex]?.reason == .deviation,
                "第 3 手的原因是 \(String(describing: byIndex[deviatingIndex]?.reason))")
        #expect(byIndex[biggestPotIndex]?.reason != .deviation,
                "第 8 手也被标成了偏离")
        #expect(byIndex[deviatingIndex]?.score == 15_000)
    }

    // GIVEN 一手的翻前局面在已安装内容里没有覆盖
    // WHEN 选关键手
    // THEN 该手的原因不可能是 .deviation
    // AND 它仍可因底池、全下或波动入选
    @Test("内容未覆盖的手不会被标为偏离")
    func anUncoveredHandIsNeverADeviation() throws {
        let uncoveredIndex = 3
        func facts(weightForUncovered weight: Int?) -> [KeyHandFacts] {
            (0 ..< 10).map { index in
                KeyHandFacts(
                    handIndex: index,
                    // Big enough to be selected on its own merits, small enough
                    // that a deviation would outrank it if one were found.
                    potTotalCentiBB: index == uncoveredIndex ? 5_000 : 200 + index * 10,
                    sawAllIn: index == uncoveredIndex,
                    heroStackDeltaCentiBB: index == uncoveredIndex ? -2_500 : 0,
                    heroActionWeightBasisPoints: index == uncoveredIndex ? weight : nil
                )
            }
        }

        let uncovered = KeyHandSelection.select(from: facts(weightForUncovered: nil))
        let byIndex = Dictionary(uniqueKeysWithValues: uncovered.map { ($0.handIndex, $0) })
        let hand = try #require(byIndex[uncoveredIndex], "未覆盖的这手根本没入选，断言是空转的")

        #expect(hand.reason != .deviation, "未覆盖的手被标成了偏离")
        #expect(hand.reason == .allIn, "它应当仍因全下入选，实际是 \(hand.reason)")
        #expect(uncovered.first?.handIndex == uncoveredIndex, "它没有排在最前：\(uncovered.map(\.handIndex))")

        // The same hand, the same pot, the same all-in — the only thing that
        // changed is that content now covers it and says the hero's line has no
        // weight. Without this the assertion above is also satisfied by an
        // implementation that never produces `.deviation` at all.
        let covered = KeyHandSelection.select(from: facts(weightForUncovered: 0))
        let coveredHand = try #require(covered.first { $0.handIndex == uncoveredIndex })
        #expect(coveredHand.reason == .deviation, "覆盖且权重为 0 时的原因是 \(coveredHand.reason)")
    }

    /// The threshold is a strict `<`, and the score falls as the weight rises.
    /// Both halves matter: an implementation that flagged everything covered
    /// would satisfy the two scenarios above, and one that scored every
    /// deviation the same would order two of them by hand index.
    @Test("权重 5000 及以上不算偏离，权重越低分数越高")
    func theDeviationThresholdAndScoreFollowTheWeight() {
        func reason(forWeight weight: Int?) -> (KeyHandReason, Int)? {
            // One hand, so `.bigPot` always applies and there is always a row
            // to fall back on — the question is only whether `.deviation`
            // outranks it.
            let selected = KeyHandSelection.select(from: [
                KeyHandFacts(
                    handIndex: 0,
                    potTotalCentiBB: 100,
                    sawAllIn: false,
                    heroStackDeltaCentiBB: 0,
                    heroActionWeightBasisPoints: weight
                ),
            ])
            return selected.first.map { ($0.reason, $0.score) }
        }

        #expect(reason(forWeight: nil)?.0 == .bigPot)
        #expect(reason(forWeight: 5_000)?.0 == .bigPot, "权重恰好 5000 被算成了偏离")
        #expect(reason(forWeight: 10_000)?.0 == .bigPot)
        #expect(reason(forWeight: 4_999)?.0 == .deviation, "权重 4999 没有被算成偏离")

        #expect(reason(forWeight: 4_999)?.1 == 10_001)
        #expect(reason(forWeight: 2_500)?.1 == 12_500)
        #expect(reason(forWeight: 0)?.1 == 15_000)
    }

    /// The all-in test the spec's wording invites getting wrong: `.allIn` is not
    /// the only way all the chips go in. A call for one's whole stack is the
    /// all-in — `cash-decision-domain` says so — and a blind post capped to a
    /// short stack is too. Over 60 seeds × 30 hands, 267 hands put somebody all
    /// in and only 236 of them contain an `.allIn` action.
    @Test("跟光筹码也算全下，不只看 allIn 行动")
    func anAllInIsAboutTheChipsNotTheActionName() {
        var chipsAllIn = 0
        var namedAllIn = 0
        var chipsOnly: [(UInt64, Int)] = []

        for seed in UInt64(1) ... 60 {
            for hand in SessionRunner(seed: seed).run(handCount: 30).hands.map(SessionHandRecord.init) {
                let byChips = KeyHandFacts(hand, heroActionWeightBasisPoints: nil).sawAllIn
                let byName = hand.actions.contains {
                    if case .allIn = $0.action { true } else { false }
                }
                if byChips { chipsAllIn += 1 }
                if byName { namedAllIn += 1 }
                if byChips && !byName { chipsOnly.append((seed, hand.handIndex)) }
                #expect(!byName || byChips, "种子 \(seed) 第 \(hand.handIndex) 手有 allIn 行动却没算全下")
            }
        }

        #expect(namedAllIn > 0, "扫描里没有任何 allIn 行动，断言是空转的")
        #expect(
            !chipsOnly.isEmpty,
            "没有一手是「把筹码跟光但没有 allIn 行动」，这条判据没有被区分开"
        )
        #expect(chipsAllIn > namedAllIn)
    }

    @Test("没有手牌就没有关键手")
    func anEmptySessionHasNoKeyHands() {
        #expect(KeyHandSelection.select(from: [] as [KeyHandFacts]).isEmpty)
        #expect(KeyHandSelection.select(from: [], heroActionWeightsBasisPoints: [:]).isEmpty)
    }

    /// The range weight is an input, not something the engine looks up. This
    /// package cannot see installed content, and the layering gate enforces it;
    /// the assertion here is only that what the caller passes in arrives, and
    /// that "absent" and "zero" stay distinguishable — they mean opposite
    /// things and a dictionary lookup is the easiest place to conflate them.
    ///
    /// The other three facts are read off the record, and are pinned to the
    /// sixth hand of seed 42 by value: the hero loses 93.50BB into a 188.00BB
    /// pot with a stack in the middle. Values rather than a restatement of the
    /// expression, so that reading the wrong seat's delta is a red test.
    @Test("四项判据由记录算出，范围权重由调用方传入")
    func theFactsComeFromTheRecordAndTheCaller() throws {
        let hands = session(handCount: 15)
        let facts = KeyHandSelection.facts(
            for: hands,
            heroActionWeightsBasisPoints: [2: 0, 5: 7_500]
        )

        #expect(facts.count == 15)
        #expect(
            facts.filter { $0.heroActionWeightBasisPoints != nil }.map(\.handIndex) == [2, 5],
            "带权重的是 \(facts.filter { $0.heroActionWeightBasisPoints != nil }.map(\.handIndex))"
        )
        #expect(facts.first { $0.handIndex == 2 }?.heroActionWeightBasisPoints == 0)
        #expect(facts.first { $0.handIndex == 5 }?.heroActionWeightBasisPoints == 7_500)
        #expect(
            KeyHandSelection
                .facts(for: hands, heroActionWeightsBasisPoints: [:])
                .allSatisfy { $0.heroActionWeightBasisPoints == nil }
        )

        let sixth = try #require(facts.first { $0.handIndex == 5 })
        #expect(sixth.potTotalCentiBB == 18_800, "第 6 手底池是 \(sixth.potTotalCentiBB)")
        #expect(sixth.heroStackDeltaCentiBB == -9_350, "英雄筹码变化是 \(sixth.heroStackDeltaCentiBB)")
        #expect(sixth.sawAllIn)

        // A hand from the same session where nobody's stack went in, so the
        // flag above is not simply always true.
        let second = try #require(facts.first { $0.handIndex == 1 })
        #expect(!second.sawAllIn)
        #expect(second.potTotalCentiBB == 525)
        #expect(second.heroStackDeltaCentiBB == 0)
    }
}
