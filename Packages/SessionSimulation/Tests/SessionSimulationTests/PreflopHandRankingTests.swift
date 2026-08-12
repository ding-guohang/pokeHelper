import PokerCore
import Testing
@testable import SessionSimulation

/// The ordering the profiles' entry rates are defined against.
///
/// It is worth its own suite because everything about a stated entry rate rests
/// on it: "the strongest 44%" only means something if the ordering is total, is
/// over all 169 classes, and maps each one to the right share of the deck. A
/// collision in the lookup index would give two classes the same percentile and
/// leave a hole somewhere else — a defect that shows up as an opponent playing
/// a hand it should fold, and nowhere else.
@Suite("翻前起手牌排序")
struct PreflopHandRankingTests {
    @Test("169 个类别恰好各出现一次，共 1326 个组合")
    func theOrderingCoversEveryClassExactlyOnce() {
        let ordered = PreflopHandRanking.strongestFirst
        #expect(ordered.count == 169)
        #expect(Set(ordered).count == 169, "排序里有重复的类别")
        #expect(Set(ordered) == Set(HandClass.all), "排序与 169 格的集合不一致")
        #expect(
            ordered.reduce(0) { $0 + $1.combinationCount } == PreflopHandRanking.combinationCount
        )
    }

    @Test("百分位沿排序严格递增，从最强到 10000")
    func percentilesRiseWithTheOrdering() {
        let ordered = PreflopHandRanking.strongestFirst
        var previous = 0

        for handClass in ordered {
            let percentile = PreflopHandRanking.percentileBasisPoints(handClass)
            #expect(
                percentile > previous,
                "\(handClass) 的百分位 \(percentile) 没有比上一个 \(previous) 大"
            )
            #expect((1 ... 10_000).contains(percentile), "\(handClass) 的百分位是 \(percentile)")
            previous = percentile
        }

        #expect(previous == 10_000, "最弱的类别的百分位是 \(previous)，不是 10000")
        #expect(Set(HandClass.all.map(PreflopHandRanking.percentileBasisPoints)).count == 169)
    }

    /// Spot checks against the published formula rather than against the
    /// implementation. Chen is a fixed, citable ordering: aces first, the
    /// premium pairs and big suited aces near the top, and a suited hand always
    /// ahead of the same two ranks offsuit.
    @Test("排序符合 Chen 公式的已知结果")
    func theOrderingMatchesTheKnownShapeOfChensFormula() throws {
        func handClass(_ notation: String) throws -> HandClass {
            try #require(HandClass(notation: notation), "无法解析 \(notation)")
        }

        #expect(PreflopHandRanking.strongestFirst.first == (try handClass("AA")))
        #expect(PreflopHandRanking.percentileBasisPoints(try handClass("AA")) == 45)

        // Pairs descend in order.
        let pairs = ["AA", "KK", "QQ", "JJ", "TT", "99", "88", "77"]
        for (stronger, weaker) in zip(pairs, pairs.dropFirst()) {
            #expect(
                PreflopHandRanking.percentileBasisPoints(try handClass(stronger))
                    < PreflopHandRanking.percentileBasisPoints(try handClass(weaker)),
                "\(stronger) 没有排在 \(weaker) 前面"
            )
        }

        // Suited beats offsuit, for every pair of distinct ranks.
        for high in Rank.allCases {
            for low in Rank.allCases where low.strength < high.strength {
                let suited = try handClass(high.rawValue + low.rawValue + "s")
                let offsuit = try handClass(high.rawValue + low.rawValue + "o")
                #expect(
                    PreflopHandRanking.percentileBasisPoints(suited)
                        < PreflopHandRanking.percentileBasisPoints(offsuit),
                    "\(suited) 没有排在 \(offsuit) 前面"
                )
            }
        }

        // The worst hand in hold'em, and it should be last.
        #expect(PreflopHandRanking.strongestFirst.last == (try handClass("72o")))
    }
}
