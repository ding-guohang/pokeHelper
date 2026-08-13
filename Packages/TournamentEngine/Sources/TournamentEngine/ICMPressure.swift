/// The ICM bubble factor: how much prize equity a player risks per unit of prize
/// equity gained in a two-way all-in.
///
/// It is a descriptive metric built on `ICMCalculator`, in the same category as
/// ICM equity itself — a fact about the prize structure and chips, not strategy.
/// It quantifies ICM pressure; it does not recommend calling or folding and
/// carries no ranges. Bubble-factor-driven ranges are reviewed content and live
/// elsewhere.
///
/// For hero risking `r = min(heroStack, opponentStack)` against one opponent:
///
///     BF = (equityNow - equityLose) / (equityWin - equityNow)
///
/// It is exactly 1 under a winner-take-all structure (chips equal equity) and
/// greater than 1 when a prize ladder taxes chips. An all-in eliminates the
/// short/equal stack that loses: the knocked-out player takes the last-place
/// payout and the survivors contest the places above.
public enum ICMPressure {
    public static func bubbleFactor(
        chipStacks: [Int],
        payouts: [Int],
        heroIndex: Int,
        opponentIndex: Int
    ) throws -> Fraction {
        // ICM input validation (and equityNow) first, so ill-formed stacks or
        // payouts surface as the ICM errors rather than a seat error.
        let currentEquities = try ICMCalculator.equities(chipStacks: chipStacks, payouts: payouts)

        let count = chipStacks.count
        guard heroIndex >= 0, heroIndex < count, opponentIndex >= 0, opponentIndex < count else {
            throw ICMError.seatOutOfRange
        }
        guard heroIndex != opponentIndex else { throw ICMError.sameSeat }

        let equityNow = currentEquities[heroIndex]
        let atRisk = min(chipStacks[heroIndex], chipStacks[opponentIndex])

        let equityWin = try heroEquityAfter(
            chipStacks: chipStacks, payouts: payouts,
            heroIndex: heroIndex, opponentIndex: opponentIndex,
            newHeroStack: chipStacks[heroIndex] + atRisk,
            newOpponentStack: chipStacks[opponentIndex] - atRisk
        )
        let equityLose = try heroEquityAfter(
            chipStacks: chipStacks, payouts: payouts,
            heroIndex: heroIndex, opponentIndex: opponentIndex,
            newHeroStack: chipStacks[heroIndex] - atRisk,
            newOpponentStack: chipStacks[opponentIndex] + atRisk
        )

        let gain = try equityWin.subtracting(equityNow)
        guard gain != Fraction(0) else { throw ICMError.noEquityGain }
        let risk = try equityNow.subtracting(equityLose)
        return try risk.divided(by: gain)
    }

    /// Hero's ICM equity after the all-in resolves to the given post-hand stacks.
    /// Chips are conserved between hero and opponent; every other seat is
    /// unchanged. Whoever falls to zero is eliminated into the last place of the
    /// current field (a deterministic tail payout), and the survivors contest
    /// the places above.
    private static func heroEquityAfter(
        chipStacks: [Int],
        payouts: [Int],
        heroIndex: Int,
        opponentIndex: Int,
        newHeroStack: Int,
        newOpponentStack: Int
    ) throws -> Fraction {
        let count = chipStacks.count

        // Hero busts: hero finishes last of the current N and takes that payout.
        if newHeroStack == 0 {
            return Fraction(payoutAt(count - 1, payouts: payouts))
        }

        var stacks = chipStacks
        stacks[heroIndex] = newHeroStack
        stacks[opponentIndex] = newOpponentStack

        // Opponent busts: they take last place; the remaining N-1 seats contest
        // the top N-1 payouts. Hero's index shifts if the opponent sat before it.
        if newOpponentStack == 0 {
            stacks.remove(at: opponentIndex)
            let reducedPayouts = Array(payouts.prefix(count - 1))
            let heroReducedIndex = heroIndex > opponentIndex ? heroIndex - 1 : heroIndex
            return try ICMCalculator.equities(chipStacks: stacks, payouts: reducedPayouts)[heroReducedIndex]
        }

        // Nobody busts: the full field plays on with the same payouts.
        return try ICMCalculator.equities(chipStacks: stacks, payouts: payouts)[heroIndex]
    }

    /// The payout for finishing place `place` (0-based), or zero past the paid
    /// places.
    private static func payoutAt(_ place: Int, payouts: [Int]) -> Int {
        place < payouts.count ? payouts[place] : 0
    }
}
