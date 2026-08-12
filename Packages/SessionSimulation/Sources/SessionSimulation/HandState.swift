import PokerCore

/// What one seat looks like at a point in a hand.
public struct SeatSnapshot: Hashable, Sendable {
    public let seat: Int
    /// Chips still behind. This is the effective stack for that seat's next
    /// decision.
    public let stack: BBAmount
    public let committedThisStreet: BBAmount
    public let totalCommitted: BBAmount
    public let hasFolded: Bool

    /// In the hand with nothing behind. A seat that started the hand busted is
    /// folded, not all-in — it has no claim on the pot.
    public var isAllIn: Bool {
        !hasFolded && stack.centiBB == 0
    }
}

/// One action, as it happened.
public struct RecordedAction: Hashable, Sendable, Codable {
    public let seat: Int
    public let street: Street
    public let action: DecisionAction
    /// The pot after the chips went in, so a street-by-street replay does not
    /// have to re-run the arithmetic to show a running pot.
    public let potAfter: BBAmount
}

/// One layer of the pot and who took it.
public struct PotAward: Hashable, Sendable, Codable {
    public let amount: BBAmount
    /// Everyone still in the hand who had chips in this layer, ascending.
    public let eligibleSeats: [Int]
    /// Whoever took it, ascending. More than one on a chop.
    public let winningSeats: [Int]
    /// The hand that won it, or `nil` when everyone else folded and no cards
    /// were shown.
    public let winningRanking: HandRanking?
}

/// How a hand finished.
public struct HandResult: Hashable, Sendable, Codable {
    /// The furthest street the hand reached; `board.count` always matches it.
    public let streetReached: Street
    public let board: [Card]

    /// Everything that went in, across all seats and streets.
    public let potTotal: BBAmount
    public let contributions: [BBAmount]
    public let payouts: [BBAmount]

    /// Payout minus contribution, per seat, in centi-BB. Signed, so it cannot
    /// be a `BBAmount` — losing a hand is the ordinary case.
    public let stackDeltasCentiBB: [Int]

    /// Seats that had to show, ascending. Empty when the hand ended on a fold.
    public let showdownSeats: [Int]
    public let pots: [PotAward]

    /// Rake, which is zero for the whole of M2A.
    ///
    /// Present as a field so that chip conservation is a claim about a stated
    /// quantity. An engine with no rake concept at all would satisfy
    /// "deltas sum to zero" no matter what it did with the pot.
    public let rake: BBAmount
}

/// The betting state machine for a single hand.
///
/// Two things it guarantees, and they are the same guarantee read from either
/// side: `legalActions()` returns every action the machine will accept, and
/// `apply(_:)` rejects everything else. A machine that only promised the first
/// half could return `{.fold}` forever and still be "sound".
///
/// Every amount is incremental — the chips the acting player adds from their
/// remaining stack right now — matching `BettingDecisionContext.amountToCall`.
/// So `.raise(to: 600)` with 200 already in for the street means 600 more, not
/// 600 total. The alternative convention would make the cap against the
/// effective stack a two-term comparison at every site, which is where the
/// off-by-ones live.
public struct HandState: Hashable, Sendable {
    public let dealtHand: DealtHand
    public let startingStacks: [BBAmount]

    // Everything below is centi-BB in plain `Int`. `BBAmount` cannot be
    // negative and traps rather than wrapping, which is right for a value at
    // an API boundary and wrong for intermediate arithmetic — the pot layers in
    // settlement legitimately pass through subtractions.
    private var stacks: [Int]
    private var committedThisStreet: [Int]
    private var totalCommitted: [Int]
    private var folded: [Bool]

    /// Seats that still owe the machine a decision this street.
    private var needsToAct: [Bool]

    /// The largest amount committed to this street by any one seat.
    private var currentBet: Int

    /// The size of the last full raise, which sets the minimum for the next
    /// one. Starts at one big blind on every street.
    private var lastFullRaiseIncrement: Int

    /// How many voluntary aggressive actions this street has seen. Blind posts
    /// are not aggression, so a preflop spot with no open is `.unopened`.
    private var raiseCountThisStreet: Int

    /// Where the search for the next actor begins.
    private var searchStartSeat: Int

    public private(set) var street: Street
    public private(set) var pot: BBAmount
    public private(set) var actionLog: [RecordedAction]
    public private(set) var seatToAct: Int?
    public private(set) var result: HandResult?

    public var isComplete: Bool {
        result != nil
    }

