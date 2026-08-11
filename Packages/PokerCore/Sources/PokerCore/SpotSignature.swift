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

/// The identity of a *situation*, with the cards left out.
///
/// This is the key that answers "does installed content have anything to say
/// about this spot?", and it deliberately omits the hand class. A scenario's
/// hero cards are the example the training screen shows; its range table covers
/// the whole range — 47 to 102 classes each in the shipped pack. Keying
/// coverage on the example hand would require the user to be dealt that exact
/// hand: measured against the shipped pack over 6,000 dealt hands, the full
/// signature matched 15 of them, one hand in 400, 0.07 per 30-hand session. The
/// comparison loop that number describes does not exist.
///
/// The hero's actual cards are not thrown away, they are asked second: once the
/// situation is covered, the class is looked up in that scenario's range table.
/// A class the table omits is not a miss — it is the table saying it folds that
/// hand 100% of the time, which is as comparable an answer as any other.
public struct SpotCoverageKey: Hashable, Sendable, Codable {
    public let street: Street
    public let heroSeatOffsetFromButton: Int
    public let facing: FacingAction
    public let stackBucket: StackBucket

    public init(
        street: Street,
        heroSeatOffsetFromButton: Int,
        facing: FacingAction,
        stackBucket: StackBucket
    ) {
        self.street = street
        self.heroSeatOffsetFromButton = heroSeatOffsetFromButton
        self.facing = facing
        self.stackBucket = stackBucket
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

    /// This spot's situation, without the cards.
    ///
    /// The signature still answers "is this literally the same training
    /// scenario"; the coverage key answers the question a review screen
    /// actually asks, which is whether content covers the situation.
    public var coverageKey: SpotCoverageKey {
        SpotCoverageKey(
            street: street,
            heroSeatOffsetFromButton: heroSeatOffsetFromButton,
            facing: facing,
            stackBucket: stackBucket
        )
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
