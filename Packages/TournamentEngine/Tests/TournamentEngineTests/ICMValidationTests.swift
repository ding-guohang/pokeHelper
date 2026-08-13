import Testing
@testable import TournamentEngine

// Each rejection is tested with exactly one defect present, and paired with the
// same shape minus that defect succeeding — so a validator that rejected
// everything could not pass, and the fixed precedence is what maps a
// single-defect input to one error.

@Test func rejectsEmptyStacksBeforePayoutCountCheck() throws {
    #expect(throws: ICMError.noPlayers) {
        _ = try ICMCalculator.equities(chipStacks: [], payouts: [100])
    }
    let ok = try ICMCalculator.equities(chipStacks: [100], payouts: [100])
    #expect(ok == [Fraction(numerator: 100, denominator: 1)])
}

@Test func rejectsEmptyPayouts() throws {
    #expect(throws: ICMError.emptyPayouts) {
        _ = try ICMCalculator.equities(chipStacks: [1000, 1000], payouts: [])
    }
    let ok = try ICMCalculator.equities(chipStacks: [1000, 1000], payouts: [100])
    #expect(ok.count == 2)
}

@Test func rejectsZeroOrNegativeStack() throws {
    #expect(throws: ICMError.nonPositiveStack) {
        _ = try ICMCalculator.equities(chipStacks: [0, 1000], payouts: [100])
    }
    #expect(throws: ICMError.nonPositiveStack) {
        _ = try ICMCalculator.equities(chipStacks: [-1, 1000], payouts: [100])
    }
    let ok = try ICMCalculator.equities(chipStacks: [1, 1000], payouts: [100])
    #expect(ok.count == 2)
}

@Test func rejectsNegativePayout() throws {
    #expect(throws: ICMError.negativePayout) {
        _ = try ICMCalculator.equities(chipStacks: [1000, 1000], payouts: [100, -1])
    }
    let ok = try ICMCalculator.equities(chipStacks: [1000, 1000], payouts: [100, 1])
    #expect(ok.count == 2)
}

@Test func rejectsMorePayoutsThanPlayers() throws {
    #expect(throws: ICMError.morePayoutsThanPlayers) {
        _ = try ICMCalculator.equities(chipStacks: [1000, 1000], payouts: [100, 60, 40])
    }
    let ok = try ICMCalculator.equities(chipStacks: [1000, 1000], payouts: [100, 60])
    #expect(ok.count == 2)
}

@Test func rejectsMoreThanSixtyFourSeats() throws {
    // 64 seats is the bit-mask limit and must succeed; 65 must be rejected
    // rather than silently corrupting the finishing-order mask.
    let sixtyFour = try ICMCalculator.equities(
        chipStacks: Array(repeating: 1000, count: 64),
        payouts: [100]
    )
    #expect(sixtyFour.count == 64)
    #expect(throws: ICMError.tooManySeats) {
        _ = try ICMCalculator.equities(chipStacks: Array(repeating: 1000, count: 65), payouts: [100])
    }
}

@Test func theICMErrorsArePairwiseDistinct() {
    let errors: [ICMError] = [
        .noPlayers, .emptyPayouts, .nonPositiveStack,
        .negativePayout, .morePayoutsThanPlayers, .tooManySeats,
        .noEquityGain, .sameSeat, .seatOutOfRange, .overflow,
    ]
    for i in errors.indices {
        for j in errors.indices where j != i {
            #expect(errors[i] != errors[j])
        }
    }
}
