import PokerCore

/// Which of the four disclosed profiles a seat is playing.
///
/// A stable string rather than an index, because a session record stores it and
/// a record has to survive the list being reordered.
public enum OpponentProfileID: String, Hashable, Sendable, Codable, CaseIterable {
    case rock
    case tag
    case station
    case maniac
}

/// One opponent profile: a name and three numbers that are shown to the user.
///
/// The three numbers are **definitions, not measurements**. Nothing counts what
/// the opponent actually did and reports it back; the behaviour table reads
/// these fields and acts on them, so the number on the screen is the number the
/// opponent is playing. Each one has a stated meaning, and each meaning is
/// pinned by a test in `OpponentProfileTableTests`:
///
/// | Field | Means |
/// |---|---|
/// | `entryRateBasisPoints` | Share of the 1,326 starting combinations it puts money in with preflop when nobody has raised, averaged over the six seats |
/// | `aggressionBasisPoints` | Share of the times it bets or raises rather than checking or calling, holding a medium-strength hand |
/// | `callingTendencyBasisPoints` | Share of the times it continues rather than folds when facing a bet, holding a medium-strength hand |
///
/// "Medium strength" is the midpoint of the 0–100 read `OpponentActionPolicy`
/// takes of a made hand — around two pair. Both curves pass through the stated
/// figure there and move with the holding on either side, so a profile is more
/// aggressive with a better hand and less with a worse one while the published
/// number stays the value in the middle.
///
/// Basis points, matching the project's rule that frequencies are integers.
public struct OpponentProfile: Hashable, Sendable {
    public let id: OpponentProfileID

    /// The name shown to the user.
    public let name: String

    public let entryRateBasisPoints: Int
    public let aggressionBasisPoints: Int
    public let callingTendencyBasisPoints: Int

    /// One line describing the shape, for the screen that lists the profiles.
    public let tendencySummary: String

    public init(
        id: OpponentProfileID,
        name: String,
        entryRateBasisPoints: Int,
        aggressionBasisPoints: Int,
        callingTendencyBasisPoints: Int,
        tendencySummary: String
    ) {
        precondition(
            (0 ... 10_000).contains(entryRateBasisPoints),
            "Entry rate must be a frequency in basis points"
        )
        precondition(
            (0 ... 10_000).contains(aggressionBasisPoints),
            "Aggression must be a frequency in basis points"
        )
        precondition(
            (0 ... 10_000).contains(callingTendencyBasisPoints),
            "Calling tendency must be a frequency in basis points"
        )

        self.id = id
        self.name = name
        self.entryRateBasisPoints = entryRateBasisPoints
        self.aggressionBasisPoints = aggressionBasisPoints
        self.callingTendencyBasisPoints = callingTendencyBasisPoints
        self.tendencySummary = tendencySummary
    }
}

/// The four disclosed opponent profiles, and the version of the behaviour they
/// produce.
///
/// ## Why this carries a version
///
/// A recorded session replays from three things: the seed, the dealing
/// algorithm and this table. Change the third while the first two hold still
/// and every session recorded before the change replays *different* actions —
/// silently, because the seed still matches and every acceptance criterion in
/// `virtual-opponents` is written inside one version and still passes. The
/// version is what makes that divergence announce itself: `SessionRecord`
/// stores it, replay refuses to claim consistency when it differs, and the
/// committed golden sequences under `Tests/Fixtures/` are bound to it so that
/// changing behaviour without bumping the number turns a test red instead of
/// quietly repainting history.
///
/// **Any change that alters what `OpponentActionPolicy` returns must increment
/// `version`.** That includes the profile numbers, every threshold and curve in
/// the policy, and `PreflopHandRanking`'s ordering. Renaming a profile or
/// rewording its summary does not — those do not reach the action.
///
/// The rule is enforced rather than asked for: the committed golden sequences
/// are regenerated from live play, so an edit that changes an action and leaves
/// the version alone fails `OpponentGoldenSequenceTests`. Both halves of the
/// mechanism were checked by mutation — including two edits to
/// `PreflopHandRanking`'s scoring, which the golden caught even though the
/// ranking's own tests did not.
///
/// ## Why the table is hardcoded rather than shipped as content
///
/// A strategy pack's review status means "a human checked these frequencies
/// against a solver". There is no solver answer to "how would a made-up nit
/// play", so putting the profiles through the same review gate would make the
/// word `reviewed` mean two different things in the same system.
public enum OpponentProfileTable {
    /// The behaviour version. See the note on this type before changing it.
    public static let version = "1"

    /// What the user must be told about where opponent behaviour comes from.
    ///
    /// A constant of its own, separate from the strategy-content disclosures in
    /// the app target, and deliberately not shared with them. They answer
    /// different questions — one is about where a frequency table came from,
    /// the other about where an opponent's decisions come from — and a session
    /// screen has to show both at once. Collapsing them into one string would
    /// mean a session with reviewed content installed could show a reassuring
    /// content disclosure and say nothing at all about the opponents.
    public static let disclosure =
        "对手行为来自固定启发式规则，不是求解器策略，也不代表真实牌手。"

    public static let rock = OpponentProfile(
        id: .rock,
        name: "岩石",
        entryRateBasisPoints: 800,
        aggressionBasisPoints: 2_500,
        callingTendencyBasisPoints: 2_000,
        tendencySummary: "紧弱：只打很强的起手牌，被下注就走"
    )

    public static let tag = OpponentProfile(
        id: .tag,
        name: "稳固加注者",
        entryRateBasisPoints: 2_400,
        aggressionBasisPoints: 6_000,
        callingTendencyBasisPoints: 4_000,
        tendencySummary: "紧凶：入池不多，入池就多半在加注"
    )

    public static let station = OpponentProfile(
        id: .station,
        name: "跟注站",
        entryRateBasisPoints: 4_400,
        aggressionBasisPoints: 500,
        callingTendencyBasisPoints: 8_500,
        tendencySummary: "松弱：什么牌都看翻牌，很少主动下注，也很少弃牌"
    )

    public static let maniac = OpponentProfile(
        id: .maniac,
        name: "疯子",
        entryRateBasisPoints: 6_200,
        aggressionBasisPoints: 9_000,
        callingTendencyBasisPoints: 6_000,
        tendencySummary: "松凶：入池极宽，拿到主动权就下最大的尺度"
    )

    /// The four, tightest first. A fixed order, because the UI lists them and a
    /// test enumerates them.
    public static let profiles: [OpponentProfile] = [rock, tag, station, maniac]

    public static func profile(_ id: OpponentProfileID) -> OpponentProfile {
        switch id {
        case .rock: rock
        case .tag: tag
        case .station: station
        case .maniac: maniac
        }
    }

    public static func policy(_ id: OpponentProfileID) -> OpponentActionPolicy {
        OpponentActionPolicy(profile: profile(id))
    }
}
