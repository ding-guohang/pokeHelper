import Foundation

/// Which betting round a spot belongs to.
public enum Street: String, Hashable, Sendable, CaseIterable, Codable {
    case preflop
    case flop
    case turn
    case river

    /// The street implied by how many community cards are out.
    public init?(boardCardCount: Int) {
        switch boardCardCount {
        case 0: self = .preflop
        case 3: self = .flop
        case 4: self = .turn
        case 5: self = .river
        default: return nil
        }
    }

    public var boardCardCount: Int {
        switch self {
        case .preflop: 0
        case .flop: 3
        case .turn: 4
        case .river: 5
        }
    }
}

/// How much aggression the acting player is facing.
///
/// Coarse on purpose. It exists to key a spot against curated content, and
/// content is authored for "unopened", "facing a raise" and "facing a
/// re-raise" — not for an unbounded count of raises.
public enum FacingAction: String, Hashable, Sendable, CaseIterable, Codable {
    case unopened
    case singleRaise
    case reraise

    /// Derived from how many aggressive actions preceded this decision.
    /// Anything beyond a re-raise is still `reraise`: no content distinguishes
    /// a 4-bet from a 5-bet, so pretending the key does would produce buckets
    /// that never match.
    public init(priorRaiseCount: Int) {
        switch priorRaiseCount {
        case ..<1: self = .unopened
        case 1: self = .singleRaise
        default: self = .reraise
        }
    }
}

/// Effective stack, coarsened into the buckets spot equivalence compares on.
///
/// Stack depth is continuous, and comparing it exactly would mean a dealt hand
/// essentially never matches a curated scenario. The boundaries are fixed here
/// rather than tuned per caller so that two sides producing a signature cannot
/// disagree about them.
public enum StackBucket: String, Hashable, Sendable, CaseIterable, Codable {
    /// Under 20BB.
    case short
    /// 20BB up to 60BB.
    case medium
    /// 60BB up to 120BB.
    case deep
    /// 120BB and above.
    case veryDeep

    public init(effectiveStack: BBAmount) {
        switch effectiveStack.centiBB {
        case ..<2_000: self = .short
        case ..<6_000: self = .medium
        case ..<12_000: self = .deep
        default: self = .veryDeep
        }
    }
}

/// The identity of a betting spot, for deciding whether a hand dealt in a
/// session corresponds to a scenario in the installed content.
///
/// Lives in PokerCore because every component is a fact about the hand rather
/// than about teaching: which street, where the hero sits, what two cards they
/// hold, how much aggression they face, how deep the stacks are. That placement
/// is what keeps `SessionSimulation` from having to import `StrategyContent`
/// and `TrainingDomain` from having to import `SessionSimulation` — the second
/// of which would be an import cycle.
///
/// A false match costs the user one irrelevant comparison on a review screen.
/// It cannot corrupt the ability profile, because session hands never produce
/// training events.
public struct SpotSignature: Hashable, Sendable, Codable {
    public let street: Street
    public let heroSeatOffsetFromButton: Int
    public let handClass: HandClass
    public let facing: FacingAction
    public let stackBucket: StackBucket

    public init(
        street: Street,
        heroSeatOffsetFromButton: Int,
        handClass: HandClass,
        facing: FacingAction,
        stackBucket: StackBucket
    ) {
        self.street = street
        self.heroSeatOffsetFromButton = heroSeatOffsetFromButton
        self.handClass = handClass
        self.facing = facing
        self.stackBucket = stackBucket
    }
}

extension HandClass: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let notation = try container.decode(String.self)
        guard let parsed = HandClass(notation: notation) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Hand class must be 169-cell notation such as AKs, AKo or 77"
            )
        }
        self = parsed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
