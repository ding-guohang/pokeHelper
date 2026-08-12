import PokerCore

/// One hand, played out.
public struct PlayedHand: Hashable, Sendable {
    public let handIndex: Int
    public let buttonSeat: Int
    public let holeCards: [[Card]]

    /// The community cards the hand reached — 0, 3, 4 or 5 of them.
    public let board: [Card]
    public let actions: [RecordedAction]
    public let result: HandResult
    public let startingStacks: [BBAmount]
    public let endingStacks: [BBAmount]

    /// Every decision point that came up, in order.
    ///
    /// Kept because the legal-set property is about the points, not the
    /// outcome: a test has to be able to walk back over them and check both
    /// that everything offered was accepted and that everything else was
    /// refused.
    public let decisions: [DecisionPoint]
}

/// A run of hands from one seed.
public struct SessionRun: Hashable, Sendable {
    public let seed: UInt64
    public let hands: [PlayedHand]
    public let finalStacks: [BBAmount]

    /// The table broke up before `handCount` hands: fewer than two seats held
    /// chips, so no further hand could be dealt. A completed run leaves this
    /// `false`.
    public let endedEarly: Bool

    /// The whole table's chips. Fixed at `seatCount × 100BB` for a rake-free
    /// table with no rebuys, however the hands went.
    public var totalChips: BBAmount {
        BBAmount(centiBB: finalStacks.reduce(0) { $0 + $1.centiBB })
    }
}

/// Plays hands from a seed.
///
/// The seed and the policy are the whole input. There is no clock, no system
/// randomness and no stored mutable state, so two processes handed the same
/// pair produce the same session — which is the only claim in this package that
/// cannot be checked from inside a single process.
public struct SessionRunner: Sendable {
    public let seed: UInt64
    public let policy: any SessionActionPolicy
    public let dealer: SessionDealer

    public init(seed: UInt64, policy: any SessionActionPolicy = BaselineActionPolicy()) {
        self.seed = seed
        self.policy = policy
        dealer = SessionDealer(seed: seed)
    }

    /// Label for the action stream, distinct from the dealer's deck label.
    ///
    /// Distinct so the two streams are unrelated. Sharing a label would make
    /// them the same sequence, and an opponent's choices would then be a
    /// function of the cards that were about to come off the deck.
    private static let actionStreamLabel: UInt64 = 0x0000_0000_0000_0002

    /// The action stream for one hand.
    ///
    /// Public because a caller resuming an interrupted session at hand 8 has to
    /// reach hand 8's stream without replaying hands 0 through 7, and because
    /// tests step through a hand by hand instead of calling `run`.
    public func actionSeed(handIndex: Int) -> UInt64 {
        SplitMix64.derivedSeed(
            base: seed,
            label: Self.actionStreamLabel &+ UInt64(bitPattern: Int64(handIndex)) &* 0x1_0000
        )
    }

    /// The stacks every session starts from: 100BB in each of the six seats.
    public static var initialStacks: [BBAmount] {
        [BBAmount](repeating: TableRules.startingStack, count: TableRules.seatCount)
    }

    /// A hand needs at least this many seats holding chips: one to post the
    /// small blind and one to post the big. With fewer there is no hand.
    public static let minimumSeatsToDeal = 2

    /// How many of these stacks still hold chips.
    public static func seatsWithChips(_ stacks: [BBAmount]) -> Int {
        stacks.count { $0.centiBB > 0 }
    }

    /// Plays one hand from a given set of stacks.
    public func playHand(handIndex: Int, stacks: [BBAmount]) -> PlayedHand {
        let dealtHand = dealer.deal(handIndex: handIndex)
        var state = HandState(dealtHand: dealtHand, stacks: stacks)
        var rng = SplitMix64(seed: actionSeed(handIndex: handIndex))
        var decisions: [DecisionPoint] = []

        // A hand cannot need more decisions than this: four streets, six seats,
        // and a bounded number of re-raises before somebody is all-in. The cap
        // turns a state machine that fails to make progress into a named crash
        // instead of a hang, which is the difference between a five-minute
        // diagnosis and a CI timeout with no output.
        var stepsRemaining = 4 * TableRules.seatCount * 64
        while !state.isComplete {
            guard let decision = state.currentDecision() else {
                preconditionFailure("Hand \(handIndex) is unfinished but has nobody to act")
            }
            decisions.append(decision)

            let action = policy.chooseAction(at: decision, using: &rng)
            do {
                try state.apply(action)
            } catch {
                preconditionFailure(
                    "Policy returned \(action) at seat \(decision.seat), which the state machine "
                        + "refused with \(error). Legal set was \(decision.orderedLegalActions)."
                )
            }

            stepsRemaining -= 1
            precondition(stepsRemaining > 0, "Hand \(handIndex) did not terminate")
        }

        guard let result = state.result else {
            preconditionFailure("A completed hand must have a result")
        }

        return PlayedHand(
            handIndex: handIndex,
            buttonSeat: dealtHand.buttonSeat,
            holeCards: dealtHand.holeCards,
            board: result.board,
            actions: state.actionLog,
            result: result,
            startingStacks: stacks,
            endingStacks: state.endingStacks,
            decisions: decisions
        )
    }

    /// Plays a whole session, carrying stacks from hand to hand.
    ///
    /// No rebuy: a seat that busts stays at zero and is dealt out of subsequent
    /// hands. That is what keeps the table total at 600BB rather than making it
    /// a function of how many times somebody topped up.
    public func run(handCount: Int) -> SessionRun {
        precondition(handCount >= 0, "Hand count cannot be negative")

        var stacks = Self.initialStacks
        var hands: [PlayedHand] = []
        hands.reserveCapacity(handCount)

        for handIndex in 0 ..< handCount {
            // A hand with fewer than two funded seats has no blinds to post and
            // is not a hand. The session ends here rather than dealing it.
            guard Self.seatsWithChips(stacks) >= Self.minimumSeatsToDeal else {
                break
            }
            let played = playHand(handIndex: handIndex, stacks: stacks)
            stacks = played.endingStacks
            hands.append(played)
        }

        return SessionRun(
            seed: seed,
            hands: hands,
            finalStacks: stacks,
            endedEarly: hands.count < handCount
        )
    }
}
