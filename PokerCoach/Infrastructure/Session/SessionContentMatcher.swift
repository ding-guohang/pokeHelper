import PokerCore
import SessionSimulation
import StrategyContent

/// One recorded session spot that installed content has something to say about.
struct SessionContentMatch: Equatable {
    let handIndex: Int
    let signature: SpotSignature
    let scenarioID: String

    /// What the covering scenario's range table gives the action the hero took,
    /// in basis points. `nil` when the hero's action has no name in a range
    /// table's vocabulary — a preflop check, which no shipped scenario's spot
    /// even permits.
    let heroActionWeightBasisPoints: Int?
}

/// Answers "does installed content cover this session spot?".
///
/// It lives in the app target because this is the only layer that can see both
/// sides. `SessionSimulation` produces a `SpotSignature` for every decision the
/// hero faced and knows nothing about teaching content; `StrategyContent`
/// produces one for every scenario and knows nothing about sessions. The
/// comparison is a value comparison, made here.
///
/// ## Coverage is keyed on the situation, not on the cards
///
/// The key is `SpotCoverageKey` — street, seat, aggression faced, stack bucket
/// — and deliberately not the whole signature. A scenario's `heroCards` are the
/// example its training screen shows; its `rangeCells` cover the entire range.
/// Requiring the dealt hand to be the example hand made coverage almost
/// unreachable: measured over 6,000 dealt hands against the shipped pack, the
/// full signature covered 15 of them. On the coverage key it covers 2,257 —
/// 37.6% of all hands, 40.0% of the hero's preflop decisions.
///
/// The cards are not discarded, they are asked second: `heroActionWeight` looks
/// the hero's class up in the covering scenario's range table. A class the
/// table omits is a class that range folds every time, which is still an answer
/// to compare against.
///
/// What this type does *not* do is create anything. A match means one thing —
/// the review screen may show the user what they did beside what the content
/// says — and specifically not that a decision was graded. Session hands never
/// produce a `TrainingEvent`, whether or not they match, because grading needs
/// the action and the confidence submitted together and a session asks for
/// neither. This type has no access to an event store, which is the structural
/// half of that guarantee; `SessionEventIsolationTests` is the observed half.
struct SessionContentMatcher {
    private let scenariosByCoverageKey: [SpotCoverageKey: DecisionScenario]

    init(scenarios: [DecisionScenario]) {
        var mapping: [SpotCoverageKey: DecisionScenario] = [:]
        // Sorted, first wins: two scenarios sharing a coverage key must resolve
        // the same way on every launch rather than by array order.
        for scenario in scenarios.sorted(by: { $0.id < $1.id }) {
            guard let key = scenario.spotCoverageKey, mapping[key] == nil else {
                continue
            }
            mapping[key] = scenario
        }
        scenariosByCoverageKey = mapping
    }

    /// The scenario covering this spot, if installed content has one.
    ///
    /// Equality of the coverage key, not a resemblance score. Two spots that
    /// differ in any of its four components — including one stack bucket apart
    /// — are different situations, and a comparison drawn from a different
    /// situation is worse than no comparison.
    func scenarioID(matching signature: SpotSignature) -> String? {
        scenariosByCoverageKey[signature.coverageKey]?.id
    }

    /// The weight the covering scenario's range table gives `action` for the
    /// hand class in `signature`.
    ///
    /// `nil` when nothing covers the spot, and `nil` when the action has no
    /// name in a range table — two different reasons for no comparison, both of
    /// which mean the hand cannot be a deviation.
    func heroActionWeightBasisPoints(
        forSpot signature: SpotSignature,
        action: DecisionAction
    ) -> Int? {
        scenariosByCoverageKey[signature.coverageKey]?
            .rangeWeightBasisPoints(forHandClass: signature.handClass, action: action)
    }

    /// The hero spots in this hand that installed content covers.
    ///
    /// Preflop only in M2A, and enforced here rather than inferred from the
    /// shipped pack. The coverage key carries its street, so against
    /// preflop-only content the filter changes nothing; against content that
    /// does contain a postflop scenario it is the difference between following
    /// the spec and following an accident. `cash-session-run` requires that
    /// only a hand's preflop decision points be marked comparable, because
    /// postflop equivalence needs a hand-class taxonomy this project has not
    /// defined — the app's own development fixture ships two flop scenarios,
    /// which without this line would be matched against dealt flop spots and
    /// shown as curated answers to a question nobody curated.
    func matches(in hand: SessionHandRecord) -> [SessionContentMatch] {
        hand.heroSpots.compactMap { spot in
            guard spot.signature.street == .preflop,
                  let scenarioID = scenarioID(matching: spot.signature)
            else {
                return nil
            }
            return SessionContentMatch(
                handIndex: hand.handIndex,
                signature: spot.signature,
                scenarioID: scenarioID,
                heroActionWeightBasisPoints: heroActionWeightBasisPoints(
                    forSpot: spot.signature,
                    action: spot.action
                )
            )
        }
    }

    func matchedHands(in hands: [SessionHandRecord]) -> [SessionHandRecord] {
        hands.filter { !matches(in: $0).isEmpty }
    }

    /// Hand index to the weight installed content gives what the hero did,
    /// for the key-hand scorer.
    ///
    /// A hand the hero acted on twice in covered spots — opening the cutoff and
    /// then answering a 3-bet there, which the shipped pack covers both halves
    /// of — contributes its *lowest* weight. The reason a hand is worth
    /// reviewing is the biggest departure it contains, not the average of it
    /// with the parts the user played straight.
    ///
    /// Absent means uncovered. Present and 0 means covered and never played
    /// that way, which is the opposite claim, so the two must not be merged.
    func heroActionWeightsBasisPoints(in hands: [SessionHandRecord]) -> [Int: Int] {
        var weights: [Int: Int] = [:]
        for hand in hands {
            for match in matches(in: hand) {
                guard let weight = match.heroActionWeightBasisPoints else {
                    continue
                }
                weights[hand.handIndex] = min(weights[hand.handIndex] ?? weight, weight)
            }
        }
        return weights
    }
}
