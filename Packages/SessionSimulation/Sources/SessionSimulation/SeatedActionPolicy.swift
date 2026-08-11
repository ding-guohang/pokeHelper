import PokerCore
import Synchronization

/// Sits a profile in each opponent seat and the user in seat 0.
///
/// The engine asks one policy for every decision, so this is what makes a table
/// of four different opponents possible at all. Dispatch is by seat and nothing
/// else: no state, no memory of earlier hands, so the same seat in the same spot
/// with the same generator state answers the same way in any process.
public struct SeatedActionPolicy: SessionActionPolicy {
    public let heroPolicy: any SessionActionPolicy
    public let seating: SeatAssignment

    public init(heroPolicy: any SessionActionPolicy, seating: SeatAssignment) {
        self.heroPolicy = heroPolicy
        self.seating = seating
    }

    public func chooseAction(
        at decision: DecisionPoint,
        using rng: inout SplitMix64
    ) -> DecisionAction {
        guard let profile = seating.profile(forSeat: decision.seat) else {
            // The hero's turn. Exactly one value comes off the shared stream,
            // whatever the hero is, and the hero draws from a branch seeded
            // with it.
            //
            // This is what makes a session rebuildable. A hero who drew
            // directly from the shared stream would move it by however many
            // values that particular hero happened to want — one for the
            // autopilot, none for a human, none for a replay of recorded
            // actions — and every opponent decision after the hero's first one
            // would come out of a different position in the sequence. The
            // record would then reproduce the cards and a different hand. It
            // was measured, not predicted: replaying a session played by the
            // autopilot diverged at the first hand until the hero's draws were
            // moved off the shared stream.
            var heroStream = SplitMix64(seed: rng.next())
            return heroPolicy.chooseAction(at: decision, using: &heroStream)
        }
        return OpponentProfileTable.policy(profile)
            .chooseAction(at: decision, using: &rng)
    }
}

/// Plays back the hero's recorded actions.
///
/// A session's opponents are a function of the seed and the behaviour table, so
/// a rebuild can derive them. The hero is a person, and their choices exist
/// only in the record. Replaying a session therefore means feeding these back
/// in while the engine re-derives everything else — which is also what makes
/// the rebuild a real check: the opponents have to arrive at the same actions
/// from the same states, rather than being copied out of the record.
///
/// A recorded action that the state machine would not accept is not forced
/// through. Rather than crash a replay of a record written by an older,
/// differently-behaved build, the fallback takes the first legal action and the
/// comparison against the stored hands reports the divergence.
public struct RecordedHeroPolicy: SessionActionPolicy {
    private final class Cursor: Sendable {
        private let remaining: Mutex<[Int: [DecisionAction]]>

        init(actionsByHand: [Int: [DecisionAction]]) {
            remaining = Mutex(actionsByHand)
        }

        func next(handIndex: Int) -> DecisionAction? {
            remaining.withLock { actionsByHand in
                guard var actions = actionsByHand[handIndex], !actions.isEmpty else {
                    return nil
                }
                let action = actions.removeFirst()
                actionsByHand[handIndex] = actions
                return action
            }
        }
    }

    private let cursor: Cursor

    public init(hands: [SessionHandRecord]) {
        var actionsByHand: [Int: [DecisionAction]] = [:]
        for hand in hands {
            actionsByHand[hand.handIndex] = hand.heroActions
        }
        cursor = Cursor(actionsByHand: actionsByHand)
    }

    public func chooseAction(
        at decision: DecisionPoint,
        using _: inout SplitMix64
    ) -> DecisionAction {
        let actions = decision.orderedLegalActions
        precondition(!actions.isEmpty, "A decision point must offer at least one action")

        guard let recorded = cursor.next(handIndex: decision.handIndex),
              actions.contains(recorded)
        else {
            return actions[0]
        }
        return recorded
    }
}
