/// A short-stack push/fold decision spot, chip-denominated and content-free.
///
/// It answers two things and nothing more: whether the spot sits at or below a
/// *caller-supplied* big-blind depth (exact integer arithmetic, no floor loss),
/// and what the two moves of the jam-or-fold model are. It endorses no
/// threshold, scores no action, and holds no range — those are strategy truth
/// for reviewed content. See `PushFoldOption` for why jam-or-fold is a disclosed
/// modeling restriction, not legality.
public struct PushFoldContext: Hashable, Sendable {
    public let effectiveChips: Int
    public let level: BlindLevel

    /// Rejects a spot that cannot be reasoned about: a non-positive stack has
    /// nothing to commit, and a non-positive big blind is the division-by-zero
    /// source for depth (`BlindLevel` is a memberwise value with no validation
    /// of its own, so a raw one can carry `bigBlindChips == 0`).
    public init(effectiveChips: Int, level: BlindLevel) throws {
        guard effectiveChips > 0 else { throw PushFoldError.nonPositiveEffectiveStack }
        guard level.bigBlindChips > 0 else { throw PushFoldError.nonPositiveBigBlind }
        self.effectiveChips = effectiveChips
        self.level = level
    }

    /// Floored depth in big blinds, for display. The threshold test below does
    /// not go through this — it compares chips directly to avoid the floor.
    public var effectiveBigBlinds: Int {
        TournamentEngine.effectiveBigBlinds(chips: effectiveChips, atLevel: level)
    }

    /// Whether the effective stack is at or below `thresholdBigBlinds` deep,
    /// computed exactly as `effectiveChips <= thresholdBigBlinds × bigBlindChips`
    /// — inclusive of the boundary, and free of the rounding that comparing the
    /// floored `effectiveBigBlinds` would introduce (850 chips at BB 100 is 8.5
    /// bb: at threshold 8 the exact test is `false`, the floored test would be
    /// `true`).
    public func isAtOrBelow(thresholdBigBlinds: Int) throws -> Bool {
        guard thresholdBigBlinds >= 0 else { throw PushFoldError.negativeThreshold }
        let (thresholdChips, overflow) = thresholdBigBlinds.multipliedReportingOverflow(by: level.bigBlindChips)
        if overflow { throw PushFoldError.thresholdOverflow }
        return effectiveChips <= thresholdChips
    }

    /// The two moves of the jam-or-fold model: fold, or jam the entire effective
    /// stack. Independent of depth — this is the model's move set, never a
    /// recommendation or the legal action set. Callers should gate presentation
    /// on `isAtOrBelow`, and `.fold` assumes the hero faces a wager.
    public func options() -> [PushFoldOption] {
        [.fold, .jam(toChips: effectiveChips)]
    }
}
