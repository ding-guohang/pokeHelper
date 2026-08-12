import PokerCore

/// The 169 starting-hand classes in a fixed strength order, and where each one
/// falls in that order as a share of the 1,326 two-card combinations.
///
/// This exists so that an opponent profile's stated entry rate can be a
/// *definition* rather than a description. "Enters 45% of hands" means exactly
/// "plays the classes whose combinations make up the strongest 45% of the
/// 1,326", and a test can check the two agree to within one class's width.
/// Without an ordering, an entry rate is a number on a screen that nothing in
/// the code is obliged to honour.
///
/// The ordering is Chen's formula. It is a published heuristic from 1998, not a
/// solver output, and it is wrong at the margins — it likes small pairs more
/// than modern ranges do. That is acceptable and it is the point: the profiles
/// are disclosed as fixed heuristics, so the ordering behind them has to be
/// something a user could look up and disagree with, not a private table whose
/// provenance nobody can state.
public enum PreflopHandRanking {
    /// Chen's formula with every value doubled.
    ///
    /// Chen works in halves — a ten is worth 5, a nine 4.5 — so doubling keeps
    /// the whole computation in integers. Only the ordering is used, and
    /// doubling preserves it exactly, which is why the final round-up step of
    /// the published formula is omitted rather than approximated.
    static func chenScoreDoubled(_ handClass: HandClass) -> Int {
        let high = handClass.highRank
        let low = handClass.lowRank
        let highPoints = pointsDoubled(high)

        // A pair is worth twice its high card, with a floor: deuces score 5 in
        // the published formula rather than 1.
        if handClass.suitedness == .pair {
            return max(10, highPoints * 2)
        }

        var score = highPoints
        if handClass.suitedness == .suited {
            score += 4
        }

        // Cards between the two, so a connector gaps zero.
        let gap = high.strength - low.strength - 1
        switch gap {
        case 0: break
        case 1: score -= 2
        case 2: score -= 4
        case 3: score -= 8
        default: score -= 10
        }

        // Chen's straight bonus: connected or one-gapped, both cards below a
        // queen. The high card carries the test — if it is below a queen the
        // low one is too.
        if gap <= 1, high.strength < Rank.queen.strength {
            score += 2
        }
        return score
    }

    /// High-card points, doubled. Ace 10, king 8, queen 7, jack 6, and every
    /// other rank half its face value.
    private static func pointsDoubled(_ rank: Rank) -> Int {
        switch rank {
        case .ace: 20
        case .king: 16
        case .queen: 14
        case .jack: 12
        // `strength` is 0 for a deuce, so this is the rank's face value.
        default: rank.strength + 2
        }
    }

    /// All 169 classes, strongest first.
    ///
    /// The comparator is a total order — score, then high rank, then low rank,
    /// then suitedness, and no two classes share all four — so the result does
    /// not depend on the sort being stable, which Swift's is not.
    public static let strongestFirst: [HandClass] = HandClass.all.sorted { lhs, rhs in
        let leftScore = chenScoreDoubled(lhs)
        let rightScore = chenScoreDoubled(rhs)
        if leftScore != rightScore {
            return leftScore > rightScore
        }
        if lhs.highRank.strength != rhs.highRank.strength {
            return lhs.highRank.strength > rhs.highRank.strength
        }
        if lhs.lowRank.strength != rhs.lowRank.strength {
            return lhs.lowRank.strength > rhs.lowRank.strength
        }
        return suitednessOrder(lhs.suitedness) < suitednessOrder(rhs.suitedness)
    }

    /// How much of the deck is at least as strong as this class, in basis
    /// points of the 1,326 combinations. Lower is stronger; aces are 45.
    ///
    /// Cumulative *through* the class rather than up to it, so that
    /// `percentile <= entryRate` includes the class that straddles the
    /// boundary rather than half-including it.
    public static func percentileBasisPoints(_ handClass: HandClass) -> Int {
        percentileTable[slot(handClass)]
    }

    /// The total number of two-card combinations, which is what the percentile
    /// is a share of.
    public static let combinationCount = 1_326

    private static let percentileTable: [Int] = {
        // Indexed by rank pair and suitedness rather than hashed. A dictionary
        // would be correct for lookup, but the habit of not reaching for one is
        // worth more here than the four lines it would save: iterating one is
        // what makes a session replay differently on the next launch.
        var table = [Int](repeating: 0, count: 13 * 13 * 3)
        var cumulative = 0
        for handClass in strongestFirst {
            cumulative += handClass.combinationCount
            table[slot(handClass)] = cumulative * 10_000 / combinationCount
        }
        return table
    }()

    private static func slot(_ handClass: HandClass) -> Int {
        (handClass.highRank.strength * 13 + handClass.lowRank.strength) * 3
            + suitednessOrder(handClass.suitedness)
    }

    private static func suitednessOrder(_ suitedness: HandClass.Suitedness) -> Int {
        switch suitedness {
        case .pair: 0
        case .suited: 1
        case .offsuit: 2
        }
    }
}
