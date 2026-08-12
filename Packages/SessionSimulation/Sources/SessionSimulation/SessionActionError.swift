import PokerCore

/// Why the betting state machine refused an action.
///
/// Typed and enumerable, per the project's error rules: a caller has to be able
/// to tell "you cannot afford that" from "that is not a move here", because the
/// two produce different messages and different retries.
public enum SessionActionError: Error, Equatable, Sendable {
    /// The hand has already been settled.
    case handAlreadyComplete

    /// No seat is waiting on a decision — the caller is out of step with the
    /// machine, not proposing an illegal move.
    case noSeatToAct

    /// The action asked the acting player to put in more than they have.
    ///
    /// Carries both figures because the interesting bug is almost always an
    /// off-by-one in the cap rather than the raw fact of the overdraft.
    case exceedsEffectiveStack(attempted: BBAmount, effectiveStack: BBAmount)

    /// The action is inside the player's means but is not one of the moves the
    /// current state permits — a check facing a bet, a raise below the minimum,
    /// a bet size that was never offered.
    case notPermitted(DecisionAction)
}
