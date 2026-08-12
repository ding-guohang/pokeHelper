import Foundation
import PokerCore

/// A standardized representation of a real hand that was observed (played online
/// and imported), as distinct from a hand this app dealt.
///
/// It is defined from scratch rather than reusing `SessionSimulation.PlayedHand`:
/// that type is fixed at six seats with the hero in seat 0, every hole card
/// dealt (never unknown), rake pinned to zero and no raw text — none of which
/// fits a hand a stranger's client exported. Every amount is an integer
/// centi-big-blind derived from the hand's stated big blind; floats never enter.
public struct ObservedHand: Hashable, Sendable, Codable {
    /// The raw text plus its identity (SHA-256 of the normalized text).
    public let source: HandSource
    /// The client the text came from. `.pokerStars` is the only value this slice
    /// produces.
    public let site: PokerSite
    /// Seats at the table, 2...9.
    public let tableSize: Int
    /// The button's 0-based index into `seats` (which is sorted ascending).
    public let buttonSeat: Int
    /// Always 100: the model expresses every amount in centi-big-blinds, so the
    /// big blind itself is 1 BB = 100 centi-BB. Stored so "amounts are scaled by
    /// the big blind" is self-evident in the model rather than buried in the
    /// parser.
    public let bigBlindCentiBB: Int
    /// Seats in ascending seat-number order; `count == tableSize`.
    public let seats: [ObservedSeat]
    /// Blinds and antes, kept apart from voluntary actions so "six preflop
    /// actions" is unambiguous.
    public let forcedPosts: [ForcedPost]
    /// Streets from preflop onward; length 1...4.
    public let streets: [ObservedStreet]
    /// Rake and other end-of-hand facts.
    public let result: ObservedResult

    public init(
        source: HandSource,
        site: PokerSite,
        tableSize: Int,
        buttonSeat: Int,
        bigBlindCentiBB: Int,
        seats: [ObservedSeat],
        forcedPosts: [ForcedPost],
        streets: [ObservedStreet],
        result: ObservedResult
    ) {
        self.source = source
        self.site = site
        self.tableSize = tableSize
        self.buttonSeat = buttonSeat
        self.bigBlindCentiBB = bigBlindCentiBB
        self.seats = seats
        self.forcedPosts = forcedPosts
        self.streets = streets
        self.result = result
    }
}

public struct ObservedSeat: Hashable, Sendable, Codable {
    /// The PokerStars seat number (1-based), as printed in the text.
    public let seat: Int
    /// The seat's offset from the button, the input to `TablePosition`.
    public let seatOffsetFromButton: Int
    public let startingStackCentiBB: Int
    public let holeCards: HoleCards

    public init(
        seat: Int,
        seatOffsetFromButton: Int,
        startingStackCentiBB: Int,
        holeCards: HoleCards
    ) {
        self.seat = seat
        self.seatOffsetFromButton = seatOffsetFromButton
        self.startingStackCentiBB = startingStackCentiBB
        self.holeCards = holeCards
    }
}

/// A seat's hole cards, or the fact that they were never shown.
///
/// Unknown is a first-class value, not a sentinel pair: an opponent who never
/// showed down has cards nobody can name, and inventing two for them would be
/// exactly the kind of guess this slice refuses to make.
public enum HoleCards: Hashable, Sendable, Codable {
    case known(Card, Card)
    case unknown
}

public struct ObservedStreet: Hashable, Sendable, Codable {
    public let street: Street
    /// Community cards visible on this street; count matches the street.
    public let board: [Card]
    /// Voluntary actions only, in the order they occurred.
    public let actions: [ObservedAction]

    public init(street: Street, board: [Card], actions: [ObservedAction]) {
        self.street = street
        self.board = board
        self.actions = actions
    }
}

public struct ObservedAction: Hashable, Sendable, Codable {
    public let seat: Int
    public let kind: ActionKind
    /// nil for fold/check. For bet/call/raiseTo it is the total amount that seat
    /// has in front of it on this street after the action (the "to" amount), so
    /// a call that matches a raise records the same number as the raise.
    public let amountCentiBB: Int?

    public init(seat: Int, kind: ActionKind, amountCentiBB: Int?) {
        self.seat = seat
        self.kind = kind
        self.amountCentiBB = amountCentiBB
    }
}

/// A voluntary action. Forced posts (blinds, antes) are not here — they are
/// `ForcedPost` — so counting the entries on a street counts decisions.
public enum ActionKind: String, Hashable, Sendable, Codable {
    case fold
    case check
    case call
    case bet
    case raiseTo
}

/// A blind or ante: money in the pot that the rules demanded, not a decision.
public struct ForcedPost: Hashable, Sendable, Codable {
    public let seat: Int
    public let kind: ForcedPostKind
    public let amountCentiBB: Int

    public init(seat: Int, kind: ForcedPostKind, amountCentiBB: Int) {
        self.seat = seat
        self.kind = kind
        self.amountCentiBB = amountCentiBB
    }
}

public enum ForcedPostKind: String, Hashable, Sendable, Codable {
    case smallBlind
    case bigBlind
    case ante
}

public struct ObservedResult: Hashable, Sendable, Codable {
    /// Rake taken from the pot. May be non-zero (appendix A = 50) — the most
    /// direct difference between an observed hand and a simulated one.
    public let rakeCentiBB: Int

    public init(rakeCentiBB: Int) {
        self.rakeCentiBB = rakeCentiBB
    }
}

public enum PokerSite: String, Hashable, Sendable, Codable {
    case pokerStars
}

extension ObservedHand {
    /// The deterministic encoding used for byte-for-byte comparison and the
    /// golden fixture. Keys are sorted so the bytes do not depend on Swift's
    /// property order; slashes are not escaped so card and text fields read
    /// plainly. Same shape as `OpponentActionGolden.encodedJSON()`.
    public func canonicalJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
