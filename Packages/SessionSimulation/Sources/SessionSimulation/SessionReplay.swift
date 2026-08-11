import PokerCore

/// What came out of replaying a stored session.
///
/// Deliberately not a `Bool` and not an optional list of hands. Three states
/// have to be distinguishable, and the one that gets lost when they are
/// collapsed is the middle one: a record produced by a *different* behaviour
/// table, which can be shown but cannot be claimed to be a faithful replay.
public struct SessionReplayResult: Sendable {
    /// The hands as they were stored. Always present — a record written under
    /// another behaviour table is still a record of hands that were played, and
    /// refusing to show them would punish the user for a change we made.
    public let savedHands: [SessionHandRecord]

    /// What the engine produced now, or `nil` when nothing was rebuilt because
    /// the behaviour table has changed.
    ///
    /// Nil rather than "rebuilt anyway, with a warning attached": rebuilding
    /// under the current table and displaying the result is the silent
    /// repainting of history this whole mechanism exists to prevent.
    public let rebuiltHands: [SessionHandRecord]?

    /// The version the record was written under, and the one in this build.
    public let recordedTableVersion: String
    public let currentTableVersion: String

    /// True only when the behaviour table matches *and* the rebuild came out
    /// hand for hand identical.
    public var claimsFaithfulReplay: Bool {
        recordedTableVersion == currentTableVersion && rebuiltHands == savedHands
    }

    public var behaviourTableChanged: Bool {
        recordedTableVersion != currentTableVersion
    }

    /// What to tell the user when the table has changed. Nil when it has not,
    /// so a screen cannot show a mismatch notice for a session that matches.
    public var behaviourTableNotice: String? {
        guard behaviourTableChanged else {
            return nil
        }
        return "这局 Session 由第 \(recordedTableVersion) 版对手行为表产生，"
            + "当前为第 \(currentTableVersion) 版。以下为已保存的手牌记录，不重放。"
    }

    /// The first hand where a rebuild disagreed with the record, if any. A bug
    /// report rather than an expected state: within one behaviour table version
    /// the engine has to reproduce its own output.
    public var firstDivergentHandIndex: Int? {
        guard let rebuiltHands else {
            return nil
        }
        for (saved, rebuilt) in zip(savedHands, rebuiltHands) where saved != rebuilt {
            return saved.handIndex
        }
        return savedHands.count == rebuiltHands.count ? nil : rebuiltHands.count
    }
}

/// Rebuilds a stored session.
public enum SessionReplay {
    /// Replays `savedHands` from `record`.
    ///
    /// The cards and the opponents come from the seed and the seating; only the
    /// hero's actions are read back out of the record, because only they are not
    /// derivable. If the recorded behaviour-table version is not this build's,
    /// nothing is rebuilt at all.
    public static func replay(
        record: SessionRecord,
        savedHands: [SessionHandRecord],
        currentTableVersion: String = OpponentProfileTable.version
    ) -> SessionReplayResult {
        guard record.opponentProfileTableVersion == currentTableVersion else {
            return SessionReplayResult(
                savedHands: savedHands,
                rebuiltHands: nil,
                recordedTableVersion: record.opponentProfileTableVersion,
                currentTableVersion: currentTableVersion
            )
        }

        let runner = SessionRunner(
            seed: record.seed,
            policy: record.policy(heroPolicy: RecordedHeroPolicy(hands: savedHands))
        )
        var stacks = SessionRunner.initialStacks
        var rebuilt: [SessionHandRecord] = []
        rebuilt.reserveCapacity(savedHands.count)

        for hand in savedHands {
            let played = runner.playHand(handIndex: hand.handIndex, stacks: stacks)
            stacks = played.endingStacks
            rebuilt.append(SessionHandRecord(played))
        }

        return SessionReplayResult(
            savedHands: savedHands,
            rebuiltHands: rebuilt,
            recordedTableVersion: record.opponentProfileTableVersion,
            currentTableVersion: currentTableVersion
        )
    }
}
