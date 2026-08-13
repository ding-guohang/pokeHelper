import Testing
@testable import TournamentEngine

private let bb100 = BlindLevel(level: 1, smallBlindChips: 50, bigBlindChips: 100, anteChips: 0)

@Test func thresholdClassificationIsExactAndDiscriminatesFromFloor() throws {
    // 850 chips at BB 100 is 8.5 bb. The floored depth is 8, so a floor-based
    // compare would call it "at or below 8"; the exact chip compare does not.
    let context = try PushFoldContext(effectiveChips: 850, level: bb100)
    #expect(try context.isAtOrBelow(thresholdBigBlinds: 10) == true)   // 850 <= 1000
    #expect(try context.isAtOrBelow(thresholdBigBlinds: 8) == false)   // 850 > 800, but floor(8.5)=8
    #expect(context.effectiveBigBlinds == 8)                            // floored, for display only
}

@Test func thresholdBoundaryIsInclusive() throws {
    let context = try PushFoldContext(effectiveChips: 800, level: bb100)
    #expect(try context.isAtOrBelow(thresholdBigBlinds: 8) == true)    // 800 <= 800
}

@Test func negativeThresholdAndThresholdOverflowRejectedWithLegalSucceeding() throws {
    let context = try PushFoldContext(effectiveChips: 1000, level: bb100)
    #expect(throws: PushFoldError.negativeThreshold) {
        _ = try context.isAtOrBelow(thresholdBigBlinds: -1)
    }
    #expect(throws: PushFoldError.thresholdOverflow) {
        // Int.max * 100 cannot be represented; reported, not trapped.
        _ = try context.isAtOrBelow(thresholdBigBlinds: .max)
    }
    // Paired success so neither rejection can degenerate into always-throw.
    #expect(try context.isAtOrBelow(thresholdBigBlinds: 10) == true)
}

@Test func optionsAreFoldAndJamEntireStackIndependentOfDepth() throws {
    let context = try PushFoldContext(effectiveChips: 1200, level: bb100)
    #expect(context.options() == [.fold, .jam(toChips: 1200)])

    // Depth-independence: a deep stack returns the same model move set, proving
    // options() is the model's action set, not a depth-driven recommendation.
    let deep = try PushFoldContext(effectiveChips: 500_000, level: bb100)
    #expect(deep.options() == [.fold, .jam(toChips: 500_000)])
}

@Test func rejectsNonPositiveEffectiveStackAndNonPositiveBigBlind() {
    #expect(throws: PushFoldError.nonPositiveEffectiveStack) {
        _ = try PushFoldContext(effectiveChips: 0, level: bb100)
    }
    #expect(throws: PushFoldError.nonPositiveEffectiveStack) {
        _ = try PushFoldContext(effectiveChips: -100, level: bb100)
    }
    let zeroBigBlind = BlindLevel(level: 1, smallBlindChips: 0, bigBlindChips: 0, anteChips: 0)
    #expect(throws: PushFoldError.nonPositiveBigBlind) {
        _ = try PushFoldContext(effectiveChips: 1000, level: zeroBigBlind)
    }
    // Paired successes: remove each defect and construction works.
    #expect(throws: Never.self) {
        _ = try PushFoldContext(effectiveChips: 1000, level: bb100)
    }
}

@Test func theFourPushFoldErrorsArePairwiseDistinct() {
    let errors: [PushFoldError] = [
        .nonPositiveEffectiveStack, .nonPositiveBigBlind, .negativeThreshold, .thresholdOverflow,
    ]
    for i in errors.indices {
        for j in errors.indices where j != i {
            #expect(errors[i] != errors[j])
        }
    }
}
