import PokerCore

/// The strength of a five-card poker hand, as a category plus the ranks that
/// break ties inside it.
///
/// Stored as a category and an ordered list of rank strengths rather than a
/// single packed integer. A packed score is faster and completely opaque; when
/// a showdown awards the pot to the wrong seat, the difference between
/// `1_234_567` and `.twoPair [11, 4, 12]` is the difference between a
/// debugging session and reading the failure message.
public struct HandRanking: Hashable, Sendable, Comparable, CustomStringConvertible {
    /// Ordered weakest to strongest; the raw values are the comparison.
    public enum Category: Int, Hashable, Sendable, Comparable, CaseIterable {
        case highCard
        case pair
        case twoPair
        case threeOfAKind
        case straight
        case flush
        case fullHouse
        case fourOfAKind
        case straightFlush

        public static func < (lhs: Category, rhs: Category) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let category: Category

    /// Rank strengths, most significant first: for two pair, the higher pair,
    /// then the lower pair, then the kicker. Two rankings in the same category
    /// always carry the same number of entries.
    public let tiebreakers: [Int]

    public init(category: Category, tiebreakers: [Int]) {
        self.category = category
        self.tiebreakers = tiebreakers
    }

    public static func < (lhs: HandRanking, rhs: HandRanking) -> Bool {
        if lhs.category != rhs.category {
            return lhs.category < rhs.category
        }
        return lhs.tiebreakers.lexicographicallyPrecedes(rhs.tiebreakers)
    }

    public var description: String {
        "\(category) \(tiebreakers)"
    }
}

/// Picks the best five-card hand out of the seven a player shows down with.
public enum HandEvaluator {
    /// Ace-low is spelled `-1` so that a wheel sorts below every other
    /// straight without a special case at every comparison site.
    private static let aceLowStrength = -1

    /// Evaluates two hole cards against a board of three, four or five.
    ///
    /// Categorises directly rather than scoring all 21 five-card subsets. The
    /// subset approach is easier to argue correct but a great deal slower, and
    /// speed matters here: settling 30 hands means evaluating up to 180 of
    /// these, and the golden-fixture generator runs many more. Correctness is
    /// covered instead by tests that pin one hand of every category and the
    /// boundaries between them.
    public static func evaluate(holeCards: [Card], board: [Card]) -> HandRanking {
        evaluate(cards: holeCards + board)
    }

    public static func evaluate(cards: [Card]) -> HandRanking {
        precondition(cards.count >= 5, "A hand needs at least five cards to rank")

        // Indexed by `Rank.strength`; no dictionary, so nothing downstream can
        // pick up an iteration order that varies between processes.
        var countsByRank = [Int](repeating: 0, count: 13)
        var countsBySuit = [Suit: Int]()
        var strengthsBySuit = [Suit: [Int]]()

        for card in cards {
            countsByRank[card.rank.strength] += 1
            countsBySuit[card.suit, default: 0] += 1
            strengthsBySuit[card.suit, default: []].append(card.rank.strength)
        }

        // `Suit.allCases` rather than iterating the dictionary: at most one suit
        // can reach five cards out of seven, so the result is the same either
        // way, but only one of the two spellings stays the same if that ever
        // stops being true.
        let flushSuit = Suit.allCases.first { countsBySuit[$0, default: 0] >= 5 }

        if let flushSuit {
            let flushStrengths = (strengthsBySuit[flushSuit] ?? []).sorted(by: >)
            if let high = straightHigh(among: flushStrengths) {
                return HandRanking(category: .straightFlush, tiebreakers: [high])
            }
            // Fall through: a flush can still lose to a full house or quads,
            // both of which are checked below before the flush is returned.
            let quadsOrBoat = quadsOrFullHouse(countsByRank: countsByRank)
            if let quadsOrBoat {
                return quadsOrBoat
            }
            return HandRanking(category: .flush, tiebreakers: Array(flushStrengths.prefix(5)))
        }

        if let quadsOrBoat = quadsOrFullHouse(countsByRank: countsByRank) {
            return quadsOrBoat
        }

        let allStrengths = cards.map(\.rank.strength).sorted(by: >)
        if let high = straightHigh(among: allStrengths) {
            return HandRanking(category: .straight, tiebreakers: [high])
        }

        // Ranks grouped by how many of each are present, strongest group first
        // and higher rank first inside a group. `sorted` on an array built from
        // an index sweep, so the order is fully determined by the cards.
        var groups: [(count: Int, strength: Int)] = []
        for strength in stride(from: 12, through: 0, by: -1) where countsByRank[strength] > 0 {
            groups.append((countsByRank[strength], strength))
        }
        groups.sort { lhs, rhs in
            lhs.count != rhs.count ? lhs.count > rhs.count : lhs.strength > rhs.strength
        }

        switch groups[0].count {
        case 3:
            let kickers = groups.dropFirst().prefix(2).map(\.strength)
            return HandRanking(category: .threeOfAKind, tiebreakers: [groups[0].strength] + kickers)
        case 2 where groups.count > 1 && groups[1].count == 2:
            let kicker = groups.dropFirst(2).first?.strength ?? aceLowStrength
            return HandRanking(
                category: .twoPair,
                tiebreakers: [groups[0].strength, groups[1].strength, kicker]
            )
        case 2:
            let kickers = groups.dropFirst().prefix(3).map(\.strength)
            return HandRanking(category: .pair, tiebreakers: [groups[0].strength] + kickers)
        default:
            return HandRanking(category: .highCard, tiebreakers: Array(allStrengths.prefix(5)))
        }
    }

