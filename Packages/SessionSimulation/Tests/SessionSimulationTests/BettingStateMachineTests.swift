import PokerCore
import Testing
@testable import SessionSimulation

@Suite("下注状态永远合法")
struct BettingStateMachineTests {
    private static let seed: UInt64 = 42
    private static let handCount = 30

    /// Both directions, over every decision point in the 30 hands the spec
    /// names.
    ///
    /// One direction is not enough and the spec says so. A `legalActions()`
    /// that returned `{.fold}` and an `apply(_:)` that accepted only folds
    /// would satisfy "everything in the set is accepted" perfectly. What makes
    /// the pair meaningful is that the set is also *complete*: every action
    /// outside it is refused.
    @Test("每个决策点：集合内均被接受，集合外均被拒绝")
    func theLegalSetIsExactlyTheSetOfAcceptedActions() throws {
        var decisionPoints = 0
        var acceptedTotal = 0
        var rejectedTotal = 0

        try SessionWalk.run(seed: Self.seed, handCount: Self.handCount) { state in
            let legal = state.legalActions()
            let context = try #require(state.decisionContext())
            decisionPoints += 1

            #expect(!legal.isEmpty, "决策点给出了空的合法集合")

            for action in legal.canonicallyOrdered {
                var candidate = state
                do {
                    try candidate.apply(action)
                    acceptedTotal += 1
                } catch {
                    Issue.record("合法集合里的 \(action) 被拒绝：\(error)")
                }
            }

            for action in SessionWalk.candidateActions(for: context) where !legal.contains(action) {
                var candidate = state
                do {
                    try candidate.apply(action)
                    let message = "集合外的 \(action) 被接受了。合法集合是 "
                        + "\(legal.canonicallyOrdered)，上下文 \(context)"
                    Issue.record(Comment(rawValue: message))
                } catch {
                    rejectedTotal += 1
                }
            }
        }

        // Counts, because everything above is a loop and an empty loop is
        // silent. 30 hands at a six-handed table cannot plausibly produce
        // fewer than a hundred decisions.
        #expect(decisionPoints >= 100, "只走过 \(decisionPoints) 个决策点")
        #expect(acceptedTotal >= decisionPoints, "接受计数 \(acceptedTotal) 低于决策点数")
        #expect(rejectedTotal >= decisionPoints, "拒绝计数 \(rejectedTotal) 低于决策点数")
    }

