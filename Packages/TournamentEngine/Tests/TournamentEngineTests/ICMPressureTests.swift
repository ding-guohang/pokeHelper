import Testing
@testable import TournamentEngine

@Test func equalStacksWithPrizeLadderGiveBubbleFactorAboveOne() throws {
    // equityNow 1000/3; win: opp busts (takes 200), {2000,1000} contest [500,300]
    // -> 1300/3; lose: hero busts, takes 200. BF = (400/3)/100 = 4/3.
    let bf = try ICMPressure.bubbleFactor(
        chipStacks: [1000, 1000, 1000],
        payouts: [500, 300, 200],
        heroIndex: 0,
        opponentIndex: 1
    )
    #expect(bf == Fraction(numerator: 4, denominator: 3))
    #expect(bf > Fraction(1))
}

@Test func winnerTakeAllHasBubbleFactorOfExactlyOne() throws {
    let bf = try ICMPressure.bubbleFactor(
        chipStacks: [1000, 1000, 1000],
        payouts: [1000],
        heroIndex: 0,
        opponentIndex: 1
    )
    #expect(bf == Fraction(1))
}

@Test func bigStackVersusShortStackBubbleFactor() throws {
    // r = min(3000,1000) = 1000. win: opp busts, {4000,2000} contest [500,300]
    // -> 1300/3. lose: both survive [2000,2000,2000] -> 1000/3. equityNow = 385.
    // BF = (155/3)/(145/3) = 31/29.
    let bf = try ICMPressure.bubbleFactor(
        chipStacks: [3000, 1000, 2000],
        payouts: [500, 300, 200],
        heroIndex: 0,
        opponentIndex: 1
    )
    #expect(bf == Fraction(numerator: 31, denominator: 29))
    #expect(bf > Fraction(1))
}

@Test func headsUpHasBubbleFactorOfExactlyOne() throws {
    // No prize ladder to climb heads-up: BF is exactly 1.
    let bf = try ICMPressure.bubbleFactor(
        chipStacks: [3000, 1000],
        payouts: [100, 60],
        heroIndex: 0,
        opponentIndex: 1
    )
    #expect(bf == Fraction(1))
}

@Test func flatPayoutsRejectedAsNoEquityGain() throws {
    #expect(throws: ICMError.noEquityGain) {
        _ = try ICMPressure.bubbleFactor(
            chipStacks: [1000, 1000, 1000],
            payouts: [300, 300, 300],
            heroIndex: 0,
            opponentIndex: 1
        )
    }
    // Paired success: a non-flat structure on the same stacks returns a factor.
    let bf = try ICMPressure.bubbleFactor(
        chipStacks: [1000, 1000, 1000],
        payouts: [500, 300, 200],
        heroIndex: 0,
        opponentIndex: 1
    )
    #expect(bf == Fraction(numerator: 4, denominator: 3))
}

@Test func sameSeatAndOutOfRangeSeatsRejectedWithLegalSucceeding() throws {
    #expect(throws: ICMError.sameSeat) {
        _ = try ICMPressure.bubbleFactor(
            chipStacks: [1000, 1000, 1000], payouts: [500, 300, 200],
            heroIndex: 1, opponentIndex: 1
        )
    }
    #expect(throws: ICMError.seatOutOfRange) {
        _ = try ICMPressure.bubbleFactor(
            chipStacks: [1000, 1000, 1000], payouts: [500, 300, 200],
            heroIndex: 0, opponentIndex: 3
        )
    }
    #expect(throws: ICMError.seatOutOfRange) {
        _ = try ICMPressure.bubbleFactor(
            chipStacks: [1000, 1000, 1000], payouts: [500, 300, 200],
            heroIndex: -1, opponentIndex: 1
        )
    }
    let bf = try ICMPressure.bubbleFactor(
        chipStacks: [1000, 1000, 1000], payouts: [500, 300, 200],
        heroIndex: 0, opponentIndex: 1
    )
    #expect(bf == Fraction(numerator: 4, denominator: 3))
}

@Test func reusesICMInputValidation() {
    #expect(throws: ICMError.noPlayers) {
        _ = try ICMPressure.bubbleFactor(chipStacks: [], payouts: [100], heroIndex: 0, opponentIndex: 1)
    }
    #expect(throws: ICMError.nonPositiveStack) {
        _ = try ICMPressure.bubbleFactor(chipStacks: [0, 1000], payouts: [100], heroIndex: 0, opponentIndex: 1)
    }
    #expect(throws: ICMError.morePayoutsThanPlayers) {
        _ = try ICMPressure.bubbleFactor(chipStacks: [1000, 1000], payouts: [100, 60, 40], heroIndex: 0, opponentIndex: 1)
    }
}
