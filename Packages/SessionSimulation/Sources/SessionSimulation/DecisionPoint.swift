import PokerCore

/// Everything a player — or a policy standing in for one — can see when it is
/// their turn.
///
/// Carries the legal set rather than expecting the caller to ask for it
/// separately, so that "choose an action" and "check it is legal" cannot end up
/// looking at two different states.
public struct DecisionPoint: Hashable, Sendable {
    public let handIndex: Int
    public let seat: Int
    public let seatOffsetFromButton: Int
    public let street: Street
    public let holeCards: [Card]

    /// The community cards that have actually been dealt, never the undealt
    /// remainder — a policy that could see the turn card before the turn would
    /// make the whole simulation worthless.
    public let board: [Card]
    public let pot: BBAmount
    public let context: BettingDecisionContext
    public let legalActions: Set<DecisionAction>
    public let facing: FacingAction
    public let handClass: HandClass

    /// The spot's identity, for the app layer to compare against installed
    /// content.
    ///
    /// Produced for every street even though M2A only matches preflop. The
    /// signature carries its own `street`, so filtering is the comparing side's
    /// job; withholding it here would just mean the engine had quietly taken a
    /// decision about teaching content, which is the thing this package is not
    /// allowed to know about.
    public let signature: SpotSignature

    /// The legal set in a fixed order.
    ///
    /// Anything that picks an action must go through this. `Set` iteration
    /// order depends on per-process hash seeding, so a policy that iterated the
    /// set directly would play a different hand on every launch from the same
    /// recorded seed — and would pass any determinism test written inside a
    /// single process.
    public var orderedLegalActions: [DecisionAction] {
        legalActions.canonicallyOrdered
    }
}
