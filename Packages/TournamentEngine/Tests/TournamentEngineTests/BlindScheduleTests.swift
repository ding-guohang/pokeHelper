import Testing
@testable import TournamentEngine

private let legalLevels = [
    BlindLevel(level: 1, smallBlindChips: 50, bigBlindChips: 100, anteChips: 0),
    BlindLevel(level: 2, smallBlindChips: 75, bigBlindChips: 150, anteChips: 0),
    BlindLevel(level: 3, smallBlindChips: 100, bigBlindChips: 200, anteChips: 25),
]

@Test func acceptsLegalThreeLevelSchedule() throws {
    let schedule = try BlindSchedule(levels: legalLevels)
    #expect(schedule.levels == legalLevels)
}

@Test func levelLookupStepsByHandIndexAndClampsAtFinalLevel() throws {
    let schedule = try BlindSchedule(levels: legalLevels)
    let handsPerLevel = 10

    #expect(schedule.level(atHandIndex: 0, handsPerLevel: handsPerLevel) == legalLevels[0])
    #expect(schedule.level(atHandIndex: 9, handsPerLevel: handsPerLevel) == legalLevels[0])
    #expect(schedule.level(atHandIndex: 10, handsPerLevel: handsPerLevel) == legalLevels[1])
    #expect(schedule.level(atHandIndex: 19, handsPerLevel: handsPerLevel) == legalLevels[1])
    #expect(schedule.level(atHandIndex: 20, handsPerLevel: handsPerLevel) == legalLevels[2])
    // Past the last level the schedule clamps to the final level.
    #expect(schedule.level(atHandIndex: 100, handsPerLevel: handsPerLevel) == legalLevels[2])
}

@Test func rejectsEmptySchedule() {
    #expect(throws: BlindScheduleError.empty) {
        _ = try BlindSchedule(levels: [])
    }
}

@Test func rejectsScheduleNotStartingAtLevelOne() {
    let levels = [
        BlindLevel(level: 2, smallBlindChips: 50, bigBlindChips: 100, anteChips: 0),
        BlindLevel(level: 3, smallBlindChips: 75, bigBlindChips: 150, anteChips: 0),
    ]
    #expect(throws: BlindScheduleError.levelsNotStartingAtOne) {
        _ = try BlindSchedule(levels: levels)
    }
}

@Test func rejectsNonConsecutiveLevels() {
    let levels = [
        BlindLevel(level: 1, smallBlindChips: 50, bigBlindChips: 100, anteChips: 0),
        BlindLevel(level: 3, smallBlindChips: 75, bigBlindChips: 150, anteChips: 0),
    ]
    #expect(throws: BlindScheduleError.levelsNotConsecutive) {
        _ = try BlindSchedule(levels: levels)
    }
}

@Test func rejectsNonPositiveBigBlind() {
    let levels = [
        BlindLevel(level: 1, smallBlindChips: 0, bigBlindChips: 0, anteChips: 0),
    ]
    #expect(throws: BlindScheduleError.nonPositiveBigBlind(level: 1)) {
        _ = try BlindSchedule(levels: levels)
    }
}

@Test func rejectsNegativeAnte() {
    let levels = [
        BlindLevel(level: 1, smallBlindChips: 50, bigBlindChips: 100, anteChips: -5),
    ]
    #expect(throws: BlindScheduleError.negativeAnte(level: 1)) {
        _ = try BlindSchedule(levels: levels)
    }
}

@Test func rejectsSmallBlindExceedingBigBlind() {
    let levels = [
        BlindLevel(level: 1, smallBlindChips: 150, bigBlindChips: 100, anteChips: 0),
    ]
    #expect(throws: BlindScheduleError.smallBlindExceedsBigBlind(level: 1)) {
        _ = try BlindSchedule(levels: levels)
    }
}

@Test func rejectsBigBlindNotStrictlyIncreasing() {
    let levels = [
        BlindLevel(level: 1, smallBlindChips: 50, bigBlindChips: 100, anteChips: 0),
        BlindLevel(level: 2, smallBlindChips: 50, bigBlindChips: 100, anteChips: 0),
    ]
    #expect(throws: BlindScheduleError.bigBlindNotStrictlyIncreasing(level: 2)) {
        _ = try BlindSchedule(levels: levels)
    }
}

@Test func theSevenErrorsArePairwiseDistinct() {
    let errors: [BlindScheduleError] = [
        .empty,
        .levelsNotStartingAtOne,
        .levelsNotConsecutive,
        .bigBlindNotStrictlyIncreasing(level: 2),
        .smallBlindExceedsBigBlind(level: 1),
        .nonPositiveBigBlind(level: 1),
        .negativeAnte(level: 1),
    ]
    for i in errors.indices {
        for j in errors.indices where j != i {
            #expect(errors[i] != errors[j])
        }
    }
}
