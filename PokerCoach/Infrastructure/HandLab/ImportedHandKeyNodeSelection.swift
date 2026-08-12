import HandHistory

/// Why a hero decision is worth reviewing.
enum KeyNodeReason: Equatable {
    /// The hero played a line the covering range table rarely takes.
    case deviation
    /// The hero committed their whole starting stack at this decision.
    case allIn
}

/// One hero decision selected for review, with why it was picked.
struct KeyNode: Equatable {
    let signature: HeroDecisionSignature
    let reason: KeyNodeReason
    /// How far the played line sat from the range, for a deviation; `nil` for an
    /// all-in that is not also a deviation, because an uncovered spot has no
    /// weight to measure against.
    let deviationMagnitude: Int?
}

/// The threshold below which a covered line counts as a deviation, in basis
/// points. Restated locally, and deliberately not imported: this is the value
/// `SessionSimulation.KeyHandSelection.deviationWeightThresholdBasisPoints`
/// ships as (5,000). Importing that type would pull the session key-hand
/// selection logic into the import path; only the number is shared, so only the
/// number is copied, and the two are kept equal by this comment rather than by
/// a dependency.
let importedHandDeviationWeightThresholdBasisPoints = 5_000

/// Selects the review-worthy decisions from a classified imported hand.
///
/// A decision is a deviation when content covers it and the range plays the
/// hero's line under the threshold; it is an all-in when the hero committed
/// their whole stack. A decision that is both is a deviation — the learning
/// signal wins, matching the session rule of one reason per node with deviation
/// highest. Deviations sort ahead of all-ins and, among themselves, by
/// magnitude descending, so review opens on the largest departure. At most five
/// are returned, and the list may be empty.
func selectKeyNodes(
    _ classified: [(HeroDecisionSignature, NodeCoverage)]
) -> [KeyNode] {
    var deviations: [KeyNode] = []
    var allIns: [KeyNode] = []

    for (signature, coverage) in classified {
        if case let .covered(_, weight) = coverage,
           weight < importedHandDeviationWeightThresholdBasisPoints {
            // Covered and under the threshold is a deviation, and takes
            // precedence over the all-in reason when the node is both.
            deviations.append(
                KeyNode(
                    signature: signature,
                    reason: .deviation,
                    deviationMagnitude: deviationMagnitude(weightBasisPoints: weight)
                )
            )
        } else if signature.isAllIn {
            allIns.append(
                KeyNode(signature: signature, reason: .allIn, deviationMagnitude: nil)
            )
        }
    }

    // Deviations ahead of all-ins; among deviations, the largest departure
    // first. All-ins keep the order they occurred in.
    let ordered = deviations.sorted {
        ($0.deviationMagnitude ?? 0) > ($1.deviationMagnitude ?? 0)
    } + allIns
    return Array(ordered.prefix(5))
}