    /// Starts a hand: marks busted seats out, posts the blinds and finds the
    /// first actor.
    ///
    /// A seat with no chips is folded rather than skipped. It is still dealt
    /// two cards — the deal does not depend on the stacks, so a busted seat
    /// cannot change what anyone else is holding — but it has no claim on the
    /// pot.
    public init(dealtHand: DealtHand, stacks startingStacks: [BBAmount]) {
        precondition(
            startingStacks.count == TableRules.seatCount,
            "A hand needs one stack per seat"
        )
        precondition(
            dealtHand.holeCards.count == TableRules.seatCount,
            "A hand needs hole cards for every seat"
        )

        self.dealtHand = dealtHand
        self.startingStacks = startingStacks

        stacks = startingStacks.map(\.centiBB)
        committedThisStreet = [Int](repeating: 0, count: TableRules.seatCount)
        totalCommitted = [Int](repeating: 0, count: TableRules.seatCount)
        folded = stacks.map { $0 == 0 }
        needsToAct = [Bool](repeating: false, count: TableRules.seatCount)
        currentBet = 0
        lastFullRaiseIncrement = TableRules.bigBlind.centiBB
        raiseCountThisStreet = 0
        searchStartSeat = TableRules.seat(atOffset: 3, buttonSeat: dealtHand.buttonSeat)
        street = .preflop
        pot = BBAmount(centiBB: 0)
        actionLog = []
        seatToAct = nil
        result = nil

        // The blinds pass to the first seats after the button that still hold
        // chips, so a hand is never dealt without them. Posting from fixed
        // offsets and skipping a busted seat is how a hand ended up with no
        // blind at all. When fewer than two seats have chips there is nothing
        // to post; the guard below stands everyone down and the session-level
        // check stops dealing.
        let smallBlindSeat = firstSeatWithChips(startingAfter: dealtHand.buttonSeat)
        let bigBlindSeat = smallBlindSeat.flatMap { firstSeatWithChips(startingAfter: $0) }
        if let smallBlindSeat, let bigBlindSeat, smallBlindSeat != bigBlindSeat {
            postBlind(seat: smallBlindSeat, amount: TableRules.smallBlind.centiBB)
            postBlind(seat: bigBlindSeat, amount: TableRules.bigBlind.centiBB)
            // Action opens on the first seat left of the big blind, wherever
            // the blind landed. `nextSeatNeedingToAct` still skips folded and
            // busted seats, so this only has to point at the right neighbour.
            searchStartSeat = TableRules.seat(atOffset: 1, buttonSeat: bigBlindSeat)
        }
        currentBet = committedThisStreet.max() ?? 0

        // The big blind still has the option when nobody raises, so everyone
        // with chips owes a decision — including the seats that already put
        // money in.
        for seat in 0 ..< TableRules.seatCount where !folded[seat] && stacks[seat] > 0 {
            needsToAct[seat] = true
        }
        if activeWithChipsCount < 2 {
            needsToAct = [Bool](repeating: false, count: TableRules.seatCount)
        }

        advanceToNextDecision()
    }

    // MARK: - Reading the state

    public var seats: [SeatSnapshot] {
        (0 ..< TableRules.seatCount).map { seat in
            SeatSnapshot(
                seat: seat,
                stack: BBAmount(centiBB: stacks[seat]),
                committedThisStreet: BBAmount(centiBB: committedThisStreet[seat]),
                totalCommitted: BBAmount(centiBB: totalCommitted[seat]),
                hasFolded: folded[seat]
            )
        }
    }

    /// The community cards the hand has actually reached, never the five that
    /// were dealt up front.
    public var board: [Card] {
        Array(dealtHand.fullBoard.prefix(street.boardCardCount))
    }

    /// How much aggression the acting seat is facing, for a spot signature.
    public var facingAction: FacingAction {
        FacingAction(priorRaiseCount: raiseCountThisStreet)
    }

    /// The decision context for whoever is to act, or `nil` if nobody is.
    public func decisionContext() -> BettingDecisionContext? {
        guard let seat = seatToAct else {
            return nil
        }
        return decisionContext(for: seat)
    }

    /// Every action the machine will accept right now.
    ///
    /// Empty when no seat is to act, which is the only case in which
    /// `apply(_:)` rejects everything: the set and the machine agree there too.
    public func legalActions() -> Set<DecisionAction> {
        decisionContext()?.legalActions() ?? []
    }

