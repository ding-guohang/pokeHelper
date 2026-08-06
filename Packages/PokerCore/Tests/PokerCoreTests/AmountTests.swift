import Foundation
import Testing
@testable import PokerCore

@Test func exactAmountsAvoidFloatingPointChips() {
    #expect(BBAmount(centiBB: 650) + BBAmount(centiBB: 325) == BBAmount(centiBB: 975))
    #expect(EVAmount(milliBB: 180) - EVAmount(milliBB: 25) == EVAmount(milliBB: 155))
}

@Test func amountCodableUsesUnitKeysAndRoundTrips() throws {
    let bbAmount = BBAmount(centiBB: 650)
    let evAmount = EVAmount(milliBB: -25)
    let bbData = try JSONEncoder().encode(bbAmount)
    let evData = try JSONEncoder().encode(evAmount)

    #expect(try JSONDecoder().decode([String: Int].self, from: bbData) == ["centiBB": 650])
    #expect(try JSONDecoder().decode([String: Int].self, from: evData) == ["milliBB": -25])
    #expect(try JSONDecoder().decode(BBAmount.self, from: bbData) == bbAmount)
    #expect(try JSONDecoder().decode(EVAmount.self, from: evData) == evAmount)
}

@Test func bbAmountCodableRejectsNegativeCentiBB() {
    let negativeAmount = Data(#"{"centiBB":-1}"#.utf8)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(BBAmount.self, from: negativeAmount)
    }
}
