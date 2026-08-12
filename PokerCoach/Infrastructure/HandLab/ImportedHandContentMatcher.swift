import HandHistory
import PokerCore
import StrategyContent

/// Whether installed content covers one hero decision from an imported hand,
/// and — when it does — the weight the covering range table gives the line the
/// hero actually took.
enum NodeCoverage: Equatable {
    /// Content covers the situation. `weightBasisPoints` is what the covering
    /// scenario's range table gives the hero's hand class for the action taken,
    /// out of 10,000; 0 means "the range never plays it that way", which is a
    /// comparison, not a gap.
    case covered(scenarioID: String, weightBasisPoints: Int)
    /// No installed scenario shares this decision's coverage key, or the hero's
    /// action (a check) has no name in a range table's vocabulary. Either way
    /// there is nothing to compare against.
    case uncovered
}

/// Answers "does installed content cover this imported hero decision?", the
/// import-side twin of `SessionContentMatcher`.
///
/// It lives in the app target for the same reason that one does: this is the
/// only layer that sees both sides. `HandHistory` turns an imported hand into a
/// `HeroDecisionSignature` for every decision the hero made and knows nothing
/// about teaching content; `StrategyContent` describes scenarios and knows
/// nothing about imported hands. The comparison is a value comparison, made
/// here, on the coverage key — street, seat, aggression faced, stack bucket —
/// exactly as sessions are matched, so an imported hand and a played session
/// are judged against content the same way.
///
/// The cards are asked second, never first: once a scenario covers the
/// situation, the hero's hand class is looked up in that scenario's range table
/// through the same `RangeBaseline` path `SessionContentMatcher` uses, so the
/// two cannot drift. What this type does *not* do is grade anything or reach an
/// event store — an imported hand is not a training answer.
struct ImportedHandContentMatcher {
    private let scenariosByCoverageKey: [SpotCoverageKey: DecisionScenario]

    init(scenarios: [DecisionScenario]) {
        var mapping: [SpotCoverageKey: DecisionScenario] = [:]
        // Sorted, first wins: two scenarios sharing a coverage key must resolve
        // the same way on every launch rather than by array order, matching
        // `SessionContentMatcher`.
        for scenario in scenarios.sorted(by: { $0.id < $1.id }) {
            guard let key = scenario.spotCoverageKey, mapping[key] == nil else {
                continue
            }
            mapping[key] = scenario
        }
        scenariosByCoverageKey = mapping
    }

    /// Whether content covers this decision, and the weight it gives the line
    /// the hero took.
    ///
    /// Uncovered when no scenario shares the coverage key, and uncovered again
    /// when the scenario cannot weigh the action — a check has no name in a
    /// range table's vocabulary, so there is no comparison to draw even though
    /// the situation is covered.
    func classify(_ signature: HeroDecisionSignature) -> NodeCoverage {
        guard let scenario = scenariosByCoverageKey[signature.signature.coverageKey] else {
            return .uncovered
        }
        guard let weight = scenario.rangeWeightBasisPoints(
            forHandClass: signature.signature.handClass,
            action: Self.decisionAction(from: signature.action)
        ) else {
            return .uncovered
        }
        return .covered(scenarioID: scenario.id, weightBasisPoints: weight)
    }

    /// The `PokerCore` action a range table can weigh, from an observed one.
    /// The `amountCentiBB` an observed action carries is the "to" amount, which
    /// is exactly what the sized `DecisionAction` cases hold; the range lookup
    /// only cares about the verb, not the size.
    private static func decisionAction(from action: ObservedAction) -> DecisionAction {
        let amount = BBAmount(centiBB: action.amountCentiBB ?? 0)
        switch action.kind {
        case .fold: return .fold
        case .check: return .check
        case .call: return .call(to: amount)
        case .bet: return .bet(to: amount)
        case .raiseTo: return .raise(to: amount)
        }
    }
}
