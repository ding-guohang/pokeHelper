import Foundation
import PokerCore

/// What one profile does over a seeded session, in a form that can be committed
/// to the repository and compared byte for byte.
///
/// ## Why this type is in the library rather than in the test
///
/// Because the writer and the reader must not be able to drift. The record is
/// produced by `session-transcript --golden` in one process and checked by a
/// test in another; two hand-rolled copies of the same five fields would
/// eventually disagree about a key name, and the failure mode of that
/// disagreement is a decoding error that looks like a broken fixture rather
/// than a broken opponent.
///
/// ## What it is for
///
/// `version` is stamped in by `make`, never passed in. That is the whole
/// mechanism behind the rule in `OpponentProfileTable`:
///
/// - change behaviour and forget the version → `actions` no longer match the
///   committed file → red;
/// - bump the version and forget to regenerate → `tableVersion` no longer
///   matches → red.
///
/// Either way the change announces itself, instead of every session recorded
/// under the old table quietly replaying as a different session.
public struct OpponentActionGolden: Codable, Hashable, Sendable {
    /// The behaviour table version these actions came out of.
    public let tableVersion: String
    public let profile: OpponentProfileID
    public let seed: UInt64
    public let handCount: Int

    /// One entry per opponent action, in the format
    /// `handIndex:seat:street:action`. The hero's seat is excluded, matching
    /// `SessionTranscript.opponentActions`.
    public let actions: [String]

    /// Plays the session and records what the profile did.
    ///
    /// Every seat plays the same profile, including the hero's — the hero's
    /// actions are then dropped. A homogeneous table is what makes the record a
    /// statement about one profile rather than about a particular mixture.
    public static func make(profile: OpponentProfileID, seed: UInt64, handCount: Int) -> Self {
        let run = SessionRunner(seed: seed, policy: OpponentProfileTable.policy(profile))
            .run(handCount: handCount)
        return OpponentActionGolden(
            tableVersion: OpponentProfileTable.version,
            profile: profile,
            seed: seed,
            handCount: handCount,
            actions: SessionTranscript.opponentActions(run)
        )
    }

    /// Pretty-printed with sorted keys, so a regenerated file differs from the
    /// committed one only where the behaviour differs.
    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