    /// Quads, or a full house, if the rank counts contain one. `nil` otherwise.
    ///
    /// Split out because a flush has to consult it before declaring itself the
    /// best hand, and duplicating the check is how a flush ends up beating a
    /// full house in exactly the hands nobody wrote a test for.
    private static func quadsOrFullHouse(countsByRank: [Int]) -> HandRanking? {
        var quadRank: Int?
        var tripRanks: [Int] = []
        var pairRanks: [Int] = []

        for strength in stride(from: 12, through: 0, by: -1) {
            switch countsByRank[strength] {
            case 4 where quadRank == nil: quadRank = strength
            case 3: tripRanks.append(strength)
            case 2: pairRanks.append(strength)
            default: break
            }
        }

        if let quadRank {
            var kicker = aceLowStrength
            for strength in stride(from: 12, through: 0, by: -1)
            where strength != quadRank && countsByRank[strength] > 0 {
                kicker = strength
                break
            }
            return HandRanking(category: .fourOfAKind, tiebreakers: [quadRank, kicker])
        }

        guard let topTrips = tripRanks.first else {
            return nil
        }
        // Seven cards can hold two sets; the lower one plays as the pair.
        guard let pair = tripRanks.dropFirst().first ?? pairRanks.first else {
            return nil
        }
        return HandRanking(category: .fullHouse, tiebreakers: [topTrips, pair])
    }

    /// The high card of the best straight present, or `nil`.
    ///
    /// Takes strengths in any order and works off a presence table, so a
    /// repeated rank neither breaks the run nor counts twice.
    ///
    /// The wheel needs no special case: an ace also lights the slot below the
    /// deuce, so the ordinary sweep finds A-2-3-4-5 when it reaches a high card
    /// of five, and reports it as the weakest straight, which is what it is.
    private static func straightHigh(among strengths: [Int]) -> Int? {
        // Index 0 is the ace playing low; index `strength + 1` is every other
        // rank, so a run of five is five consecutive true slots.
        var present = [Bool](repeating: false, count: 14)
        for strength in strengths {
            present[strength + 1] = true
            if strength == 12 {
                present[0] = true
            }
        }

        var high = 12
        while high >= 3 {
            var isRun = true
            for offset in 0 ..< 5 where !present[high - offset + 1] {
                isRun = false
                break
            }
            if isRun {
                return high
            }
            high -= 1
        }
        return nil
    }
}
