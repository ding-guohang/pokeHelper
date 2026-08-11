import PokerCore

/// Decides what a seat does when it is that seat's turn.
///
/// The engine never calls anything else to move a hand along, so an
/// implementation is the only place a hand's shape comes from. Two obligations,
/// both load-bearing:
///
/// 1. The returned action must come from `decision.orderedLegalActions`. The
///    engine rejects anything else, and rejection at this point is a programmer
///    error rather than a recoverable one.
/// 2. All randomness must come from the supplied generator. Reaching for
///    `Int.random(in:)`, `SystemRandomNumberGenerator` or `hashValue` breaks
///    cross-process replay, and breaks it silently — within one process every
///    one of those is perfectly stable.
public protocol SessionActionPolicy: Sendable {
    func chooseAction(at decision: DecisionPoint, using rng: inout SplitMix64) -> DecisionAction
}

/// A single seeded policy, so that hands can be played end to end before the
/// four disclosed opponent profiles exist.
///
/// **This is not one of the four profiles.** `virtual-opponents` requires named
/// profiles whose entry rate, aggression and calling tendency are stated to the
/// user as defined values and are distinguishable from each other on a fixed
/// set of spots; that is task T6 and it owns `OpponentProfileTable` and its
/// version constant. This type exists because T4 and T5 have to settle real
/// pots to assert chip conservation, and settling a pot needs somebody to act.
///
/// It is deliberately not disclosed to any user and carries no version, so it
/// cannot be mistaken for the behaviour table a recorded session pins itself
/// to.
public struct BaselineActionPolicy: SessionActionPolicy {
    public init() {}

    public func chooseAction(at decision: DecisionPoint, using rng: inout SplitMix64) -> DecisionAction {
        let actions = decision.orderedLegalActions
        precondition(!actions.isEmpty, "A decision point must offer at least one action")

        let strength = handStrength(at: decision)
        let weights = weights(for: actions, strength: strength)
        let total = weights.reduce(0, +)
        precondition(total > 0, "Every action was weighted to zero")

        // Weighted pick by walking the cumulative weights. Linear rather than
        // clever: the list is never longer than six entries, and a running sum
        // is easy to check by eye against a failing case.
        var roll = Int(rng.nextBelow(UInt64(total)))
        for (index, weight) in weights.enumerated() {
            roll -= weight
            if roll < 0 {
                return actions[index]
            }
        }
        return actions[actions.count - 1]
    }

    /// A rough 0–100 read on the seat's holding.
    ///
    /// Preflop it comes from the hand class; afterwards from the made hand. Not
    /// a strategy and not claimed to be one — it exists so that the hands the
    /// engine produces contain a spread of pot sizes and showdowns instead of
    /// noise, which is what makes settlement and legal-set assertions run over
    /// interesting states.
    ///
    /// Deliberately *not* shared with the disclosed profiles, which read a
    /// holding on their own scale. The two scales measure the same thing to
    /// different calibrations — a pair of aces is 23 here and 55 there — and
    /// merging them would change every hand this baseline has ever dealt, for
    /// the sake of a function neither caller wants to share.
    private func handStrength(at decision: DecisionPoint) -> Int {
        guard decision.street != .preflop else {
            return preflopStrength(decision.handClass)
        }
        let ranking = HandEvaluator.evaluate(
            holeCards: decision.holeCards,
            board: decision.board
        )
        return min(100, ranking.category.rawValue * 11 + (ranking.tiebreakers.first ?? 0))
    }

    private func preflopStrength(_ handClass: HandClass) -> Int {
        let high = handClass.highRank.strength
        let low = handClass.lowRank.strength
        return switch handClass.suitedness {
        case .pair: 55 + high * 3
        case .suited: 12 + high * 2 + low
        case .offsuit: high * 2 + low
        }
    }

    /// Relative weights, one per offered action.
    ///
    /// The aggression budget is split across the offered sizes rather than
    /// applied to each one. That distinction is not cosmetic: weighting each
    /// size independently makes total aggression scale with how many sizes the
    /// state machine happened to offer, and the first version of this policy
    /// did exactly that. Every seat became a maniac, raise wars compounded, and
    /// a 30-hand session busted five of six seats — which left twelve hands
    /// with no live players, no pot and therefore no positive chip delta, and
    /// turned the settlement assertions into statements about an empty table.
    ///
    /// Every legal action still keeps a positive weight, so nothing is
    /// unreachable — including the all-in that the side-pot paths need.
    private func weights(for actions: [DecisionAction], strength: Int) -> [Int] {
        let sizedCount = actions.count { action in
            switch action {
            case .bet, .raise: true
            default: false
            }
        }
        // Betting into an unopened pot is cheap; putting in a raise is not.
        let facingBet = actions.contains(.fold)
        let aggressionBudget = facingBet ? 6 + strength / 8 : 20 + strength / 4
        let perSize = sizedCount > 0 ? max(1, aggressionBudget / sizedCount) : 0

        return actions.map { action in
            switch action {
            case .fold: max(1, 55 - strength / 2)
            case .check: 40 + strength / 4
            case .call: 18 + strength / 3
            case .bet, .raise: perSize
            case .allIn: 1 + strength / 40
            }
        }
    }
}