    /// The full decision point, including the cards and the spot signature.
    public func currentDecision() -> DecisionPoint? {
        guard let seat = seatToAct else {
            return nil
        }
        let context = decisionContext(for: seat)
        let holeCards = dealtHand.holeCards[seat]
        let offset = TableRules.seatOffsetFromButton(seat: seat, buttonSeat: dealtHand.buttonSeat)
        let handClass = HandClass(holeCards[0], holeCards[1])

        return DecisionPoint(
            handIndex: dealtHand.handIndex,
            seat: seat,
            seatOffsetFromButton: offset,
            street: street,
            holeCards: holeCards,
            board: board,
            pot: pot,
            context: context,
            legalActions: context.legalActions(),
            facing: facingAction,
            handClass: handClass,
            signature: SpotSignature(
                street: street,
                heroSeatOffsetFromButton: offset,
                handClass: handClass,
                facing: facingAction,
                stackBucket: StackBucket(effectiveStack: BBAmount(centiBB: stacks[seat]))
            )
        )
    }

    // MARK: - Advancing the state

    /// Applies an action, or throws and leaves the state exactly as it was.
    ///
    /// Validation happens before any mutation, so a rejected action cannot
    /// leave the hand half-advanced. That is a property worth asserting rather
    /// than assuming — `Session 状态未改变` is in the spec because a machine
    /// that deducts chips and then throws is the failure mode.
    public mutating func apply(_ action: DecisionAction) throws(SessionActionError) {
        guard !isComplete else {
            throw .handAlreadyComplete
        }
        guard let seat = seatToAct else {
            throw .noSeatToAct
        }
        let context = decisionContext(for: seat)
        guard context.legalActions().contains(action) else {
            // The overdraft gets its own error even though it is a special case
            // of "not permitted": it is the one rejection a caller can act on,
            // and the spec names it.
            let attempted = action.committedAmount
            if attempted > context.effectiveStack {
                throw .exceedsEffectiveStack(
                    attempted: attempted,
                    effectiveStack: context.effectiveStack
                )
            }
            throw .notPermitted(action)
        }

        switch action {
        case .fold:
            folded[seat] = true
        case .check:
            break
        case let .call(to: amount):
            commit(seat: seat, amount: amount.centiBB)
        case let .bet(to: amount), let .raise(to: amount), let .allIn(to: amount):
            commit(seat: seat, amount: amount.centiBB)
        }

        needsToAct[seat] = false
        actionLog.append(
            RecordedAction(seat: seat, street: street, action: action, potAfter: pot)
        )

        if committedThisStreet[seat] > currentBet {
            reopenBetting(after: seat)
        }

        searchStartSeat = (seat + 1) % TableRules.seatCount
        advanceToNextDecision()
    }

    /// Records aggression and gives everyone else another turn.
    ///
    /// Simplification, stated because it is a real departure from casino rules:
    /// **any** increase to the current bet reopens the action, including an
    /// all-in for less than a full raise, which at a real table caps the
    /// raising rights of players who had already called. Implementing the real
    /// rule needs a per-seat "may call but not raise" bit, and that bit would
    /// make the spec's own scenario — facing a bet with chips behind, the legal
    /// set contains a raise — false in exactly those spots. The engine follows
    /// the spec; the cost is that an under-raise all-in reopens betting it
    /// should not, which affects realism and neither legality nor chip
    /// conservation.
    private mutating func reopenBetting(after seat: Int) {
        let increment = committedThisStreet[seat] - currentBet
        currentBet = committedThisStreet[seat]
        lastFullRaiseIncrement = max(lastFullRaiseIncrement, increment)
        raiseCountThisStreet += 1

        for other in 0 ..< TableRules.seatCount
        where other != seat && !folded[other] && stacks[other] > 0 {
            needsToAct[other] = true
        }
    }

    /// Finds the next seat to act, moving through streets and settling the hand
    /// when there is nobody left to ask.
    private mutating func advanceToNextDecision() {
        while true {
            if contenders.count <= 1 {
                settle()
                return
            }
            if let next = nextSeatNeedingToAct() {
                seatToAct = next
                return
            }
            guard street != .river else {
                settle()
                return
            }
            beginNextStreet()
        }
    }

    private mutating func beginNextStreet() {
        street = Street(boardCardCount: street.boardCardCount == 0 ? 3 : street.boardCardCount + 1)
            ?? .river
        committedThisStreet = [Int](repeating: 0, count: TableRules.seatCount)
        currentBet = 0
        lastFullRaiseIncrement = TableRules.bigBlind.centiBB
        raiseCountThisStreet = 0
        searchStartSeat = TableRules.seat(atOffset: 1, buttonSeat: dealtHand.buttonSeat)

        // With at most one seat still holding chips there is nothing to bet, so
        // the remaining streets are dealt out and the hand goes to showdown.
        let shouldBet = activeWithChipsCount >= 2
        for seat in 0 ..< TableRules.seatCount {
            needsToAct[seat] = shouldBet && !folded[seat] && stacks[seat] > 0
        }
    }

