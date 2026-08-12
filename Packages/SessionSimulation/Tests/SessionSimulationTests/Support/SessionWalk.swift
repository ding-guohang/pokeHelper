import PokerCore
@testable import SessionSimulation

/// Plays a session the way `SessionRunner.run` does, but hands the caller the
/// `HandState` at every decision point and at every settlement.
///
/// `SessionRunner` returns finished hands, which is the right shape for a
/// caller and the wrong shape for the two properties that are about the states
/// in between: whether the legal set is exactly the set of accepted actions,
/// and whether the pot is empty the moment a hand settles.
enum SessionWalk {
    /// Runs `handCount` hands from `seed`, calling back before every action and
    /// after every settlement. Returns the final stacks.
    @discardableResult
    static func run(
        seed: UInt64,
        handCount: Int,
        policy: any SessionActionPolicy = BaselineActionPolicy(),
        atDecision: (HandState) throws -> Void = { _ in },
        atHandEnd: (HandState) throws -> Void = { _ in }
    ) rethrows -> [BBAmount] {
        let runner = SessionRunner(seed: seed, policy: policy)
        var stacks = SessionRunner.initialStacks

        for handIndex in 0 ..< handCount {
            var state = HandState(
                dealtHand: runner.dealer.deal(handIndex: handIndex),
                stacks: stacks
            )
            var rng = SplitMix64(seed: runner.actionSeed(handIndex: handIndex))

            while !state.isComplete {
                guard let decision = state.currentDecision() else {
                    fatalError("Hand \(handIndex) is unfinished with nobody to act")
                }
                try atDecision(state)
                let action = policy.chooseAction(at: decision, using: &rng)
                do {
                    try state.apply(action)
                } catch {
                    fatalError("Policy produced an illegal action \(action): \(error)")
                }
            }

            try atHandEnd(state)
            stacks = state.endingStacks
        }

        return stacks
    }

    /// Every action that could plausibly be attempted at a decision point,
    /// legal or not.
    ///
    /// Deliberately built around the boundaries rather than from random
    /// amounts: one under the call, one over the minimum raise, exactly the
    /// stack, one over the stack. A rejection test made of wild values proves
    /// only that the machine rejects nonsense, and nonsense is not what a
    /// betting engine gets wrong.
    static func candidateActions(for context: BettingDecisionContext) -> [DecisionAction] {
        let call = context.amountToCall.centiBB
        let stack = context.effectiveStack.centiBB
        let minimumRaise = context.minimumRaiseTo?.centiBB

        var amounts: Set<Int> = [
            0, 1,
            call, call - 1, call + 1,
            stack, stack - 1, stack + 1, stack + 1_000,
            context.pot.centiBB,
        ]
        if let minimumRaise {
            amounts.formUnion([minimumRaise, minimumRaise - 1, minimumRaise + 1])
        }
        for size in context.configuredBetSizes {
            amounts.formUnion([size.centiBB, size.centiBB - 1, size.centiBB + 1])
        }

        // Sorted before use: `Set` iteration order varies between processes, and
        // a test whose candidate list is ordered by the hash seed is a test that
        // covers something different on every run.
        var actions: [DecisionAction] = [.fold, .check]
        for amount in amounts.sorted() where amount >= 0 {
            let value = BBAmount(centiBB: amount)
            actions.append(.call(to: value))
            actions.append(.bet(to: value))
            actions.append(.raise(to: value))
            actions.append(.allIn(to: value))
        }
        return actions
    }
}
