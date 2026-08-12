/// SplitMix64 — the one source of randomness in session dealing.
///
/// Written out rather than taken from the standard library because
/// reproducibility here has to survive a process boundary. `SystemRandom‑
/// NumberGenerator` is seeded from the OS per process, and `Hashable`'s hash
/// values are salted per process, so anything derived from either replays
/// differently on the next launch even when the seed was faithfully recorded.
/// A recorded session that replays differently is worse than one that cannot
/// be replayed at all, because nothing announces the divergence.
///
/// The stdlib's `shuffled(using:)` and `random(in:)` are avoided for a
/// narrower reason: they are deterministic for a given generator, but their
/// algorithms carry no cross-version stability guarantee, so a toolchain
/// upgrade could silently repaint every committed golden fixture. Everything
/// this package derives from a seed goes through the two primitives below.
///
/// The constants are Steele, Lea and Flood's published SplitMix64: the
/// golden-ratio increment and the two finalising multipliers. They are fixed
/// values of the algorithm, not tuning knobs — changing one changes every card
/// this package will ever deal.
public struct SplitMix64: Sendable, Hashable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    /// The next 64 raw bits. Every other member is built on this one.
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A uniform value in `0..<upperBound`.
    ///
    /// Rejection sampled rather than `next() % upperBound`. Plain modulo skews
    /// toward the low end whenever `upperBound` does not divide 2^64, which for
    /// a 52-card shuffle means the deck is very slightly non-uniform in a way
    /// no test would ever notice and no reviewer could ever rule out. The
    /// rejection threshold discards the short tail so the remaining range is an
    /// exact multiple of `upperBound`.
    public mutating func nextBelow(_ upperBound: UInt64) -> UInt64 {
        precondition(upperBound > 0, "Upper bound must be positive")

        // Values at or above this point form a partial final block; dropping
        // them leaves a range that divides evenly.
        let limit = UInt64.max - (UInt64.max % upperBound) - (upperBound - 1)
        var candidate = next()
        while candidate > limit {
            candidate = next()
        }
        return candidate % upperBound
    }

    /// Derives an independent seed from a base seed and a label.
    ///
    /// Used to give each hand its own deck stream and its own action stream.
    /// Without it the streams would be one sequence, and how many random draws
    /// the players happened to need in hand 7 would shift every card in hand 8
    /// — which makes "resume an interrupted session at hand 8 and get the same
    /// cards" depend on replaying the earlier hands identically rather than on
    /// the seed alone.
    ///
    /// The mixing is one SplitMix64 step over the combined inputs, so two
    /// labels that differ in a single bit produce unrelated streams.
    public static func derivedSeed(base: UInt64, label: UInt64) -> UInt64 {
        var mixer = SplitMix64(seed: base &+ (label &* 0x9E37_79B9_7F4A_7C15))
        return mixer.next()
    }
}
