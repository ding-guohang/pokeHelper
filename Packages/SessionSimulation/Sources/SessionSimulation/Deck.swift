import PokerCore

/// The 52-card deck and the shuffle session dealing runs on.
public enum Deck {
    /// The deck in a fixed order: rank ascending, and within a rank the suits
    /// in `Suit.allCases` order.
    ///
    /// The order matters even though the deck is about to be shuffled. Fisher–
    /// Yates permutes a starting arrangement, so the starting arrangement is
    /// part of the mapping from seed to cards; changing it changes every hand
    /// the same way changing the PRNG would. Derived from `allCases` rather
    /// than written out so a card cannot go missing, and asserted to be 52
    /// distinct cards by test.
    public static let ordered: [Card] = Rank.allCases.flatMap { rank in
        Suit.allCases.map { Card(rank: rank, suit: $0) }
    }

    /// Fisher–Yates, spelled out.
    ///
    /// Not `Array.shuffled(using:)`: that is deterministic for a given
    /// generator today, but the standard library does not promise the same
    /// permutation from the same draws across toolchain versions, and a
    /// silently repainted deck is exactly the failure the recorded seed exists
    /// to rule out.
    ///
    /// Descending sweep, drawing `j` in `0...i` and swapping — the unbiased
    /// form. The upward variant that draws in `0..<count` every step is a
    /// different, non-uniform permutation.
    public static func shuffled(using rng: inout SplitMix64) -> [Card] {
        var cards = ordered
        var index = cards.count - 1
        while index > 0 {
            let target = Int(rng.nextBelow(UInt64(index + 1)))
            cards.swapAt(index, target)
            index -= 1
        }
        return cards
    }
}
