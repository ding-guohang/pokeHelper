import Testing
@testable import TournamentEngine

@Test func equalStacksSplitPrizePoolExactlyByThirds() throws {
    let equities = try ICMCalculator.equities(
        chipStacks: [1000, 1000, 1000],
        payouts: [5000, 3000, 2000]
    )
    // Total pool 10000 / 3 by symmetry — an exact rational, never 3333.33.
    for equity in equities {
        #expect(equity == Fraction(numerator: 10000, denominator: 3))
    }
    let total = try equities.reduce(Fraction(0)) { try $0.adding($1) }
    #expect(total == Fraction(numerator: 10000, denominator: 1))
}

@Test func twoPlayerHeadsUpEquities() throws {
    let equities = try ICMCalculator.equities(
        chipStacks: [3000, 1000],
        payouts: [100, 60]
    )
    // A: 3/4*100 + 1/4*60 = 90; B: 1/4*100 + 3/4*60 = 70.
    #expect(equities == [Fraction(numerator: 90, denominator: 1), Fraction(numerator: 70, denominator: 1)])
}

@Test func threePlayerClassicDistributionHasExactPerPlayerEquities() throws {
    let equities = try ICMCalculator.equities(
        chipStacks: [5000, 3000, 2000],
        payouts: [500, 300, 200]
    )
    #expect(equities[0] == Fraction(numerator: 5375, denominator: 14))
    #expect(equities[1] == Fraction(numerator: 655, denominator: 2))   // 4585/14
    #expect(equities[2] == Fraction(numerator: 2020, denominator: 7))  // 4040/14
    let total = try equities.reduce(Fraction(0)) { try $0.adding($1) }
    #expect(total == Fraction(numerator: 1000, denominator: 1))
}

@Test func fewerPayoutsThanPlayersPaysZeroForUnpaidPlaces() throws {
    let equities = try ICMCalculator.equities(
        chipStacks: [4000, 3000, 2000, 1000],
        payouts: [500, 300]
    )
    // Only the top two places pay; the field still sums to the awarded 800.
    let total = try equities.reduce(Fraction(0)) { try $0.adding($1) }
    #expect(total == Fraction(numerator: 800, denominator: 1))
    #expect(equities.count == 4)
}

@Test func singleRemainingPlayerTakesFirstPrize() throws {
    let equities = try ICMCalculator.equities(chipStacks: [1000], payouts: [500])
    #expect(equities == [Fraction(numerator: 500, denominator: 1)])
}
