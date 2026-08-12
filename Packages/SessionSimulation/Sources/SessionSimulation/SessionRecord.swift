import Foundation
import PokerCore

/// Which profile sits in each of the five opponent seats.
///
/// Five entries, not six: the hero sits in seat 0 and is the user. Indexed by
/// seat minus one, and stored as an array rather than a dictionary because a
/// dictionary's encoding order is not fixed and a record has to compare byte
/// for byte across launches.
public struct SeatAssignment: Hashable, Sendable, Codable {
    /// Seats 1 through 5, in seat order.
    public let opponentProfiles: [OpponentProfileID]

    public init(opponentProfiles: [OpponentProfileID]) {
        precondition(
            opponentProfiles.count == TableRules.seatCount - 1,
            "A 6-max table seats five opponents, got \(opponentProfiles.count)"
        )
        self.opponentProfiles = opponentProfiles
    }

    public func profile(forSeat seat: Int) -> OpponentProfileID? {
        guard seat != TableRules.heroSeat,
              (1 ..< TableRules.seatCount).contains(seat)
        else {
            return nil
        }
        return opponentProfiles[seat - 1]
    }

    /// Label mixed into the seat-assignment stream.
    ///
    /// A third label, distinct from the deck's and the action stream's. Sharing
    /// one would make the seating a function of the first cards off the deck.
    private static let assignmentStreamLabel: UInt64 = 0x0000_0000_0000_0003

    /// The seating a seed produces.
    ///
    /// Derived rather than chosen so that a seed alone is enough to start a
    /// session, and recorded anyway so that changing this derivation cannot
    /// silently reseat an existing record's table.
    public static func derived(seed: UInt64) -> SeatAssignment {
        var rng = SplitMix64(
            seed: SplitMix64.derivedSeed(base: seed, label: assignmentStreamLabel)
        )
        let all = OpponentProfileID.allCases
        return SeatAssignment(
            opponentProfiles: (1 ..< TableRules.seatCount).map { _ in
                all[Int(rng.nextBelow(UInt64(all.count)))]
            }
        )
    }
}

/// What a session is, before any of it has been played.
///
/// The four fields are the whole of what a replay needs from the setup, and
/// each one is here because leaving it out breaks replay in a different way:
/// the seed fixes the cards, the seating fixes who is playing which behaviour,
/// the behaviour-table version fixes what those behaviours *are*, and the hand
/// count fixes where the session ends.
public struct SessionRecord: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let seed: UInt64
    public let seating: SeatAssignment

    /// The value of `OpponentProfileTable.version` when the session was
    /// created. Not re-read at replay time — that is the entire point.
    public let opponentProfileTableVersion: String
    public let handCount: Int

    public init(
        id: UUID,
        seed: UInt64,
        seating: SeatAssignment,
        opponentProfileTableVersion: String = OpponentProfileTable.version,
        handCount: Int
    ) {
        precondition(handCount > 0, "A session plays at least one hand")

        self.id = id
        self.seed = seed
        self.seating = seating
        self.opponentProfileTableVersion = opponentProfileTableVersion
        self.handCount = handCount
    }

    /// A session from a seed alone, seated by that seed.
    public init(id: UUID, seed: UInt64, handCount: Int) {
        self.init(
            id: id,
            seed: seed,
            seating: SeatAssignment.derived(seed: seed),
            handCount: handCount
        )
    }

    /// The policy table this record's opponents play.
    public func policy(
        heroPolicy: any SessionActionPolicy
    ) -> SeatedActionPolicy {
        SeatedActionPolicy(heroPolicy: heroPolicy, seating: seating)
    }
}

/// One played hand, as it is stored.
///
/// A record of what happened, not of the machinery that produced it: no legal
/// sets, no betting contexts, no undealt board. What is kept is what a replay
/// has to reproduce and what a review screen has to show — and the hero's
/// decision signatures, which are facts about the spots the hero faced and the
/// only thing the app layer needs in order to ask whether installed content has
/// anything to say about them.
public struct SessionHandRecord: Hashable, Sendable, Codable {
    public let handIndex: Int
    public let buttonSeat: Int
    public let holeCards: [[Card]]
    public let board: [Card]
    public let actions: [RecordedAction]
    public let result: HandResult
    public let startingStacks: [BBAmount]
    public let endingStacks: [BBAmount]

    /// The signature of every spot the hero acted on, in order.
    ///
    /// A pure fact about the hand. Whether any of them corresponds to installed
    /// content is a question for the layer that can see both, and it is not
    /// answered here: this package does not know that teaching content exists.
    public let heroSpotSignatures: [SpotSignature]

    public init(_ hand: PlayedHand) {
        handIndex = hand.handIndex
        buttonSeat = hand.buttonSeat
        holeCards = hand.holeCards
        board = hand.board
        actions = hand.actions
        result = hand.result
        startingStacks = hand.startingStacks
        endingStacks = hand.endingStacks
        heroSpotSignatures = hand.decisions
            .filter { $0.seat == TableRules.heroSeat }
            .map(\.signature)
    }

    /// The hero's actions, in the order they were taken.
    ///
    /// What a rebuild feeds back in. Opponent behaviour is a function of the
    /// seed and the table, but the hero is a person: without their actions a
    /// rebuild reproduces the cards and then plays a different hand.
    public var heroActions: [DecisionAction] {
        actions.filter { $0.seat == TableRules.heroSeat }.map(\.action)
    }

    /// Each spot the hero faced, paired with what they did in it.
    ///
    /// The two arrays are parallel by construction: the runner records a
    /// decision point and then applies exactly one action for it, and blind
    /// posts are committed without going through the action log. Paired here
    /// rather than at each call site so that the invariant has one place to be
    /// stated and one place to be tested — `SessionHandRecordTests` asserts the
    /// counts agree, and the streets line up, across a sweep of seeds.
    public var heroSpots: [HeroSpot] {
        zip(heroSpotSignatures, heroActions).map(HeroSpot.init)
    }
}

/// One spot the hero faced and the action they chose in it.
public struct HeroSpot: Hashable, Sendable {
    public let signature: SpotSignature
    public let action: DecisionAction

    public init(signature: SpotSignature, action: DecisionAction) {
        self.signature = signature
        self.action = action
    }
}

/// Where a stored session stands.
public struct SessionProgress: Hashable, Sendable {
    public let record: SessionRecord
    public let playedHands: [SessionHandRecord]

    public init(record: SessionRecord, playedHands: [SessionHandRecord]) {
        self.record = record
        self.playedHands = playedHands
    }

    /// The index of the hand to deal next.
    ///
    /// Derived from how many hands are on disk, not from a counter kept
    /// alongside them. A counter can survive a crash that the hands did not,
    /// and then the session resumes past a hand nobody played.
    public var nextHandIndex: Int {
        playedHands.count
    }

    public var isComplete: Bool {
        playedHands.count >= record.handCount
    }

    /// The stacks the next hand starts from.
    ///
    /// Carried from the last stored hand. Restarting from 100BB apiece would
    /// deal identical cards — they come from the hand index — while every
    /// action after the first bet came out different, which is the failure this
    /// value exists to prevent.
    public var stacks: [BBAmount] {
        playedHands.last?.endingStacks ?? SessionRunner.initialStacks
    }
}
