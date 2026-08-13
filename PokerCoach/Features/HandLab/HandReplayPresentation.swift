import HandHistory
import PokerCore

/// One street of an imported hand, ready to replay exactly as it was observed.
///
/// It carries only what the parser recorded — the street, the community cards
/// visible on that street, and the voluntary actions in the order they occurred
/// — copied verbatim from the matching `ObservedStreet`. No pot is derived: an
/// imported hand's pot would require re-implementing rake, side pots and
/// uncalled-bet returns, and a wrong pot on a review screen is worse than none,
/// so the replay shows the facts it has and never a number it would have to
/// reconstruct.
struct ReplayStreet: Equatable {
    /// The street this row replays.
    let street: Street
    /// The community cards visible on this street — the matching
    /// `ObservedStreet.board`, so the flop shows three cards, the turn four and
    /// the river five, never the final board on every street.
    let board: [Card]
    /// The voluntary actions on this street, every player's, in recorded order.
    let actions: [ObservedAction]
}

/// The streets an imported hand actually reached, each mapped 1:1 from its
/// `ObservedStreet` with the board and actions copied verbatim.
///
/// Only the streets present in `hand.streets` are returned — a hand that ended
/// preflop yields exactly one `ReplayStreet` with an empty board, never four
/// padded with empty streets.
func replayStreets(of hand: ObservedHand) -> [ReplayStreet] {
    hand.streets.map { street in
        ReplayStreet(
            street: street.street,
            board: street.board,
            actions: street.actions
        )
    }
}

/// One hero decision from an imported hand, paired with whether installed
/// content covers it and — when it does — the counterfactual weight the covering
/// range gives the line the hero took, plus the scenario a remediation drill
/// would run.
///
/// This is a comparison, never a grade: it reuses `ImportedHandContentMatcher`
/// so an imported line is judged against the same range tables a played session
/// is, and it reaches no event store — reading a counterfactual writes nothing.
struct HeroNodeCounterfactual: Equatable, Identifiable {
    /// The hero decision, in the order it occurred, so the view can name the
    /// street, the position and the line the hero took.
    let signature: HeroDecisionSignature
    /// Whether content covers this decision, and the weight it gives the line.
    let coverage: NodeCoverage

    /// The covering range's weight for the hero's line, out of 10,000, when
    /// content covers the spot; `nil` when it does not, so the view shows a
    /// frequency exactly where one was measured and "无内容可对照" otherwise.
    var weightBasisPoints: Int? {
        if case let .covered(_, weight) = coverage { return weight }
        return nil
    }

    /// The scenario a remediation drill would run when this node is covered;
    /// `nil` otherwise, so "练这个漏洞" appears only where there is authored
    /// content to practise against.
    var remediationScenarioID: String? {
        if case let .covered(scenarioID, _) = coverage { return scenarioID }
        return nil
    }

    /// A stable identity within a hand: the hero decides at most once per
    /// (street, action-index) pair, so this names one node.
    var id: String { "\(signature.street.rawValue).\(signature.actionIndexInStreet)" }
}

/// Every hero decision in the hand, paired with how installed content weighs the
/// line the hero took, in the order the decisions occurred.
///
/// Each decision is classified through `ImportedHandContentMatcher.classify`,
/// the same value comparison analysis and played sessions use, so a covered node
/// carries the covering range's own table weight (never a fabricated one) and an
/// uncovered node carries nothing. No re-simulation, no invented opponent action.
func heroNodeCounterfactuals(
    of hand: ObservedHand,
    matcher: ImportedHandContentMatcher
) -> [HeroNodeCounterfactual] {
    hand.heroDecisionSignatures().map { signature in
        HeroNodeCounterfactual(
            signature: signature,
            coverage: matcher.classify(signature)
        )
    }
}
