import PokerCore

/// One of the four disclosed profiles, playing a seat.
///
/// ## What it is
///
/// A behaviour table, in the literal sense: three numbers per profile, two
/// lookup tables for position and aggression faced, and a pair of dice rolls.
/// There is no search, no learning and no strategy — `OpponentProfileTable`
/// discloses exactly that to the user, and this type is what the disclosure is
/// about.
///
/// ## The shape of a decision
///
/// Preflop, whether the seat plays at all is **not** random: the hand class is
/// ranked by `PreflopHandRanking` and the seat enters when the class falls
/// inside its entry rate, widened or tightened by where it sits and by how much
/// aggression it faces. That is what makes the stated entry rate honest — it is
/// the threshold itself rather than a knob that correlates with one.
///
/// Postflop, continuing is a roll against the calling tendency and whether
/// continuing means raising is a roll against aggression. Both curves pass
/// through the stated figure at a medium holding, so each number on the screen
/// is a frequency the code actually plays rather than one it gestures at.
///
/// ## Two rolls, always
///
/// `chooseAction` draws exactly two values from the generator on every call,
/// including on the branches that do not look at them. Consumption therefore
/// does not depend on the branch taken, which keeps the action stream aligned
/// when different profiles sit at the same table: seat 3 changing its mind
/// cannot shift the dice seat 4 is about to get. It also makes the twenty-spot
/// comparison a comparison of choices rather than of stream positions.
public struct OpponentActionPolicy: SessionActionPolicy {
    public let profile: OpponentProfile

    public init(profile: OpponentProfile) {
        self.profile = profile
    }

    public func chooseAction(at decision: DecisionPoint, using rng: inout SplitMix64) -> DecisionAction {
        let actions = decision.orderedLegalActions
        precondition(!actions.isEmpty, "A decision point must offer at least one action")

        // See the note on this type: two draws on every path.
        let continueRoll = Int(rng.nextBelow(10_000))
        let aggressionRoll = Int(rng.nextBelow(10_000))

        let intent = intent(
            at: decision,
            continueRoll: continueRoll,
            aggressionRoll: aggressionRoll
        )
        return resolve(intent, among: actions)
    }

    // MARK: - Deciding

    /// What the seat wants to do, before the legal set gets a say.
    private enum Intent {
        /// Put nothing more in: check if that is free, otherwise fold.
        case giveUp
        /// Stay in for the current price.
        case passive
        /// Put more in than the current price.
        case aggressive
    }

    private func intent(
        at decision: DecisionPoint,
        continueRoll: Int,
        aggressionRoll: Int
    ) -> Intent {
        if decision.street == .preflop {
            guard entersPot(at: decision) else {
                return .giveUp
            }
            // A hand strong enough to play is somewhere in the top of the
            // range, so its strength is the complement of its percentile.
            let strength = 100 - PreflopHandRanking
                .percentileBasisPoints(decision.handClass) / 100
            return aggressionRoll < aggressionFrequency(strength: strength)
                ? .aggressive
                : .passive
        }

        let strength = Self.madeHandStrength(
            holeCards: decision.holeCards,
            board: decision.board
        )
        let facingBet = decision.context.amountToCall.centiBB > 0

        // Nothing to fold to: the only question is whether to bet.
        if !facingBet {
            return aggressionRoll < aggressionFrequency(strength: strength)
                ? .aggressive
                : .passive
        }

        guard continueRoll < continueFrequency(strength: strength) else {
            return .giveUp
        }
        return aggressionRoll < aggressionFrequency(strength: strength)
            ? .aggressive
            : .passive
    }

    /// Whether the profile plays this hand class from this seat.
    ///
    /// Deterministic. Two profiles at the same spot differ here whenever the
    /// hand falls between their entry rates, which is most of what makes them
    /// distinguishable on a fixed set of spots — randomness alone would leave
    /// the difference to chance.
    private func entersPot(at decision: DecisionPoint) -> Bool {
        let percentile = PreflopHandRanking.percentileBasisPoints(decision.handClass)
        let threshold = profile.entryRateBasisPoints
            * Self.positionFactor(seatOffsetFromButton: decision.seatOffsetFromButton) / 100
            * Self.facingFactor(decision.facing) / 100
        return percentile <= threshold
    }

    /// How often the profile continues rather than folds, given the holding.
    ///
    /// Linear in the strength, passing through the stated tendency at 50 and
    /// reaching certainty at 75, clamped at both ends. Two things follow, and
    /// both are deliberate:
    ///
    /// - Nobody folds the nuts. A multiplicative scaling around the stated
    ///   figure would leave the tightest profile folding a straight flush more
    ///   than three quarters of the time, which is not a tight opponent but a
    ///   broken one.
    /// - The slope comes from the stated figure itself, so the profile that
    ///   folds most is also the one whose decision depends most on its cards:
    ///   the rock continues with nothing below a strength of 44 and with
    ///   everything above 75, while the station is nearly flat and calls 55% of
    ///   the time holding the worst hand on the board. That is the difference
    ///   between a nit and a station as players describe it, and it is what
    ///   makes the two distinguishable on spots where both are passive.
    private func continueFrequency(strength: Int) -> Int {
        let stated = profile.callingTendencyBasisPoints
        let clamped = min(100, max(0, strength))
        let slope = (10_000 - stated) / 25
        return min(10_000, max(0, stated + (clamped - 50) * slope))
    }

