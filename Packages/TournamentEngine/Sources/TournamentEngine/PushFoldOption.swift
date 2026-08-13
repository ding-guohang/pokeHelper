/// One move in the jam-or-fold model of a short-stack decision.
///
/// This is a disclosed *modeling* restriction a caller opts into, not the legal
/// action set and not a recommendation: real poker below any depth still allows
/// limping and min-raising (the cash `BettingDecisionContext.legalActions()`
/// returns that wider set). Which holdings jam is strategy truth and lives in
/// reviewed content, never here.
///
/// Chip-denominated (`Int`), not `BBAmount`: tournament chips do not divide
/// evenly into big blinds, so forcing them through centi-BB would round and
/// break the exact-data rule.
public enum PushFoldOption: Hashable, Sendable {
    case fold
    /// Commit the entire effective stack — `toChips` is that stack in chips.
    case jam(toChips: Int)
}
