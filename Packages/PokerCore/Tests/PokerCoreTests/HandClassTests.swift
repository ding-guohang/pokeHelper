import Testing
@testable import PokerCore

@Suite("起手牌类别")
struct HandClassTests {
    /// Exhaustive, not sampled. This round trip is the foundation the whole
    /// spot-equivalence relation sits on: if it fails for one class out of 169,
    /// equivalence goes silently wrong for exactly the hands in that class,
    /// which is the kind of defect a spot check does not find.
    @Test("全部 169 个类别的记号往返一致")
    func roundTripsEveryOneOfThe169Classes() throws {
        #expect(HandClass.all.count == 169)
        #expect(Set(HandClass.all).count == 169, "枚举里有重复")

        for handClass in HandClass.all {
            let notation = handClass.description
            let reparsed = try #require(
                HandClass(notation: notation),
                "\(notation) 无法被自己的记号解析回来"
            )
            #expect(reparsed == handClass)
            #expect(reparsed.description == notation)
        }
    }

    @Test("类别构成为 13 对子、78 同花、78 非同花")
    func hasTheExpectedShape() {
        let byKind = Dictionary(grouping: HandClass.all, by: \.suitedness)
        #expect(byKind[.pair]?.count == 13)
        #expect(byKind[.suited]?.count == 78)
        #expect(byKind[.offsuit]?.count == 78)
    }

    /// A signature built from a dealt hand and one built from a content range
    /// must agree, and neither side controls the other's card order.
    @Test("两张牌的给定顺序不影响归类")
    func classifiesIndependentlyOfCardOrder() {
        let deck = Self.deck
        var checked = 0

        for (index, first) in deck.enumerated() {
            for second in deck.dropFirst(index + 1) {
                #expect(HandClass(first, second) == HandClass(second, first))
                checked += 1
            }
        }

        #expect(checked == 1_326, "没有覆盖全部 1326 个组合，实际 \(checked)")
    }

    /// The 1,326 combinations must partition into the 169 classes with the
    /// textbook counts. This is what makes `combinationCount` usable as a
    /// weight when a range's frequency is derived from its cells.
    @Test("1326 个组合恰好落进 169 个类别，且各类计数为 6/4/12")
    func partitionsAllCombinationsWithTheRightWeights() {
        let deck = Self.deck
        var counts: [HandClass: Int] = [:]

        for (index, first) in deck.enumerated() {
            for second in deck.dropFirst(index + 1) {
                counts[HandClass(first, second), default: 0] += 1
            }
        }

        #expect(counts.count == 169)
        #expect(counts.values.reduce(0, +) == 1_326)
        for (handClass, count) in counts {
            #expect(
                count == handClass.combinationCount,
                "\(handClass) 实际 \(count) 个组合，声明 \(handClass.combinationCount)"
            )
        }
    }

    @Test("对子的记号不带后缀")
    func pairsCarryNoSuffix() {
        let pairs = HandClass.all.filter { $0.suitedness == .pair }
        #expect(pairs.count == 13)
        for pair in pairs {
            #expect(pair.description.count == 2)
            #expect(pair.highRank == pair.lowRank)
        }
    }

    /// Non-canonical spellings are rejected rather than normalised, so notation
    /// and value stay in bijection. `KAs` naming the same hand as `AKs` would
    /// make the round trip above lossy in one direction.
    @Test("非法或非规范记号被拒绝")
    func rejectsMalformedNotation() {
        for notation in [
            "", "A", "AKx", "ZZ", "AK", "AKso", "A Ks", "aks", "10s", "AKS",
            "KAs", "72S", "AAs", "AAo",
        ] {
            #expect(
                HandClass(notation: notation) == nil,
                "\(notation) 不该被接受"
            )
        }
    }

    /// The shipped content is the reason this type exists; every value in it
    /// has to parse, or spot equivalence is broken for real hands rather than
    /// for a hypothetical.
    @Test("已发布内容里的手牌记号全部可解析")
    func parsesEveryHandClassUsedByShippedContent() throws {
        // Sampled from PokerCoach/Resources/CoreStrategyPack.json, covering all
        // three shapes and both the strongest and the weakest cells in use.
        for notation in ["22", "AA", "AKs", "AKo", "53s", "72o", "T9s", "K2s"] {
            let parsed = try #require(
                HandClass(notation: notation),
                "内容里的 \(notation) 解析失败"
            )
            #expect(parsed.description == notation)
        }
    }

    @Test("rank 强度是严格升序且两两不同")
    func rankStrengthIsATotalOrder() {
        let strengths = Rank.allCases.map(\.strength)
        #expect(Set(strengths).count == Rank.allCases.count)
        #expect(strengths == strengths.sorted(), "allCases 的声明序不再是升序")
        #expect(Rank.two.strength == 0)
        #expect(Rank.ace.strength == 12)
    }

    private static let deck: [Card] = Rank.allCases.flatMap { rank in
        Suit.allCases.map { Card(rank: rank, suit: $0) }
    }
}
