import Foundation
import PokerCore
import SessionSimulation

/// Plays a stored session forward, writing each hand down before dealing the
/// next one.
///
/// The order matters and is the whole of what makes an interrupted session
/// resumable: play, append, then deal. Batching the writes until the session
/// ends would lose every hand of a session that was interrupted, which is the
/// only kind of session this code exists for.
public enum SessionPlaythrough {
    /// Plays from wherever the record left off.
    ///
    /// Resumption reads two things off the stored hands — how many were played
    /// and what the stacks were at the end of the last one — and derives
    /// nothing from a counter kept elsewhere. The hand index carries the cards
    /// and the action stream, so a resume that started counting from zero would
    /// deal hand 0's cards into hand 8's slot.
    @discardableResult
    public static func play(
        sessionID: UUID,
        store: FileSessionRecordStore,
        heroPolicy: any SessionActionPolicy = BaselineActionPolicy(),
        stoppingAfter handLimit: Int? = nil,
        onHandRecorded: (@Sendable (SessionHandRecord) -> Void)? = nil
    ) async throws -> [SessionHandRecord] {
        let progress = try await store.progress(for: sessionID)
        let record = progress.record
        let runner = SessionRunner(
            seed: record.seed,
            policy: record.policy(heroPolicy: heroPolicy)
        )

        var stacks = progress.stacks
        var played: [SessionHandRecord] = []

        var handIndex = progress.nextHandIndex
        while handIndex < record.handCount {
            if let handLimit, played.count == handLimit {
                break
            }
            // The table has broken up: fewer than two seats hold chips, so
            // there is no hand to deal. Stop rather than write a blindless hand.
            guard SessionRunner.seatsWithChips(stacks) >= SessionRunner.minimumSeatsToDeal else {
                break
            }

            let hand = runner.playHand(handIndex: handIndex, stacks: stacks)
            stacks = hand.endingStacks

            let stored = SessionHandRecord(hand)
            try await store.appendHand(stored, to: sessionID)
            played.append(stored)
            onHandRecorded?(stored)

            handIndex += 1
        }

        return played
    }
}
