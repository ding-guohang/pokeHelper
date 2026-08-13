import CryptoKit
import Foundation
import PokerCore

/// Why a hand-built spot was rejected.
///
/// Every case names one broken precondition so the builder screen can point at
/// the field the user got wrong instead of a generic "invalid". `Equatable` so a
/// test can assert *which* rejection fired, not merely that one did — the four
/// cases are distinguishable and a build must throw the one its input earns.
public enum ConstructedSpotError: Error, Equatable {
    /// A hole-card code that `Card(code:)` could not parse, carrying the offending
    /// string.
    case unparseableCard(String)
    /// The hole cards did not number exactly two, carrying the count given. A
    /// wrong count is not a duplicate: this fires before distinctness is asked,
    /// so `.duplicateCards` means "two parseable cards that were equal".
    case wrongCardCount(Int)
    /// The two hole cards parsed and numbered two, but were the same card.
    case duplicateCards
    /// The effective stack was zero or negative; centi-BB is always positive.
    case nonPositiveStack
    /// The seat offset does not name a seat at a six-handed table.
    case seatOutOfRange
}

/// A preflop spot a user assembled by hand, as distinct from one replayed out of
/// an imported hand.
///
/// It carries only pure poker facts — where the hero sits, the two cards held,
/// how much aggression is faced, how deep the stacks are, and what the hero did —
/// so it lives in `HandHistory` beside `ObservedHand` and never reaches for a
/// filesystem, UI or training event. Whether installed content covers the spot is
/// a question the app layer asks with `signature()`; this type only states the
/// spot.
public struct ConstructedSpot: Hashable, Sendable, Codable {
    /// The hero's 0-based offset from the button. Validated against a six-handed
    /// table on construction.
    public let heroSeatOffsetFromButton: Int
    /// Exactly two distinct hole cards.
    public let holeCards: [Card]
    /// How much aggression the hero faces.
    public let facing: FacingAction
    /// The effective stack in centi-big-blinds; always positive.
    public let effectiveStackCentiBB: Int
    /// The action the hero took in this spot.
    public let action: DecisionAction

    /// Builds a spot from user input, validating one precondition at a time.
    ///
    /// The order is fixed so the error a build throws is deterministic: cards
    /// must parse, then number exactly two, then be distinct, then the stack must
    /// be positive, then the seat must exist at a six-handed table. `tableSize` is
    /// pinned to six for this slice — the builder offers no other size.
    public init(
        heroSeatOffsetFromButton: Int,
        holeCardCodes: [String],
        facing: FacingAction,
        effectiveStackCentiBB: Int,
        action: DecisionAction
    ) throws {
        var parsed: [Card] = []
        for code in holeCardCodes {
            guard let card = Card(code: code) else {
                throw ConstructedSpotError.unparseableCard(code)
            }
            parsed.append(card)
        }

        guard parsed.count == 2 else {
            throw ConstructedSpotError.wrongCardCount(parsed.count)
        }

        guard Set(parsed).count == 2 else {
            throw ConstructedSpotError.duplicateCards
        }

        // Normalize to a canonical order so the two hole cards produce the same
        // stored order, canonical bytes and identity regardless of input order —
        // `["As","Kd"]` and `["Kd","As"]` are one spot, not two. `signature()`
        // was already order-independent (it reads `HandClass`); this makes the
        // stored form agree. The key is a total order over two distinct cards:
        // higher rank first, then suit by its declared case order.
        let ordered = parsed.sorted { lhs, rhs in
            let lhsRank = Rank.allCases.firstIndex(of: lhs.rank) ?? 0
            let rhsRank = Rank.allCases.firstIndex(of: rhs.rank) ?? 0
            if lhsRank != rhsRank {
                return lhsRank > rhsRank
            }
            let lhsSuit = Suit.allCases.firstIndex(of: lhs.suit) ?? 0
            let rhsSuit = Suit.allCases.firstIndex(of: rhs.suit) ?? 0
            return lhsSuit < rhsSuit
        }

        guard effectiveStackCentiBB > 0 else {
            throw ConstructedSpotError.nonPositiveStack
        }

        do {
            _ = try TablePosition(
                tableSize: 6,
                heroSeatOffsetFromButton: heroSeatOffsetFromButton
            )
        } catch {
            throw ConstructedSpotError.seatOutOfRange
        }

        self.heroSeatOffsetFromButton = heroSeatOffsetFromButton
        self.holeCards = ordered
        self.facing = facing
        self.effectiveStackCentiBB = effectiveStackCentiBB
        self.action = action
    }

    /// The spot's signature, so the app layer can ask whether content covers it.
    ///
    /// A constructed spot is always preflop in this slice; every other component
    /// is computed from the stored facts exactly the way `heroDecisionSignatures`
    /// computes it from an imported hand, so a hand-built spot and a replayed one
    /// with the same facts produce the same key.
    public func signature() -> SpotSignature {
        SpotSignature(
            street: .preflop,
            heroSeatOffsetFromButton: heroSeatOffsetFromButton,
            handClass: HandClass(holeCards[0], holeCards[1]),
            facing: facing,
            stackBucket: StackBucket(
                effectiveStack: BBAmount(centiBB: effectiveStackCentiBB)
            )
        )
    }

    /// The deterministic encoding used for on-disk storage and identity. Keys are
    /// sorted so the bytes do not depend on Swift's property order; slashes are
    /// not escaped so card codes read plainly. Same shape as
    /// `ObservedHand.canonicalJSON()`.
    public func canonicalJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// Lowercase hex SHA-256 of `canonicalJSON()` — two spots are "the same spot"
    /// when their identities match. Mirrors `HandSource`'s digest.
    public var identity: String {
        guard let data = try? canonicalJSON() else { return "" }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