    /// How often the profile takes the aggressive line once it is continuing.
    ///
    /// Scaled around the stated figure rather than pinned at the ends: half at
    /// a strength of zero, the stated value at 50, half again at 100. Bluffs
    /// have to survive — a curve that reached zero with a weak holding would
    /// make every bet an announcement of a made hand, and an opponent nobody
    /// ever has to read is not practice.
    private func aggressionFrequency(strength: Int) -> Int {
        let clamped = min(100, max(0, strength))
        return min(10_000, profile.aggressionBasisPoints * (50 + clamped) / 100)
    }

    /// A 0–100 read on a made hand, calibrated so that the middle of the range
    /// is the middle of what actually turns up.
    ///
    /// Two pair sits at the pivot the frequencies are anchored to, top pair a
    /// little under it and a straight or better well above. Spreading the
    /// categories out this way is the whole point: with the categories packed
    /// into the bottom quarter — which is what a `rawValue * 11` scale does —
    /// every profile reads every holding as weak and the stated tendencies stop
    /// describing the play.
    private static func madeHandStrength(holeCards: [Card], board: [Card]) -> Int {
        let ranking = HandEvaluator.evaluate(holeCards: holeCards, board: board)
        // The most significant tiebreaker: the pair's rank for a pair, the
        // higher pair's for two pair, the top card for a straight. Ace-low
        // straights spell it -1, so the floor matters.
        let top = max(0, ranking.tiebreakers.first ?? 0)

        return switch ranking.category {
        case .highCard: top * 20 / 12 // 0...20
        case .pair: 25 + top * 30 / 12 // 25...55
        case .twoPair: 58 + top // 58...70
        case .threeOfAKind: 72 + top / 2 // 72...78
        case .straight: 82
        case .flush: 86
        case .fullHouse: 92
        case .fourOfAKind: 97
        case .straightFlush: 100
        }
    }

    /// How much wider the profile plays from each seat, as a percentage of its
    /// stated entry rate.
    ///
    /// Indexed by offset from the button: 0 is the button, 1 the small blind, 2
    /// the big blind, then UTG, hijack and cutoff. **The six factors sum to
    /// 600**, so the stated entry rate is exactly the average across the table
    /// rather than a figure that happens to be near one. A test checks the
    /// realised average against the stated value, and it is the reason the
    /// loosest profile stops at 62%: from 6,250 upward the button factor would
    /// clip against 100% and drag the average below what the profile claims.
    private static func positionFactor(seatOffsetFromButton offset: Int) -> Int {
        switch offset {
        case 0: 160 // BTN
        case 1: 110 // SB
        case 2: 115 // BB
        case 3: 60 // UTG
        case 4: 75 // HJ
        default: 80 // CO
        }
    }

    /// How much the profile tightens for the aggression already in front of it,
    /// as a percentage of its entry rate.
    private static func facingFactor(_ facing: FacingAction) -> Int {
        switch facing {
        case .unopened: 100
        case .singleRaise: 65
        case .reraise: 35
        }
    }

    // MARK: - Turning an intent into a legal action

    /// Picks the action that best expresses the intent *out of the legal set*.
    ///
    /// Every returned value comes from `actions`, so an illegal action cannot
    /// escape this function however the intent was arrived at. The fallbacks
    /// are where the short-stack rule lives: with the call already equal to the
    /// whole stack there is no raise and no separate all-in to reach for, so an
    /// aggressive intent collapses into the call — which *is* the shove — and a
    /// give-up intent stays a fold.
    private func resolve(_ intent: Intent, among actions: [DecisionAction]) -> DecisionAction {
        let check = actions.first { $0 == .check }
        let fold = actions.first { $0 == .fold }
        let call = actions.first { if case .call = $0 { true } else { false } }

        switch intent {
        case .giveUp:
            // Never pay to leave: checking is free whenever it is offered.
            return check ?? fold ?? actions[0]
        case .passive:
            return check ?? call ?? actions[0]
        case .aggressive:
            return aggressiveAction(among: actions) ?? call ?? check ?? actions[0]
        }
    }

    /// The size this profile puts in when it decides to be aggressive.
    ///
    /// Sizes arrive in ascending order from `orderedLegalActions`, and which
    /// one is taken is a function of the stated aggression alone: three
    /// brackets, smallest, middle and largest. So two profiles that both decide
    /// to raise still raise differently — a passive profile that occasionally
    /// bets does not suddenly bet like a maniac.
    ///
    /// Four profiles into three brackets means one is shared: the rock and the
    /// station both take the smallest size. They are the two passive profiles
    /// and neither is characterised by how much it bets, so the collision costs
    /// nothing that the other two axes do not already say.
    private func aggressiveAction(among actions: [DecisionAction]) -> DecisionAction? {
        let sizes = actions.filter { action in
            switch action {
            case .bet, .raise: true
            default: false
            }
        }
        guard !sizes.isEmpty else {
            // No size below the stack: shoving is the only way to be
            // aggressive, and it may not be on offer either.
            return actions.first { if case .allIn = $0 { true } else { false } }
        }

        let index = switch profile.aggressionBasisPoints {
        case ..<3_000: 0
        case ..<7_500: sizes.count / 2
        default: sizes.count - 1
        }
        return sizes[index]
    }
}
