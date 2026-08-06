import Foundation
import Testing
@testable import PokerCore

@Test func cardCodeRoundTrips() throws {
    let card = try #require(Card(code: "As"))
    #expect(card.rank == .ace)
    #expect(card.suit == .spades)
    #expect(card.code == "As")
    #expect(Card(code: "1x") == nil)
}

@Test func cardCodableUsesCodeString() throws {
    let card = try #require(Card(code: "As"))
    let encoded = try JSONEncoder().encode(card)

    #expect(String(decoding: encoded, as: UTF8.self) == #""As""#)
    #expect(try JSONDecoder().decode(Card.self, from: encoded) == card)
}

@Test func cardCodableRejectsInvalidCode() {
    let invalidCard = Data(#""1x""#.utf8)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(Card.self, from: invalidCard)
    }
}
