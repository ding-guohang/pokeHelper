import Testing
@testable import TournamentEngine

private let level1 = BlindLevel(level: 1, smallBlindChips: 50, bigBlindChips: 100, anteChips: 0)
private let level3 = BlindLevel(level: 3, smallBlindChips: 100, bigBlindChips: 200, anteChips: 25)

@Test func sameChipsAreShallowerAtAHigherLevel() {
    let atLevel1 = effectiveBigBlinds(chips: 3000, level: level1)
    let atLevel3 = effectiveBigBlinds(chips: 3000, level: level3)

    #expect(atLevel1 == 30)
    #expect(atLevel3 == 15)
    // The same stack must read shallower once the blinds climb; a calculation
    // that ignored the level would return the same number twice.
    #expect(atLevel1 != atLevel3)
}

@Test func depthFloorsTowardZero() {
    #expect(effectiveBigBlinds(chips: 250, level: level1) == 2)
}

@Test func zeroChipsAreZeroBigBlinds() {
    #expect(effectiveBigBlinds(chips: 0, level: level1) == 0)
}
