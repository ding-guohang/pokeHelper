import Foundation

public extension Rank {
    /// 0 for a deuce through 12 for an ace.
    ///
    /// Written as an exhaustive switch rather than derived from `allCases`, so
    /// adding a rank is a compile error here instead of a silently wrong index.
    var strength: Int {
        switch self {
        case .two: 0
        case .three: 1
        case .four: 2
        case .five: 3
        case .six: 4
        case .seven: 5
        case .eight: 6
        case .nine: 7
        case .ten: 8
        case .jack: 9
        case .queen: 10
        case .king: 11
        case .ace: 12
        }
    }
}

/// One of the 169 starting-hand classes — `AKs`, `AKo`, `77`.
///
/// The notation is not new to the project: `RangeCell.handClass` has always
/// been a `String` in exactly this form, and every value in the shipped content
/// pack parses. What is new is having a type, so a spot signature can be
/// compared by value instead of by string, and so a malformed class is caught
/// when content is validated rather than at the point of comparison.
///
/// `RangeCell.handClass` deliberately stays a `String`. Changing it would
/// change the pack's JSON bytes and therefore its checksum, which means
/// re-signing reviewed content for an internal tidy-up.
public struct HandClass: Hashable, Sendable, CustomStringConvertible {
    public enum Suitedness: String, Hashable, Sendable, CaseIterable {
        case pair
        case suited
        case offsuit
    }

    /// Always the stronger of the two ranks; equal to `lowRank` for a pair.
    public let highRank: Rank
    public let lowRank: Rank
    public let suitedness: Suitedness

    /// Classifies two concrete cards.
    ///
    /// Order-independent: the same two cards given either way round produce the
    /// same value. A signature built from a dealt hand and one built from a
    /// content range have to agree, and neither side controls the other's
    /// card order.
    public init(_ a: Card, _ b: Card) {
        if a.rank.strength >= b.rank.strength {
            highRank = a.rank
            lowRank = b.rank
        } else {
            highRank = b.rank
            lowRank = a.rank
        }

        // A pair is decided by rank, never by suit. The two checks happen to
        // commute for legal input — two distinct cards of the same rank cannot
        // share a suit, so a suit-first spelling still reaches the rank test —
        // and a mutation test confirmed that reordering them changes nothing.
        // Rank leads anyway because it is the property being asked about;
        // relying on the two branches being unreachable in the wrong order is
        // an argument the next reader should not have to reconstruct.
        suitedness = a.rank == b.rank
            ? .pair
            : (a.suit == b.suit ? .suited : .offsuit)
    }

    /// Parses the 169-cell notation used by `RangeCell.handClass`.
    ///
    /// Canonical form only — the higher rank leads, pairs carry no suffix. A
    /// non-canonical spelling like `KAs` is rejected rather than normalised, so
    /// that notation and value are in bijection and the round trip is total.
    public init?(notation: String) {
        let characters = Array(notation)
        guard characters.count == 2 || characters.count == 3,
              let first = Rank(rawValue: String(characters[0])),
              let second = Rank(rawValue: String(characters[1]))
        else {
            return nil
        }

        if characters.count == 2 {
            guard first == second else {
                return nil
            }
            highRank = first
            lowRank = second
            suitedness = .pair
            return
        }

        guard first.strength > second.strength else {
            return nil
        }
        switch characters[2] {
        case "s": suitedness = .suited
        case "o": suitedness = .offsuit
        default: return nil
        }
        highRank = first
        lowRank = second
    }

    public var description: String {
        switch suitedness {
        case .pair: highRank.rawValue + lowRank.rawValue
        case .suited: highRank.rawValue + lowRank.rawValue + "s"
        case .offsuit: highRank.rawValue + lowRank.rawValue + "o"
        }
    }

    /// All 169 classes, in a fixed order: pairs high to low, then suited, then
    /// offsuit. Fixed because tests enumerate it and because anything derived
    /// from it must not depend on hashing order.
    public static let all: [HandClass] = {
        let ranks = Rank.allCases.sorted { $0.strength > $1.strength }
        var classes: [HandClass] = []

        for rank in ranks {
            classes.append(HandClass(notation: rank.rawValue + rank.rawValue)!)
        }
        for suffix in ["s", "o"] {
            for (index, high) in ranks.enumerated() {
                for low in ranks.dropFirst(index + 1) {
                    classes.append(
                        HandClass(notation: high.rawValue + low.rawValue + suffix)!
                    )
                }
            }
        }
        return classes
    }()

    /// How many of the 1,326 two-card combinations fall into this class.
    public var combinationCount: Int {
        switch suitedness {
        case .pair: 6
        case .suited: 4
        case .offsuit: 12
        }
    }
}
