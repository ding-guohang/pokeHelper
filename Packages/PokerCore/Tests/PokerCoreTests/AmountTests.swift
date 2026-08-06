import Testing
@testable import PokerCore

@Test func exactAmountsAvoidFloatingPointChips() {
    #expect(BBAmount(centiBB: 650) + BBAmount(centiBB: 325) == BBAmount(centiBB: 975))
    #expect(EVAmount(milliBB: 180) - EVAmount(milliBB: 25) == EVAmount(milliBB: 155))
}
