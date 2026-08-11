import Foundation
import PokerCore

public extension DecisionScenario {
    /// The spot this scenario teaches, as a comparable value.
    ///
    /// The same type a session hand produces, so the app layer can ask whether
    /// a hand it just dealt corresponds to curated content without either side
    /// knowing the other exists. Every component is a fact about the hand;
    /// `facing` is the one the content has to *declare* rather than compute,
    /// because the number of prior raises is not recoverable from a betting
    /// context — chips a caller put in and chips a raiser put in are the same
    /// chips inside `pot`.
    ///
    /// Returns nil only when the board is a size no street has (1, 2, or more
    /// than 5), which a validated pack cannot contain.
    var spotSignature: SpotSignature? {
        guard let street = Street(boardCardCount: board.count),
              heroCards.count == 2
        else {
            return nil
        }

        return SpotSignature(
            street: street,
            heroSeatOffsetFromButton: heroSeatOffsetFromButton,
            handClass: HandClass(heroCards[0], heroCards[1]),
            facing: facing,
            stackBucket: StackBucket(effectiveStack: decision.effectiveStack)
        )
    }

    /// The situation this scenario teaches, cards left out.
    ///
    /// Never nil for a validated pack, for the same reason `spotSignature` is
    /// not: only an impossible board size can fail.
    var spotCoverageKey: SpotCoverageKey? {
        spotSignature?.coverageKey
    }

    /// What this scenario's range table gives `action` for `handClass`, in
    /// basis points out of 10,000.
    ///
    /// Two cases that look alike and are not:
    ///
    /// - The table has no row for the class. That is not missing data — a range
    ///   chart lists what it plays, and a class it omits is one it folds every
    ///   time. So the answer is 10,000 for a fold and 0 for anything else, and
    ///   `nil` is not returned.
    /// - The action has no name in this table's vocabulary. Range tables in the
    ///   shipped pack are written in `fold` / `call` / `raise`; a check has no
    ///   entry anywhere and no defensible translation — mapping it onto `fold`
    ///   would call a free look at a flop a surrender. That returns `nil`,
    ///   which callers read as "no comparison to draw" rather than as zero.
    func rangeWeightBasisPoints(
        forHandClass handClass: HandClass,
        action: DecisionAction
    ) -> Int? {
        guard let key = RangeBaseline.actionKey(for: action) else {
            return nil
        }
        guard let cell = rangeCells.first(where: { $0.handClass == handClass.description }) else {
            return key == RangeBaseline.foldKey ? RangeBaseline.fullWeightBasisPoints : 0
        }
        return cell.actionWeightsBasisPoints[key] ?? 0
    }
}

/// How often a range enters the pot, in basis points of all 1,326 combinations.
///
/// This is the baseline a session frequency report compares the user against.
/// It is derived from the range table rather than stored as a number, so it
/// cannot drift from the content it claims to describe: change a cell and the
/// baseline changes with it.
public enum RangeBaseline {
    /// Combinations of a full deck's two-card holdings. Every baseline is a
    /// share of this, not of the hands the table happens to list — a table
    /// that omits the trash it always folds must not thereby report a higher
    /// entry rate.
    public static let totalCombinations = 1_326

    /// A cell's weights sum to this.
    public static let fullWeightBasisPoints = 10_000

    /// The three names range tables in this project are written in.
    ///
    /// Verified against the shipped pack: every cell in every scenario uses
    /// only these keys, and every cell sums to 10,000.
    public static let foldKey = "fold"
    public static let callKey = "call"
    public static let raiseKey = "raise"

    /// The range-table name for an action a player took, or `nil` if the
    /// vocabulary has none.
    ///
    /// A bet, a raise and an all-in are all "raise": a range chart names the
    /// decision to put in more than is owed, not the sizing, and the sizing
    /// already lives in `DecisionScenario.options`.
    public static func actionKey(for action: DecisionAction) -> String? {
        switch action {
        case .fold: foldKey
        case .call: callKey
        case .bet, .raise, .allIn: raiseKey
        case .check: nil
        }
    }

    /// The share of all combinations this cell set does something other than
    /// fold with, in basis points.
    ///
    /// Weighted by combination count, so a suited cell (4 combinations) cannot
    /// count as much as an offsuit one (12). Multiplied before dividing, so the
    /// rounding happens once at the end rather than per cell, and rounded to
    /// nearest rather than truncated: truncation is a systematic downward bias,
    /// and every baseline here would read one basis point low.
    public static func entryBasisPoints(of cells: [RangeCell]) -> Int {
        var weightedBasisPoints = 0

        for cell in cells {
            guard let handClass = HandClass(notation: cell.handClass) else {
                continue
            }
            let nonFold = cell.actionWeightsBasisPoints
                .filter { !$0.key.hasPrefix("fold") }
                .values
                .reduce(0, +)
            weightedBasisPoints += handClass.combinationCount * nonFold
        }

        return (weightedBasisPoints + totalCombinations / 2) / totalCombinations
    }
}

public extension StrategyPack {
    /// Entry-rate baselines keyed by the spot they describe.
    ///
    /// Keyed by (position, facing) and not by position alone. The shipped pack
    /// has two scenarios at the cutoff — open-raising at 24.86% and answering a
    /// 3-bet at 9.05% — and collapsing them onto one key produces a number that
    /// describes neither. A report that told a user their cutoff frequency was
    /// off against that number would be comparing them to nothing.
    ///
    /// A position the content says nothing about is absent rather than zero.
    /// The big blind has no scenario in the shipped pack, and reporting a 0%
    /// baseline for it would read as "you should never continue from the big
    /// blind", which is the opposite of true.
    var entryBaselines: [PositionFacing: Int] {
        var baselines: [PositionFacing: Int] = [:]

        // Sorted by ID and first-wins, so two scenarios sharing a key resolve
        // the same way on every run. `scenarios` is an array, but the pack it
        // came from need not have been built in a fixed order, and a baseline
        // that depends on which duplicate happened to be last is a number that
        // can change without the content changing.
        for scenario in scenarios.sorted(by: { $0.id < $1.id })
        where scenario.board.isEmpty {
            let key = PositionFacing(
                heroSeatOffsetFromButton: scenario.heroSeatOffsetFromButton,
                facing: scenario.facing
            )
            guard baselines[key] == nil else {
                continue
            }
            baselines[key] = RangeBaseline.entryBasisPoints(of: scenario.rangeCells)
        }

        return baselines
    }
}

/// A seat and the aggression it is answering — the key a frequency baseline is
/// filed under.
public struct PositionFacing: Hashable, Sendable {
    public let heroSeatOffsetFromButton: Int
    public let facing: FacingAction

    public init(heroSeatOffsetFromButton: Int, facing: FacingAction) {
        self.heroSeatOffsetFromButton = heroSeatOffsetFromButton
        self.facing = facing
    }
}
