import PokerCore

/// A total order over decision actions.
///
/// Exists so that nothing in this package ever has to iterate a `Set` to make a
/// choice. `legalActions()` hands back a `Set`, `Set` iteration order depends on
/// per-process hash seeding, and an opponent that picks "the first legal
/// action" out of one plays a different hand on every launch from the same
/// recorded seed. Sorting first makes the choice a function of the actions
/// themselves.
extension DecisionAction {
    /// Rank by kind first, then by amount. The kind order is the order a player
    /// reads them in, which is also the order they appear in the spec.
    var canonicalSortKey: (Int, Int) {
        switch self {
        case .fold: (0, 0)
        case .check: (1, 0)
        case let .call(to: amount): (2, amount.centiBB)
        case let .bet(to: amount): (3, amount.centiBB)
        case let .raise(to: amount): (4, amount.centiBB)
        case let .allIn(to: amount): (5, amount.centiBB)
        }
    }

    /// The chips this action asks the acting player to put in right now.
    ///
    /// Zero for fold and check. Every amount in this package is incremental —
    /// what the player adds from their remaining stack — which is the same
    /// convention `BettingDecisionContext.amountToCall` uses, and the reason
    /// the cap against the effective stack can be a single comparison.
    var committedAmount: BBAmount {
        switch self {
        case .fold, .check: BBAmount(centiBB: 0)
        case let .call(to: amount), let .bet(to: amount),
             let .raise(to: amount), let .allIn(to: amount): amount
        }
    }
}

extension Set<DecisionAction> {
    /// The set in canonical order.
    var canonicallyOrdered: [DecisionAction] {
        sorted { lhs, rhs in
            let (leftKind, leftAmount) = lhs.canonicalSortKey
            let (rightKind, rightAmount) = rhs.canonicalSortKey
            return leftKind != rightKind ? leftKind < rightKind : leftAmount < rightAmount
        }
    }
}
