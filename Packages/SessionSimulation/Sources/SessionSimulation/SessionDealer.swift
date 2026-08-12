import PokerCore

/// The cards for one hand, drawn before any betting happens.
///
/// The whole board is dealt up front and revealed street by street, rather
/// than drawn when each street arrives. The two are equivalent for a hand that
/// runs to the river, but only the first makes a hand's cards a function of
/// `(seed, handIndex)` alone: if the turn card were drawn at the moment the
/// turn was reached, it would depend on how many random draws the players
/// consumed on the flop, and therefore on the opponent profiles. A recorded
/// session would then replay different cards after any change to opponent
/// behaviour, which is precisely the drift the recorded behaviour-table
/// version exists to detect rather than to cause.
public struct DealtHand: Hashable, Sendable {
    public let handIndex: Int
    public let buttonSeat: Int

    /// Two cards per seat, indexed by seat. Always `TableRules.seatCount`
    /// entries of two cards, including for a seat that has been busted — the
    /// deal does not depend on the chip stacks.
    public let holeCards: [[Card]]

    /// All five community cards. `HandState` exposes only the ones the hand
    /// has actually reached.
    public let fullBoard: [Card]

    public init(handIndex: Int, buttonSeat: Int, holeCards: [[Card]], fullBoard: [Card]) {
        self.handIndex = handIndex
        self.buttonSeat = buttonSeat
        self.holeCards = holeCards
        self.fullBoard = fullBoard
    }

    /// Every card this hand uses: twelve hole cards then the five board cards.
    public var allCards: [Card] {
        holeCards.flatMap(\.self) + fullBoard
    }
}

/// Turns a seed and a hand index into cards.
public struct SessionDealer: Hashable, Sendable {
    public let seed: UInt64

    public init(seed: UInt64) {
        self.seed = seed
    }

    /// Label mixed into the per-hand deck seed.
    ///
    /// A constant distinct from the one the action stream uses, so a hand's
    /// cards and its opponents' dice come from unrelated streams. Two streams
    /// derived from the same seed with the same label would be the same
    /// stream, which would make the opponents' choices a function of the board.
    private static let deckStreamLabel: UInt64 = 0x0000_0000_0000_0001

    /// The deck stream for one hand. Also used by callers that need to advance
    /// the same stream, so the derivation stays in one place.
    public func deckSeed(handIndex: Int) -> UInt64 {
        SplitMix64.derivedSeed(
            base: seed,
            label: Self.deckStreamLabel &+ UInt64(bitPattern: Int64(handIndex)) &* 0x1_0000
        )
    }

    /// Deals one hand.
    ///
    /// Cards come off the shuffled deck in the order a dealer would deal them:
    /// two rounds of one card per seat starting left of the button, then the
    /// five board cards. There is no burn card — a burn changes which cards
    /// land where without changing anything a player can observe, so it would
    /// only add a constant no test could distinguish from a bug.
    public func deal(handIndex: Int) -> DealtHand {
        var rng = SplitMix64(seed: deckSeed(handIndex: handIndex))
        let deck = Deck.shuffled(using: &rng)
        let buttonSeat = TableRules.buttonSeat(handIndex: handIndex)

        var holeCards = [[Card]](repeating: [], count: TableRules.seatCount)
        var nextCard = 0
        for _ in 0 ..< 2 {
            for offset in 1 ... TableRules.seatCount {
                let seat = TableRules.seat(atOffset: offset, buttonSeat: buttonSeat)
                holeCards[seat].append(deck[nextCard])
                nextCard += 1
            }
        }

        let fullBoard = Array(deck[nextCard ..< (nextCard + 5)])
        return DealtHand(
            handIndex: handIndex,
            buttonSeat: buttonSeat,
            holeCards: holeCards,
            fullBoard: fullBoard
        )
    }
}
