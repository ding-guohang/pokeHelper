import Foundation
import PokerCore
import SessionPersistence
import SessionSimulation
import StrategyContent

/// Which way a frequency misses its baseline.
enum SessionFrequencyLeak: String, Equatable, Sendable {
    /// Entering more often than the content's range does.
    case loose
    /// Entering less often.
    case tight
}

/// The hero's realized preflop counts at one (position, facing) pair.
struct HeroPreflopCounts: Equatable, Sendable {
    /// Hands in which the hero got to act at this pair. One per hand, never
    /// two: a hand where the hero answers a 3-bet and then a 5-bet gave them
    /// one chance to continue against a re-raise, not two.
    var opportunities: Int

    /// Of those, the ones the hero did not fold.
    var entries: Int

    static let zero = HeroPreflopCounts(opportunities: 0, entries: 0)
}

/// One line of the frequency report.
struct SessionFrequencyRow: Equatable {
    let key: PositionFacing
    let counts: HeroPreflopCounts

    /// Absent when installed content says nothing about this pair.
    ///
    /// Absent, not zero: the shipped pack has no big blind scenario, and a 0%
    /// baseline there would read as "never continue from the big blind", which
    /// is the opposite of true.
    let baselineBasisPoints: Int?

    var opportunities: Int { counts.opportunities }
    var entries: Int { counts.entries }

    var position: TablePosition? {
        try? TablePosition(
            tableSize: TableRules.seatCount,
            heroSeatOffsetFromButton: key.heroSeatOffsetFromButton
        )
    }

    /// Rounded to nearest, matching `RangeBaseline`. Truncating would bias
    /// every reported frequency downward against a baseline that does not.
    var frequencyBasisPoints: Int {
        guard counts.opportunities > 0 else {
            return 0
        }
        return (counts.entries * 10_000 + counts.opportunities / 2) / counts.opportunities
    }

    /// Whether this pair has been played often enough to say anything.
    var hasEnoughOpportunities: Bool {
        counts.opportunities >= SessionFrequencyReport.minimumOpportunities
    }

    /// The gap from the baseline, or nothing at all.
    ///
    /// Withheld on a thin sample rather than shown with a caveat. At the
    /// threshold the standard error is still around nine percentage points, and
    /// a number on screen is read as a finding no matter what is printed beside
    /// it.
    var deltaBasisPoints: Int? {
        guard let baselineBasisPoints, hasEnoughOpportunities else {
            return nil
        }
        return frequencyBasisPoints - baselineBasisPoints
    }

    var leak: SessionFrequencyLeak? {
        guard let deltaBasisPoints,
              abs(deltaBasisPoints) >= SessionFrequencyReport.leakToleranceBasisPoints
        else {
            return nil
        }
        return deltaBasisPoints > 0 ? .loose : .tight
    }
}

/// The hero's preflop frequencies by position, across every recorded session,
/// beside what installed content's ranges do in the same spot.
///
/// ## Where this lives, and why
///
/// The app target, next to `SessionContentMatcher`, for the same reason: it
/// needs both sides. The counts come from `SessionSimulation` records, which
/// know nothing about teaching content; the baselines come from
/// `StrategyContent` range tables, which know nothing about sessions. This is
/// the only layer that sees both, and `scripts/check-package-layering.sh` keeps
/// it that way.
///
/// It is not in `Features/Session/` because it holds no view state and makes no
/// presentation decisions — it is the bridge computation a view reads, the same
/// shape as the matcher beside it.
///
/// ## What it will not do
///
/// Two rules from the proposal that are structural here rather than
/// conventional:
///
/// - Every number is counted from the hands on disk. There is no running
///   counter to drift from them, so deleting a session lowers the counts by
///   exactly what that session contributed and nothing has to be told about it.
/// - The baseline is derived from the installed pack's range table each time,
///   never stored. A pack whose cells change reports a different baseline
///   without anyone editing a constant, and a pack that covers nothing reports
///   no baseline rather than zero.
struct SessionFrequencyReport: Equatable {
    /// Below this many opportunities the report counts but does not conclude.
    ///
    /// Six-handed, a position comes around every six hands, so a 60-hand
    /// session offers one position about ten chances; at p ≈ 0.46 that is a
    /// standard error near 16 percentage points. Thirty is not a safe sample —
    /// it is the point below which the number is certainly noise.
    static let minimumOpportunities = 30

