import Testing
@testable import PokerCore

@Test func cardCodeRoundTrips() throws {
    let card = try #require(Card(code: "As"))
    #expect(card.rank == .ace)
    #expect(card.suit == .spades)
    #expect(card.code == "As")
    #expect(Card(code: "1x") == nil)
}
