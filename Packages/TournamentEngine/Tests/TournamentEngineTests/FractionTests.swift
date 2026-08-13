import Testing
@testable import TournamentEngine

@Test func fractionReducesAndForcesPositiveDenominator() {
    let f = Fraction(numerator: 6, denominator: -3)
    #expect(f.numerator == -2)
    #expect(f.denominator == 1)
}

@Test func zeroNormalizesToZeroOverOne() {
    let f = Fraction(numerator: 0, denominator: 5)
    #expect(f.numerator == 0)
    #expect(f.denominator == 1)
}

@Test func alreadyReducedFractionIsUnchanged() {
    let f = Fraction(numerator: 10000, denominator: 3)
    #expect(f.numerator == 10000)
    #expect(f.denominator == 3)
}

@Test func additionCombinesOverLeastCommonMultiple() throws {
    let sum = try Fraction(numerator: 1, denominator: 2).adding(Fraction(numerator: 1, denominator: 3))
    #expect(sum == Fraction(numerator: 5, denominator: 6))
}

@Test func additionOfThirdsIsExactNotApproximate() throws {
    // Three exact thirds sum to exactly one whole; a Double would land on
    // 0.9999… and this equality would fail.
    let third = Fraction(numerator: 10000, denominator: 3)
    let sum = try third.adding(third).adding(third)
    #expect(sum == Fraction(numerator: 10000, denominator: 1))
}

@Test func integerMultiplicationWeightsByPayout() throws {
    let weighted = try Fraction(numerator: 3, denominator: 4).multiplied(byInteger: 100)
    #expect(weighted == Fraction(numerator: 75, denominator: 1))
}

@Test func fractionMultiplicationCrossReduces() throws {
    let product = try Fraction(numerator: 2, denominator: 3).multiplied(by: Fraction(numerator: 3, denominator: 2))
    #expect(product == Fraction(numerator: 1, denominator: 1))
}

@Test func comparisonOrdersByValue() {
    #expect(Fraction(numerator: 1, denominator: 3) < Fraction(numerator: 1, denominator: 2))
    #expect(!(Fraction(numerator: 1, denominator: 2) < Fraction(numerator: 1, denominator: 3)))
}

@Test func integerMultiplicationOverflowThrows() {
    // 3 * Int.max cannot be represented; the operation reports rather than wraps.
    #expect(throws: ICMError.overflow) {
        _ = try Fraction(numerator: 3, denominator: 1).multiplied(byInteger: Int.max)
    }
}

@Test func integerMultiplicationJustBelowOverflowSucceeds() throws {
    // The paired success guards the overflow test from degenerating into
    // always-throw: 3 * (Int.max / 4) fits.
    let product = try Fraction(numerator: 3, denominator: 1).multiplied(byInteger: Int.max / 4)
    #expect(product == Fraction(numerator: 3 * (Int.max / 4), denominator: 1))
}

@Test func multiplyingByZeroIntegerGivesZero() throws {
    let product = try Fraction(numerator: 7, denominator: 3).multiplied(byInteger: 0)
    #expect(product == Fraction(0))
}

@Test func multiplyingByZeroFractionGivesZero() throws {
    let product = try Fraction(numerator: 7, denominator: 3).multiplied(by: Fraction(0))
    #expect(product == Fraction(0))
}

@Test func multiplicationHandlesNegativeOperands() throws {
    let product = try Fraction(numerator: -2, denominator: 3).multiplied(by: Fraction(numerator: 3, denominator: 4))
    #expect(product == Fraction(numerator: -1, denominator: 2))
}

@Test func subtractionIsExact() throws {
    let difference = try Fraction(numerator: 1300, denominator: 3).subtracting(Fraction(numerator: 1000, denominator: 3))
    #expect(difference == Fraction(numerator: 100, denominator: 1))
}

@Test func negationFlipsSign() {
    #expect(Fraction(numerator: 2, denominator: 3).negated() == Fraction(numerator: -2, denominator: 3))
    #expect(Fraction(0).negated() == Fraction(0))
}

@Test func divisionEqualsMultiplyingByReciprocal() throws {
    let quotient = try Fraction(numerator: 400, denominator: 3).divided(by: Fraction(numerator: 100, denominator: 1))
    #expect(quotient == Fraction(numerator: 4, denominator: 3))
}

@Test func reciprocalOfNegativeFractionKeepsPositiveDenominator() {
    let reciprocal = Fraction(numerator: -3, denominator: 4).reciprocal()
    #expect(reciprocal == Fraction(numerator: -4, denominator: 3))
}

@Test func additionOverflowThrows() {
    // Denominators 2 and (Int.max) are coprime, so the combined denominator
    // 2 * Int.max cannot be represented and addition reports overflow.
    #expect(throws: ICMError.overflow) {
        _ = try Fraction(numerator: 1, denominator: 2)
            .adding(Fraction(numerator: 1, denominator: Int.max))
    }
}