    private func nextSeatNeedingToAct() -> Int? {
        for step in 0 ..< TableRules.seatCount {
            let seat = (searchStartSeat + step) % TableRules.seatCount
            if needsToAct[seat] && !folded[seat] && stacks[seat] > 0 {
                return seat
            }
        }
        return nil
    }

    private var contenders: [Int] {
        (0 ..< TableRules.seatCount).filter { !folded[$0] }
    }

    private var activeWithChipsCount: Int {
        (0 ..< TableRules.seatCount).count { !folded[$0] && stacks[$0] > 0 }
    }

    /// The first seat after `seat`, in action order, that still holds chips.
    ///
    /// `nil` when no other seat has chips — the caller reads that as "there is
    /// no hand here" rather than posting a blind on a seat that cannot cover
    /// it. The scan starts one seat along, so it never returns `seat` itself
    /// unless it is the only seat with chips, which the caller rejects.
    private func firstSeatWithChips(startingAfter seat: Int) -> Int? {
        for step in 1 ... TableRules.seatCount {
            let candidate = (seat + step) % TableRules.seatCount
            if stacks[candidate] > 0 {
                return candidate
            }
        }
        return nil
    }

    private mutating func postBlind(seat: Int, amount: Int) {
        guard !folded[seat] else {
            return
        }
        commit(seat: seat, amount: min(amount, stacks[seat]))
    }

    private mutating func commit(seat: Int, amount: Int) {
        precondition(amount >= 0, "Cannot commit a negative amount")
        precondition(amount <= stacks[seat], "Cannot commit more than the seat holds")

        stacks[seat] -= amount
        committedThisStreet[seat] += amount
        totalCommitted[seat] += amount
        pot = BBAmount(centiBB: pot.centiBB + amount)
    }

    // MARK: - The decision context

    private func decisionContext(for seat: Int) -> BettingDecisionContext {
        let effectiveStack = stacks[seat]
        let owed = max(0, currentBet - committedThisStreet[seat])

        // The cap that makes `BettingDecisionContext`'s precondition hold, and
        // the reason a call for the whole stack *is* the all-in: a player owed
        // more than they have puts in what they have, and there is nothing left
        // to make a separate all-in out of.
        let amountToCall = min(owed, effectiveStack)

        let minimumRaiseIncrement = owed + lastFullRaiseIncrement
        let minimumRaiseTo = amountToCall > 0 ? BBAmount(centiBB: minimumRaiseIncrement) : nil

        return BettingDecisionContext(
            pot: pot,
            effectiveStack: BBAmount(centiBB: effectiveStack),
            amountToCall: BBAmount(centiBB: amountToCall),
            minimumRaiseTo: minimumRaiseTo,
            configuredBetSizes: sizes(
                seat: seat,
                owed: owed,
                amountToCall: amountToCall,
                minimumRaiseIncrement: minimumRaiseIncrement
            )
        )
    }

    /// The sizes offered at this decision point, as incremental amounts.
    ///
    /// Two pot-proportional sizes plus the smallest legal one. The smallest is
    /// there on purpose: without it a spot whose pot is large relative to the
    /// remaining stack would offer no raise short of all-in, and the spec
    /// requires a raise size whenever there are chips behind.
    ///
    /// `BettingDecisionContext.legalActions()` does the final filtering — it
    /// drops anything at or above the effective stack, because that is the
    /// all-in and offering it twice under two names is how a legal-set
    /// assertion starts passing for the wrong reason.
    private func sizes(
        seat: Int,
        owed: Int,
        amountToCall: Int,
        minimumRaiseIncrement: Int
    ) -> [BBAmount] {
        let bigBlind = TableRules.bigBlind.centiBB
        var candidates: [Int] = []

        if amountToCall == 0 {
            // Unopened: a bet has to be at least one big blind.
            let potNow = pot.centiBB
            candidates = [bigBlind, max(bigBlind, potNow / 2), max(bigBlind, potNow)]
        } else {
            // Facing a bet: raise to half a pot and to a full pot over the
            // current bet, expressed as what this seat adds.
            let potAfterCall = pot.centiBB + amountToCall
            let alreadyIn = committedThisStreet[seat]
            candidates = [
                minimumRaiseIncrement,
                currentBet + potAfterCall / 2 - alreadyIn,
                currentBet + potAfterCall - alreadyIn,
            ]
            candidates = candidates.filter { $0 >= minimumRaiseIncrement }
        }

        // Sorted and de-duplicated so the offered sizes are a function of the
        // state and not of the order the candidates happened to be written in.
        var unique: [Int] = []
        for candidate in candidates.sorted() where candidate > 0 && !unique.contains(candidate) {
            unique.append(candidate)
        }
        return unique.map { BBAmount(centiBB: $0) }
    }