    @Test("未面对下注时集合同时包含 check 与至少一个下注尺度")
    func anUnopenedSpotOffersACheckAndSomethingToBetWith() throws {
        var unopenedSpots = 0
        var spotsWithANonAllInBet = 0

        try SessionWalk.run(seed: Self.seed, handCount: Self.handCount) { state in
            let context = try #require(state.decisionContext())
            guard context.amountToCall.centiBB == 0 else {
                return
            }
            unopenedSpots += 1
            let legal = state.legalActions()

            #expect(legal.contains(.check), "未面对下注却不能过牌：\(legal.canonicallyOrdered)")
            #expect(!legal.contains(.fold), "未面对下注却可以弃牌")

            let sizes = legal.filter { action in
                switch action {
                case .bet, .allIn: true
                default: false
                }
            }
            #expect(!sizes.isEmpty, "未面对下注却没有任何下注尺度")

            if legal.contains(where: { if case .bet = $0 { true } else { false } }) {
                spotsWithANonAllInBet += 1
            }
        }

        #expect(unopenedSpots >= 20, "只遇到 \(unopenedSpots) 个未面对下注的决策点")
        // An all-in is a bet size, so the loop above would pass on a table where
        // the only offer was ever "shove". This says a real size is almost
        // always available; the handful of exceptions are seats too short for
        // any bet below their stack, which is a correct offer rather than a
        // missing one.
        #expect(
            spotsWithANonAllInBet * 10 >= unopenedSpots * 9,
            "\(unopenedSpots) 个未面对下注的点里只有 \(spotsWithANonAllInBet) 个给出了非全下的尺度"
        )
    }

    @Test("面对下注且剩余筹码大于须跟注额时集合同时包含 fold、call 与至少一个 raise 尺度")
    func facingABetWithChipsBehindOffersFoldCallAndARaise() throws {
        var spots = 0
        var spotsWithANonAllInRaise = 0

        try SessionWalk.run(seed: Self.seed, handCount: Self.handCount) { state in
            let context = try #require(state.decisionContext())
            let call = context.amountToCall.centiBB
            guard call > 0, call < context.effectiveStack.centiBB else {
                return
            }
            spots += 1
            let legal = state.legalActions()

            #expect(legal.contains(.fold), "面对下注却不能弃牌")
            #expect(
                legal.contains(.call(to: context.amountToCall)),
                "面对下注却不能跟注 \(call)：\(legal.canonicallyOrdered)"
            )

            let raises = legal.filter { action in
                switch action {
                case .raise, .allIn: true
                default: false
                }
            }
            #expect(!raises.isEmpty, "有筹码在后却没有任何加注尺度")

            if legal.contains(where: { if case .raise = $0 { true } else { false } }) {
                spotsWithANonAllInRaise += 1
            }
        }

        #expect(spots >= 30, "只遇到 \(spots) 个面对下注且有筹码在后的决策点")
        #expect(
            spotsWithANonAllInRaise >= spots / 2,
            "\(spots) 个点里只有 \(spotsWithANonAllInRaise) 个给出了非全下的加注尺度"
        )
    }

    /// The spec scenario, built exactly as written: the hero has 2BB left,
    /// faces a raise, and tries to make it 6BB.
    @Test("超出筹码的加注被拒绝，且合法集合恰为 fold 与 call")
    func aRaiseBeyondTheStackIsRejectedAndTheCallIsTheAllIn() throws {
        var stacks = SessionRunner.initialStacks
        // Seat 5 is the cutoff on hand 0 — last to act before the button, so
        // there is room for a raise to land in front of it.
        stacks[5] = BBAmount(centiBB: 200)

        var state = HandState(
            dealtHand: SessionDealer(seed: Self.seed).deal(handIndex: 0),
            stacks: stacks
        )

        #expect(state.seatToAct == 3, "第一个行动的应该是 UTG")
        try state.apply(.raise(to: BBAmount(centiBB: 350)))
        #expect(state.seatToAct == 4)
        try state.apply(.fold)

        let shortSeat = try #require(state.seatToAct)
        #expect(shortSeat == 5)
        let context = try #require(state.decisionContext())
        #expect(context.effectiveStack == BBAmount(centiBB: 200))
        #expect(
            context.amountToCall == BBAmount(centiBB: 200),
            "须跟注额没有被封顶到有效筹码，实际 \(context.amountToCall.centiBB)"
        )

        #expect(state.legalActions() == [.fold, .call(to: BBAmount(centiBB: 200))])
        #expect(
            !state.legalActions().contains(.allIn(to: BBAmount(centiBB: 200))),
            "集合里出现了独立的 all-in 项——筹码用尽时的 call 就是全下"
        )

        let before = state
        var attempted = state
        #expect(throws: SessionActionError.exceedsEffectiveStack(
            attempted: BBAmount(centiBB: 600),
            effectiveStack: BBAmount(centiBB: 200)
        )) {
            try attempted.apply(.raise(to: BBAmount(centiBB: 600)))
        }
        #expect(attempted == before, "被拒绝的行动改变了 Session 状态")
    }

    @Test("行动被拒绝时状态逐字段未改变")
    func aRejectedActionLeavesTheStateAlone() throws {
        var checkedRejections = 0

        try SessionWalk.run(seed: Self.seed, handCount: 5) { state in
            let context = try #require(state.decisionContext())
            let legal = state.legalActions()

            for action in SessionWalk.candidateActions(for: context)
            where !legal.contains(action) {
                var candidate = state
                #expect(throws: SessionActionError.self) {
                    try candidate.apply(action)
                }
                #expect(candidate == state, "\(action) 被拒绝后状态变了")
                checkedRejections += 1
            }
        }

        #expect(checkedRejections >= 100, "只检查了 \(checkedRejections) 次拒绝")
    }

    @Test("已结算的手牌拒绝任何后续行动")
    func aSettledHandAcceptsNothing() {
        let run = SessionRunner(seed: Self.seed).run(handCount: 1)
        #expect(run.hands.count == 1)

        var state = HandState(
            dealtHand: SessionDealer(seed: Self.seed).deal(handIndex: 0),
            stacks: SessionRunner.initialStacks
        )
        var rng = SplitMix64(seed: SessionRunner(seed: Self.seed).actionSeed(handIndex: 0))
        let policy = BaselineActionPolicy()
        while let decision = state.currentDecision() {
            try? state.apply(policy.chooseAction(at: decision, using: &rng))
        }

        #expect(state.isComplete)
        #expect(state.legalActions().isEmpty, "已结算的手牌还给出了合法行动")
        #expect(state.seatToAct == nil)

        for action in [DecisionAction.fold, .check, .call(to: BBAmount(centiBB: 100))] {
            var candidate = state
            #expect(throws: SessionActionError.handAlreadyComplete) {
                try candidate.apply(action)
            }
        }
    }

    /// Preflop with nothing but the blinds in is `unopened`; after an open it is
    /// `singleRaise`; after a three-bet it is `reraise`. The signature keys on
    /// this, so getting it wrong misfiles every spot in the session.
    @Test("面对的行动类别随加注次数推进")
    func facingActionTracksTheAggression() throws {
        var state = HandState(
            dealtHand: SessionDealer(seed: Self.seed).deal(handIndex: 0),
            stacks: SessionRunner.initialStacks
        )

        /// The smallest raise on offer. Taken from the legal set rather than
        /// written out, because the minimum raise moves with every previous
        /// raise and a hardcoded amount would be testing the size table instead
        /// of the aggression counter.
        func smallestRaise() throws -> DecisionAction {
            let raise = state.legalActions().canonicallyOrdered.first { action in
                if case .raise = action { true } else { false }
            }
            return try #require(raise, "没有可用的加注尺度")
        }

        #expect(state.facingAction == .unopened, "只有盲注时不应算作面对加注")
        try state.apply(.raise(to: BBAmount(centiBB: 350)))
        #expect(state.facingAction == .singleRaise)
        try state.apply(try smallestRaise())
        #expect(state.facingAction == .reraise)
        try state.apply(try smallestRaise())
        #expect(state.facingAction == .reraise, "四次加注仍然记为 reraise")
    }

    @Test("翻牌后重新开始下注，面对情形回到未面对下注")
    func eachStreetStartsFresh() throws {
        var state = HandState(
            dealtHand: SessionDealer(seed: Self.seed).deal(handIndex: 0),
            stacks: SessionRunner.initialStacks
        )

        // Everybody folds to the blinds, then both blinds check the flop.
        try state.apply(.fold) // UTG
        try state.apply(.fold) // HJ
        try state.apply(.fold) // CO
        try state.apply(.fold) // BTN
        #expect(state.seatToAct == 1, "小盲应该接着行动")
        try state.apply(.call(to: BBAmount(centiBB: 50)))
        #expect(state.seatToAct == 2, "大盲应该拿到选择权")
        #expect(state.decisionContext()?.amountToCall == BBAmount(centiBB: 0))
        try state.apply(.check)

        #expect(state.street == .flop)
        #expect(state.board.count == 3)
        #expect(state.facingAction == .unopened)
        #expect(state.seatToAct == 1, "翻后应该由按钮后第一个玩家先行动")
        #expect(state.decisionContext()?.amountToCall == BBAmount(centiBB: 0))
        #expect(state.pot == BBAmount(centiBB: 200))
    }
}