    /// How far from the baseline counts as a leak: five percentage points.
    ///
    /// **This constant is not in the spec.** The proposal fixes the sample
    /// threshold and the verdict wording but never says how big a gap makes a
    /// leak, and the only scenario constraining it is a 23.67-point miss, which
    /// any tolerance from zero up would flag. Zero was rejected because it puts
    /// every sufficiently sampled position on the leak list, including one that
    /// missed by a tenth of a point, and a leak list that always lists
    /// everything is not a list.
    static let leakToleranceBasisPoints = 500

    /// Ordered by seat and then by how much aggression is being answered.
    /// Sorted rather than collected, because a dictionary's iteration order is
    /// not fixed between launches.
    let rows: [SessionFrequencyRow]

    /// Rows far enough from their baseline to name, in report order.
    ///
    /// A position with no baseline can never appear here, and neither can one
    /// below the sample threshold — there is nothing to be off by in the first
    /// case and no reason to believe the gap in the second.
    var leaks: [SessionFrequencyRow] {
        rows.filter { $0.leak != nil }
    }

    static func make(
        hands: [SessionHandRecord],
        installedContent: StrategyPack?
    ) -> SessionFrequencyReport {
        make(counts: counts(in: hands), installedContent: installedContent)
    }

    static func make(
        counts: [PositionFacing: HeroPreflopCounts],
        installedContent: StrategyPack?
    ) -> SessionFrequencyReport {
        let baselines = installedContent?.entryBaselines ?? [:]

        let rows = counts
            .map { key, counts in
                SessionFrequencyRow(
                    key: key,
                    counts: counts,
                    baselineBasisPoints: baselines[key]
                )
            }
            .sorted { lhs, rhs in
                lhs.key.heroSeatOffsetFromButton != rhs.key.heroSeatOffsetFromButton
                    ? lhs.key.heroSeatOffsetFromButton < rhs.key.heroSeatOffsetFromButton
                    : facingOrder(lhs.key.facing) < facingOrder(rhs.key.facing)
            }

        return SessionFrequencyReport(rows: rows)
    }

    /// Every recorded session, oldest hand of each to newest.
    ///
    /// Reads the hands back rather than accumulating as they are played. That
    /// is the whole of "frequencies come from the recorded hands": a counter
    /// kept alongside the store would survive a crash the hands did not, and a
    /// deleted session would go on being counted.
    static func make(
        store: FileSessionRecordStore,
        installedContent: StrategyPack?
    ) async throws -> SessionFrequencyReport {
        var hands: [SessionHandRecord] = []
        for sessionID in try await store.sessionIDs() {
            hands.append(contentsOf: try await store.hands(for: sessionID))
        }
        return make(hands: hands, installedContent: installedContent)
    }

    /// The hero's preflop opportunities and entries, keyed by spot.
    ///
    /// A hand contributes at most one opportunity per key. The hero's spot
    /// signatures and their actions are parallel — `SessionRunner` appends a
    /// decision point and then applies exactly one action to it, and a rejected
    /// action is a trap rather than a gap — so zipping them pairs each spot
    /// with what the hero did in it.
    ///
    /// A hand where the hero never acted contributes nothing, and needs no
    /// special case: it has no signatures. That is the walk — everyone folds to
    /// the big blind — and counting it as a missed chance to enter would make
    /// the hero look tighter than they played.
    static func counts(in hands: [SessionHandRecord]) -> [PositionFacing: HeroPreflopCounts] {
        var counts: [PositionFacing: HeroPreflopCounts] = [:]

        for hand in hands {
            var alreadyCountedThisHand: Set<PositionFacing> = []

            for (signature, action) in zip(hand.heroSpotSignatures, hand.heroActions)
            where signature.street == .preflop {
                let key = PositionFacing(
                    heroSeatOffsetFromButton: signature.heroSeatOffsetFromButton,
                    facing: signature.facing
                )
                guard alreadyCountedThisHand.insert(key).inserted else {
                    continue
                }

                counts[key, default: .zero].opportunities += 1
                // Continuing, not raising: the baseline is the share of
                // combinations the range does anything but fold with, so the
                // realized number it is compared against has to be the same
                // question asked of the hero.
                if action != .fold {
                    counts[key, default: .zero].entries += 1
                }
            }
        }

        return counts
    }

    private static func facingOrder(_ facing: FacingAction) -> Int {
        FacingAction.allCases.firstIndex(of: facing) ?? FacingAction.allCases.count
    }
}