    // MARK: - Settlement

    /// Splits the pot into layers, awards each one and records the result.
    ///
    /// Layer by layer from the smallest remaining contribution upward, so an
    /// all-in for less can only win the part of the pot it covered. Whatever is
    /// left when no contender can still claim it was never matched and goes
    /// back to whoever put it in — which is why a fold to a short all-in
    /// returns the uncalled remainder instead of quietly adding it to the pot.
    private mutating func settle() {
        var remaining = totalCommitted
        var payouts = [Int](repeating: 0, count: TableRules.seatCount)
        var awards: [PotAward] = []
        let contenderSeats = contenders
        let streetReached = street
        let finalBoard = board

        var rankings = [HandRanking?](repeating: nil, count: TableRules.seatCount)
        var showdownSeats: [Int] = []
        if contenderSeats.count > 1 {
            precondition(
                finalBoard.count == 5,
                "A showdown can only happen on the river; reached \(streetReached)"
            )
            for seat in contenderSeats {
                rankings[seat] = HandEvaluator.evaluate(
                    holeCards: dealtHand.holeCards[seat],
                    board: finalBoard
                )
            }
            showdownSeats = contenderSeats
        }

        while true {
            let layerLevel = contenderSeats
                .map { remaining[$0] }
                .filter { $0 > 0 }
                .min()
            guard let layerLevel else {
                break
            }

            var layerAmount = 0
            var layerEligible: [Int] = []
            for seat in 0 ..< TableRules.seatCount where remaining[seat] > 0 {
                let taken = min(layerLevel, remaining[seat])
                remaining[seat] -= taken
                layerAmount += taken
                if !folded[seat] {
                    layerEligible.append(seat)
                }
            }

            let winners: [Int]
            let winningRanking: HandRanking?
            if layerEligible.count == 1 {
                winners = layerEligible
                winningRanking = contenderSeats.count > 1 ? rankings[layerEligible[0]] : nil
            } else {
                // `max()` over an array built by an ascending seat sweep, then a
                // filter — no dictionary, no set, nothing whose order varies.
                let best = layerEligible.compactMap { rankings[$0] }.max()
                winners = layerEligible.filter { rankings[$0] == best }
                winningRanking = best
            }

            distribute(layerAmount, to: winners, into: &payouts)
            awards.append(
                PotAward(
                    amount: BBAmount(centiBB: layerAmount),
                    eligibleSeats: layerEligible,
                    winningSeats: winners,
                    winningRanking: winningRanking
                )
            )
        }

        // Never matched by anyone still in the hand: back to its owner.
        for seat in 0 ..< TableRules.seatCount where remaining[seat] > 0 {
            payouts[seat] += remaining[seat]
            remaining[seat] = 0
        }

        for seat in 0 ..< TableRules.seatCount {
            stacks[seat] += payouts[seat]
        }

        result = HandResult(
            streetReached: streetReached,
            board: finalBoard,
            potTotal: pot,
            contributions: totalCommitted.map { BBAmount(centiBB: $0) },
            payouts: payouts.map { BBAmount(centiBB: $0) },
            stackDeltasCentiBB: (0 ..< TableRules.seatCount).map { payouts[$0] - totalCommitted[$0] },
            showdownSeats: showdownSeats,
            pots: awards,
            rake: TableRules.rake
        )
        pot = BBAmount(centiBB: 0)
        seatToAct = nil
    }

    /// Splits a pot layer, giving odd chips to the earliest seat after the
    /// button.
    ///
    /// The remainder rule matters for conservation, not fairness: integer
    /// division on a three-way chop of 100 leaves one centi-BB, and dropping it
    /// makes the deltas sum to minus one.
    private func distribute(_ amount: Int, to winners: [Int], into payouts: inout [Int]) {
        precondition(!winners.isEmpty, "A pot layer must have a winner")

        let ordered = winners.sorted { lhs, rhs in
            TableRules.seatOffsetFromButton(seat: lhs, buttonSeat: dealtHand.buttonSeat)
                < TableRules.seatOffsetFromButton(seat: rhs, buttonSeat: dealtHand.buttonSeat)
        }
        let share = amount / ordered.count
        let remainder = amount % ordered.count
        for (index, seat) in ordered.enumerated() {
            payouts[seat] += share + (index < remainder ? 1 : 0)
        }
    }

    /// The stacks the next hand starts from.
    public var endingStacks: [BBAmount] {
        stacks.map { BBAmount(centiBB: $0) }
    }
}
