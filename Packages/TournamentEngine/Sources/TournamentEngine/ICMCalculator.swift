/// The Independent Chip Model: turns a chip-stack distribution and a prize
/// structure into each player's exact prize equity.
///
/// This is pure Malmuth-Harville arithmetic — probability of finishing each
/// place is proportional to chip share of the remaining field — not strategy.
/// It answers "how much prize money is my stack worth under this model," never
/// "how should I play"; no ranges, frequencies, or solver truth live here, which
/// is why it can ship with no reviewed content.
///
/// Two design choices keep it exact on real final tables:
///
/// 1. Only the paid places are enumerated. Places past the payout array pay
///    zero and contribute nothing, so the recursion stops at `K = payouts.count`
///    and runs in O(n^K), not O(n!). Crucially this bounds the intermediate
///    denominators to a product of at most `K` running totals; enumerating all
///    places would multiply `n-1` of them and overflow `Int` even for a normal
///    nine-handed table.
/// 2. Stacks are reduced by their GCD first. ICM depends only on chip ratios, so
///    `[5000, 3000, 2000]` becomes `[5, 3, 2]`, shrinking every running total and
///    keeping a realistic final table inside `Int`.
public enum ICMCalculator {
    /// Each seat's ICM equity, in the same unit as `payouts`, ordered to match
    /// `chipStacks`.
    ///
    /// Validation precedence (each single-defect input maps to one error):
    /// no players → empty payouts → non-positive stack → negative payout →
    /// more payouts than players.
    public static func equities(chipStacks: [Int], payouts: [Int]) throws -> [Fraction] {
        guard !chipStacks.isEmpty else { throw ICMError.noPlayers }
        guard !payouts.isEmpty else { throw ICMError.emptyPayouts }
        guard chipStacks.allSatisfy({ $0 > 0 }) else { throw ICMError.nonPositiveStack }
        guard payouts.allSatisfy({ $0 >= 0 }) else { throw ICMError.negativePayout }
        guard payouts.count <= chipStacks.count else { throw ICMError.morePayoutsThanPlayers }
        // The recursion tracks placed players in an Int bit mask (`1 << player`);
        // beyond 64 seats the shift would drop bits and silently corrupt the
        // result, so reject rather than mislead.
        guard chipStacks.count <= 64 else { throw ICMError.tooManySeats }

        // ICM is ratio-invariant; reduce by the shared GCD so the running totals
        // stay small. Every stack is > 0 here, so the GCD is > 0.
        let divisor = chipStacks.reduce(0) { Fraction.greatestCommonDivisor($0, $1) }
        let stacks = chipStacks.map { $0 / divisor }

        let playerCount = stacks.count
        let paidPlaces = payouts.count

        // The chip total feeds Fraction denominators, so it honors the same
        // "report, never trap" contract as the arithmetic below.
        var totalChips = 0
        for stack in stacks {
            let (sum, overflow) = totalChips.addingReportingOverflow(stack)
            if overflow { throw ICMError.overflow }
            totalChips = sum
        }

        // finishProbability[player][place] — only places 0..<paidPlaces matter.
        var finishProbability = Array(
            repeating: Array(repeating: Fraction(0), count: paidPlaces),
            count: playerCount
        )

        // Assigns players to finishing places from first downward. `usedMask`
        // marks players already placed above; `probSoFar` is the probability of
        // the prefix reaching this point; `removedSum` is their chips (always
        // ≤ totalChips, so `remainingChips` stays positive — never a zero
        // denominator).
        func assign(usedMask: Int, place: Int, probSoFar: Fraction, removedSum: Int) throws {
            if place == paidPlaces { return }
            let remainingChips = totalChips - removedSum
            for player in 0..<playerCount where usedMask & (1 << player) == 0 {
                let shareOfField = try Fraction(stacks[player]).multiplied(
                    by: Fraction(numerator: 1, denominator: remainingChips)
                )
                let contribution = try probSoFar.multiplied(by: shareOfField)
                finishProbability[player][place] = try finishProbability[player][place].adding(contribution)
                try assign(
                    usedMask: usedMask | (1 << player),
                    place: place + 1,
                    probSoFar: contribution,
                    removedSum: removedSum + stacks[player]
                )
            }
        }
        try assign(usedMask: 0, place: 0, probSoFar: Fraction(1), removedSum: 0)

        return try finishProbability.map { placesForPlayer in
            var equity = Fraction(0)
            for place in 0..<paidPlaces {
                let weighted = try placesForPlayer[place].multiplied(byInteger: payouts[place])
                equity = try equity.adding(weighted)
            }
            return equity
        }
    }
}
