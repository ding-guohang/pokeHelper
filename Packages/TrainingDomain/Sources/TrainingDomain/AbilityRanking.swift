import Foundation
import StrategyContent

public extension AbilitySnapshot {
    /// A total order on how much an ability needs work, weakest first.
    ///
    /// Total, not partial, and that matters: `PlayerProfile.abilities` is a
    /// Dictionary, and Swift seeds its hashing per process, so sorting on a
    /// key that leaves ties unresolved produces a different list on every
    /// launch. The dimension name is the final tie-break for that reason
    /// alone — not because alphabetical order means anything to the user.
    static func isWeakerFirst(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.meanScore != rhs.meanScore {
            return lhs.meanScore < rhs.meanScore
        }
        if lhs.highConfidenceErrorCount != rhs.highConfidenceErrorCount {
            return lhs.highConfidenceErrorCount > rhs.highConfidenceErrorCount
        }
        if lhs.meanLossRateBasisPoints != rhs.meanLossRateBasisPoints {
            return lhs.meanLossRateBasisPoints > rhs.meanLossRateBasisPoints
        }
        return lhs.dimension < rhs.dimension
    }
}

public extension PlayerProfile {
    /// The user's abilities ordered weakest first, for surfaces that show them
    /// where they stand.
    ///
    /// Deliberately *not* `TrainingPlanner`'s priority. Priority ranks catalog
    /// items for a time-boxed plan and folds in staleness, repetition due
    /// dates and the active learning path — scheduling terms that say nothing
    /// about how strong an ability is. Ordering the ability list by that
    /// number would tell a user their sharpest dimension is their weakest
    /// because they happened not to practise it this week.
    ///
    /// The two orderings are separate on purpose. What is *not* acceptable is
    /// a third one: this used to be a private static comparator inside
    /// `ReviewViewModel`, which both put an ability computation in the
    /// presentation layer and left the definition of "weak" free to drift away
    /// from the domain's.
    var abilitiesWeakestFirst: [AbilitySnapshot] {
        abilities.values.sorted(by: AbilitySnapshot.isWeakerFirst)
    }
}

public extension RepetitionScheduler {
    /// The curriculum nodes whose repetition is due, ready to hand to
    /// `TrainingPlanner.makePlan(dueRepetitionNodeIDs:)`.
    ///
    /// Exists so Today and Review derive "what is due" the same way. They did
    /// not: Today built this set and Review passed nothing, so the two screens
    /// could name different first items from the same profile and the same
    /// catalog.
    func dueNodeIDs(
        events: [TrainingEvent],
        pack: StrategyPack?,
        now: Date
    ) -> Set<String> {
        // Repetition is due per curriculum node, which only the content can
        // resolve. Without a pack the plan ranks without that term rather than
        // guessing at one.
        guard let pack else {
            return []
        }
        return Set(dueRepetitions(events: events, pack: pack, now: now).map(\.nodeID))
    }
}
