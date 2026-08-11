import PokerCore

/// Why a hand was put in front of the user again.
///
/// One reason per hand, even when the hand qualifies several ways: a review
/// screen that listed every applicable reason would rank hands by how many
/// labels they collected rather than by how much they mattered.
public enum KeyHandReason: String, Hashable, Sendable, Codable, CaseIterable {
    /// Somebody's whole stack went in.
    case allIn
    /// The hero's stack moved by at least 20BB.
    case bigSwing
    /// One of the session's five largest pots.
    case bigPot
    /// Installed content has something to say about the hero's preflop spot.
    ///
    /// Whether that is true is not a question this package can answer — it does
    /// not know teaching content exists — so it arrives as an input.
    case trainable
}

/// The four facts a hand is scored on.
///
/// A separate type from `SessionHandRecord` because scoring and reading a
/// record are different jobs, and because "what counts as an all-in" is a
/// decision that has to live somewhere nameable. Deriving these from a record
/// is `init(_:isTrainable:)`; everything below it works on the facts alone.
public struct KeyHandFacts: Hashable, Sendable {
    public let handIndex: Int
    public let potTotalCentiBB: Int

    /// Whether any seat put its whole stack in during this hand.
    ///
    /// Not "did an `.allIn` action appear in the log". A player who calls for
    /// their last chips is all in — `cash-decision-domain` states exactly that,
    /// and the state machine emits a `.call(to: effectiveStack)` rather than a
    /// separate all-in item in that spot — and so is one whose blind post was
    /// capped to a short stack. Across 60 seeds of 30 hands, 267 hands put
    /// somebody all in and 236 of them contain an `.allIn` action; scoring on
    /// the action name would silently drop the other 31.
    public let sawAllIn: Bool

    /// Signed, because losing is the ordinary case.
    public let heroStackDeltaCentiBB: Int

    public let isTrainable: Bool

    public init(
        handIndex: Int,
        potTotalCentiBB: Int,
        sawAllIn: Bool,
        heroStackDeltaCentiBB: Int,
        isTrainable: Bool = false
    ) {
        self.handIndex = handIndex
        self.potTotalCentiBB = potTotalCentiBB
        self.sawAllIn = sawAllIn
        self.heroStackDeltaCentiBB = heroStackDeltaCentiBB
        self.isTrainable = isTrainable
    }

    public init(_ hand: SessionHandRecord, isTrainable: Bool) {
        self.init(
            handIndex: hand.handIndex,
            potTotalCentiBB: hand.result.potTotal.centiBB,
            sawAllIn: zip(hand.startingStacks, hand.result.contributions).contains { start, put in
                start.centiBB > 0 && put == start
            },
            heroStackDeltaCentiBB: hand.result.stackDeltasCentiBB[TableRules.heroSeat],
            isTrainable: isTrainable
        )
    }
}

/// A hand worth reviewing, and the one reason shown for it.
public struct KeyHand: Hashable, Sendable {
    public let handIndex: Int
    public let reason: KeyHandReason
    public let score: Int

    public init(handIndex: Int, reason: KeyHandReason, score: Int) {
        self.handIndex = handIndex
        self.reason = reason
        self.score = score
    }
}

/// Picks the hands a finished session opens its review with.
///
/// The score table is design.md decision 4, reproduced here because the numbers
/// are the behaviour:
///
/// | Reason | Qualifies when | Score |
/// |---|---|---|
/// | `.allIn` | a stack went in | 4000 + pot |
/// | `.bigSwing` | the hero's stack moved ≥ 20BB | 3000 + \|delta\| |
/// | `.bigPot` | among the five largest pots | 2000 + pot |
/// | `.trainable` | installed content covers the preflop spot | 1000 |
///
/// A hand's score is the largest of the rows it qualifies for, and that row is
/// the reason shown. The offsets are small next to a pot measured in centi-BB,
/// so they order the *reasons within one hand* and barely order hands against
/// each other — which is deliberate: a 90BB pot matters more than a 4BB one
/// however each of them ended.
///
/// Two consequences worth stating rather than discovering:
///
/// - Between three and five hands come back for any session of three or more,
///   with no floor written into the code. `.bigPot` qualifies the five largest
///   pots, so a session of *n* hands always has at least `min(n, 5)` candidates
///   and the selection is always exactly that many.
/// - `.trainable` can never be the reason shown. It scores a flat 1000 while
///   every one of the five biggest pots scores at least 2000, so a hand whose
///   only distinction is that content covers it is always outranked.
///   `KeyHandSelectionTests` pins this down so that changing the table turns a
///   test red instead of quietly changing what users see.
public enum KeyHandSelection {
    /// Never more than five, so that "review" stays a handful of hands.
    public static let maximumCount = 5

