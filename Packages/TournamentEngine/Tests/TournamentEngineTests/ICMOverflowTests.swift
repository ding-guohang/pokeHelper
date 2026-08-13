import Testing
@testable import TournamentEngine

@Test func overflowingPayoutThrowsRatherThanApproximating() {
    // A's first-place term is 3/4 * Int.max; the numerator 3 * Int.max cannot be
    // represented, and the calculator reports it instead of returning a wrapped
    // or floating-point value.
    #expect(throws: ICMError.overflow) {
        _ = try ICMCalculator.equities(chipStacks: [3000, 1000], payouts: [Int.max, 0])
    }
}

@Test func largeButRepresentablePayoutSucceeds() throws {
    // Paired with the overflow test so the overflow gate cannot degenerate into
    // always-throw: 3/4 * (Int.max/4) fits.
    let equities = try ICMCalculator.equities(chipStacks: [3000, 1000], payouts: [Int.max / 4, 0])
    #expect(equities.count == 2)
    // A finishes first 3/4 of the time and only first place pays.
    #expect(equities[0] == Fraction(numerator: 3, denominator: 4).multipliedOrTrap(Int.max / 4))
}

@Test func realisticFinalTableWithinIntRangeComputesExactly() throws {
    // Exact Int64 rational ICM has a real ceiling: the equity denominator is the
    // LCM of products of running totals, and a field of coprime large stacks
    // (nine stacks sharing no factor) pushes that LCM past Int.max — where the
    // calculator correctly throws rather than approximating (see
    // fieldExceedingExactIntRangeThrows). Real final-table stacks are counted in
    // a shared chip unit, so they reduce to small integers and stay exact. This
    // six-handed table's stacks share a 10_000 unit → [12,9,7,5,4,3].
    let stacks = [120_000, 90_000, 70_000, 50_000, 40_000, 30_000]
    let payouts = [50_000, 30_000, 20_000]
    let equities = try ICMCalculator.equities(chipStacks: stacks, payouts: payouts)
    #expect(equities.count == 6)
    let total = try equities.reduce(Fraction(0)) { try $0.adding($1) }
    #expect(total == Fraction(numerator: 100_000, denominator: 1))
}

@Test func fieldExceedingExactIntRangeThrows() {
    // Nine coprime-ish large stacks (gcd only 1_000 → [125,98,76,61,45,33,22,14,8])
    // have an exact equity denominator larger than Int.max. Exact Int64
    // representation is impossible, so the calculator reports overflow instead of
    // returning a rounded value — the exact-data rule taken to its conclusion.
    #expect(throws: ICMError.overflow) {
        _ = try ICMCalculator.equities(
            chipStacks: [125_000, 98_000, 76_000, 61_000, 45_000, 33_000, 22_000, 14_000, 8_000],
            payouts: [50_000, 30_000, 20_000]
        )
    }
}

private extension Fraction {
    /// Test-only convenience: the multiply is known not to overflow here.
    func multipliedOrTrap(_ k: Int) -> Fraction {
        try! multiplied(byInteger: k)
    }
}
