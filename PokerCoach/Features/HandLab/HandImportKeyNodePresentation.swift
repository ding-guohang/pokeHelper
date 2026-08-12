import HandHistory
import PokerCore

/// A display-ready view of the key nodes an imported hand's analysis produced,
/// computed by pure mapping.
///
/// Nothing here is business calculation: the street, position and the hero's own
/// action are read straight off each `KeyNode`'s signature, and the only numbers
/// shown come from the coverage the selection already decided. A covered
/// deviation carries a magnitude, and the covering range's weight is the
/// magnitude's complement — 10,000 basis points minus the departure — so the
/// screen restates what analysis found rather than re-deriving it. An all-in
/// with no magnitude has no range weight to compare against, so it says so
/// plainly instead of inventing a frequency. No EV, no score, no grade: an
/// imported hand is not a training answer.
struct HandImportKeyNodePresentation: Equatable {
    struct Row: Equatable, Identifiable {
        /// Position in the key-node list, so accessibility identifiers name one
        /// row rather than the whole list.
        let index: Int
        /// The street the decision was made on, e.g. "翻前".
        let street: String
        /// The hero's table position, e.g. "BTN".
        let position: String
        /// The line the hero actually took, e.g. "加注至 3 BB".
        let heroAction: String
        /// Why the node was surfaced: "偏离" or "全下".
        let reasonLabel: String
        /// Whether this is a deviation, for styling only.
        let isDeviation: Bool
        /// How the played line compares to installed content.
        let comparison: Comparison
        /// The scenario a remediation drill would run, when this node is a
        /// covered deviation; `nil` otherwise, so the view offers "练这个漏洞"
        /// exactly where there is a spot to practise.
        let remediationScenarioID: String?

        var id: Int { index }
    }

    /// What content had to say about the line, if anything.
    enum Comparison: Equatable {
        /// Content covered the spot. `contentFrequency` is how often the covering
        /// range plays the hero's line (0% means "never"); `deviation` is how far
        /// the line sat from the range.
        case covered(contentFrequency: String, deviation: String)
        /// No installed content covered the spot, so there is nothing to compare.
        case uncovered
    }

    let rows: [Row]

    init(keyNodes: [KeyNode], tableSize: Int) {
        rows = keyNodes.enumerated().map { index, node in
            Row(
                index: index,
                street: HandImportPreview.streetName(node.signature.street),
                position: HandImportPreview.position(
                    tableSize: tableSize,
                    offset: node.signature.signature.heroSeatOffsetFromButton
                ),
                heroAction: Self.action(node.signature.action),
                reasonLabel: Self.reasonLabel(node.reason),
                isDeviation: node.reason == .deviation,
                comparison: Self.comparison(node),
                remediationScenarioID: remediationScenarioID(for: node)
            )
        }
    }

    // MARK: - Mapping

    /// The comparison a node carries.
    ///
    /// A deviation is always covered — the selection only tags it when content
    /// weighed the line under the threshold — and its magnitude fixes the range's
    /// weight as the complement out of 10,000. Anything else (an all-in with no
    /// magnitude) has no weight to show, so it is reported as uncovered rather
    /// than dressed up with a number that was never measured.
    private static func comparison(_ node: KeyNode) -> Comparison {
        guard node.reason == .deviation, let magnitude = node.deviationMagnitude else {
            return .uncovered
        }
        let weight = 10_000 - magnitude
        return .covered(
            contentFrequency: percent(basisPoints: weight),
            deviation: percent(basisPoints: magnitude)
        )
    }

    private static func reasonLabel(_ reason: KeyNodeReason) -> String {
        switch reason {
        case .deviation: "偏离"
        case .allIn: "全下"
        }
    }

    /// The hero's own action as "<verb> [<amount>]", the amount rendered as big
    /// blinds by the same formatter the preview uses so the two never disagree.
    private static func action(_ action: ObservedAction) -> String {
        let verb: String
        switch action.kind {
        case .fold: verb = "弃牌"
        case .check: verb = "过牌"
        case .call: verb = "跟注"
        case .bet: verb = "下注"
        case .raiseTo: verb = "加注至"
        }
        if let amount = action.amountCentiBB {
            return "\(verb) \(HandImportPreview.bb(amount))"
        }
        return verb
    }

    /// Basis points as a percentage: 0 -> "0%", 6234 -> "62.34%", 10000 ->
    /// "100%". Trailing zeros in the fraction are trimmed so a whole percent
    /// reads as one. A frequency, never a probability the matcher invented — the
    /// value comes from the covering range table.
    static func percent(basisPoints: Int) -> String {
        let whole = basisPoints / 100
        let fraction = basisPoints % 100
        if fraction == 0 {
            return "\(whole)%"
        }
        let twoPlaces = String(format: "%02d", fraction)
        let trimmed = twoPlaces.hasSuffix("0") ? String(twoPlaces.dropLast()) : twoPlaces
        return "\(whole).\(trimmed)%"
    }
}
