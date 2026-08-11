import PokerCore
import SessionSimulation
import StrategyContent

/// One recorded session spot that installed content has something to say about.
struct SessionContentMatch: Equatable {
    let handIndex: Int
    let signature: SpotSignature
    let scenarioID: String
}

/// Answers "does installed content cover this session spot?".
///
/// It lives in the app target because this is the only layer that can see both
/// sides. `SessionSimulation` produces a `SpotSignature` for every decision the
/// hero faced and knows nothing about teaching content; `StrategyContent`
/// produces one for every scenario and knows nothing about sessions. The
/// comparison is a value comparison, made here.
///
/// What it does *not* do is create anything. A match means one thing — the
/// review screen may show the user what they did beside what the content says —
/// and specifically not that a decision was graded. Session hands never produce
/// a `TrainingEvent`, whether or not they match, because grading needs the
/// action and the confidence submitted together and a session asks for neither.
/// This type has no access to an event store, which is the structural half of
/// that guarantee; `SessionEventIsolationTests` is the observed half.
struct SessionContentMatcher {
    private let scenarioIDsBySignature: [SpotSignature: String]

    init(scenarios: [DecisionScenario]) {
        var mapping: [SpotSignature: String] = [:]
        // Sorted, first wins: two scenarios sharing a signature must resolve
        // the same way on every launch rather than by array order.
        for scenario in scenarios.sorted(by: { $0.id < $1.id }) {
            guard let signature = scenario.spotSignature,
                  mapping[signature] == nil
            else {
                continue
            }
            mapping[signature] = scenario.id
        }
        scenarioIDsBySignature = mapping
    }

    /// The scenario covering this spot, if installed content has one.
    ///
    /// Equality of the whole signature, not a resemblance score. Two spots that
    /// differ in any component — including one stack bucket apart — are
    /// different spots, and showing a user a comparison drawn from a different
    /// spot is worse than showing none.
    func scenarioID(matching signature: SpotSignature) -> String? {
        scenarioIDsBySignature[signature]
    }

    /// The hero spots in this hand that installed content covers.
    ///
    /// Preflop only in M2A — not by filtering here, but because the signature
    /// carries its street and every shipped scenario's is `preflop`. A postflop
    /// hero spot cannot equal a preflop scenario's signature, so a postflop
    /// decision never matches and never gets marked.
    func matches(in hand: SessionHandRecord) -> [SessionContentMatch] {
        hand.heroSpotSignatures.compactMap { signature in
            guard let scenarioID = scenarioID(matching: signature) else {
                return nil
            }
            return SessionContentMatch(
                handIndex: hand.handIndex,
                signature: signature,
                scenarioID: scenarioID
            )
        }
    }

    func matchedHands(in hands: [SessionHandRecord]) -> [SessionHandRecord] {
        hands.filter { !matches(in: $0).isEmpty }
    }
}