    /// 20BB, per the spec.
    public static let bigSwingThresholdCentiBB = 2_000

    private static let allInBase = 4_000
    private static let bigSwingBase = 3_000
    private static let bigPotBase = 2_000
    private static let trainableBase = 1_000

    public static func facts(
        for hands: [SessionHandRecord],
        trainableHandIndices: Set<Int>
    ) -> [KeyHandFacts] {
        hands.map { KeyHandFacts($0, isTrainable: trainableHandIndices.contains($0.handIndex)) }
    }

    /// The key hands of a session.
    ///
    /// `trainableHandIndices` is an input because this package cannot see
    /// installed content and must not learn to: answering "does content cover
    /// this spot?" inside the engine turns the answer into something other than
    /// a fact about the hand. The app layer, which sees both sides, computes it
    /// from `SpotSignature` equality.
    public static func select(
        from hands: [SessionHandRecord],
        trainableHandIndices: Set<Int>
    ) -> [KeyHand] {
        select(from: facts(for: hands, trainableHandIndices: trainableHandIndices))
    }

    public static func select(from facts: [KeyHandFacts]) -> [KeyHand] {
        let biggestPots = biggestPotHandIndices(in: facts)

        return facts
            .compactMap { fact in
                guard let (reason, score) = bestReason(
                    for: fact,
                    isAmongBiggestPots: biggestPots.contains(fact.handIndex)
                ) else {
                    return nil
                }
                return KeyHand(handIndex: fact.handIndex, reason: reason, score: score)
            }
            // Score descending, then hand index ascending. The second key is
            // the whole of the tie-break: no dictionary iteration, no
            // `hashValue`, nothing that varies between launches.
            .sorted { lhs, rhs in
                lhs.score != rhs.score ? lhs.score > rhs.score : lhs.handIndex < rhs.handIndex
            }
            .prefix(maximumCount)
            .map { $0 }
    }

    /// The five largest pots, ties going to the earlier hand.
    private static func biggestPotHandIndices(in facts: [KeyHandFacts]) -> Set<Int> {
        Set(
            facts
                .sorted { lhs, rhs in
                    lhs.potTotalCentiBB != rhs.potTotalCentiBB
                        ? lhs.potTotalCentiBB > rhs.potTotalCentiBB
                        : lhs.handIndex < rhs.handIndex
                }
                .prefix(maximumCount)
                .map(\.handIndex)
        )
    }

    /// The highest-scoring row this hand qualifies for.
    ///
    /// Rows are considered in table order and replaced only on a strictly
    /// higher score, so two rows that happen to score the same resolve to the
    /// one listed first — a fixed rule rather than whichever comparison ran
    /// last.
    private static func bestReason(
        for fact: KeyHandFacts,
        isAmongBiggestPots: Bool
    ) -> (KeyHandReason, Int)? {
        var best: (KeyHandReason, Int)?

        func consider(_ reason: KeyHandReason, _ score: Int) {
            if best == nil || score > best!.1 {
                best = (reason, score)
            }
        }

        if fact.sawAllIn {
            consider(.allIn, allInBase + fact.potTotalCentiBB)
        }
        if abs(fact.heroStackDeltaCentiBB) >= bigSwingThresholdCentiBB {
            consider(.bigSwing, bigSwingBase + abs(fact.heroStackDeltaCentiBB))
        }
        if isAmongBiggestPots {
            consider(.bigPot, bigPotBase + fact.potTotalCentiBB)
        }
        if fact.isTrainable {
            consider(.trainable, trainableBase)
        }

        return best
    }
}
