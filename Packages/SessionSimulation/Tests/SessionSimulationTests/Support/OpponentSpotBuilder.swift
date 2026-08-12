import PokerCore
@testable import SessionSimulation

/// Builds decision points by hand, for the properties that need a *stated*
/// spot rather than one the engine happened to deal.
///
/// Every spot it produces is built the same way a real one is: the legal set is
/// computed by `BettingDecisionContext.legalActions()` from the context, never
/// written out alongside it. A spot whose legal set was hand-listed could
/// contain an action the state machine would refuse, and a policy tested
/// against it would look legal while being nothing of the kind.
enum OpponentSpotBuilder {
    enum BuildError: Error, CustomStringConvertible {
        case impossibleHolding(String)

        var description: String {
            switch self {
            case let .impossibleHolding(reason): "无法构造手牌：\(reason)"
            }
        }
    }

    /// Two concrete cards in the given class.
    ///
    /// Suits are assigned from the class rather than the class inferred from
    /// the suits, so that sweeping all 169 classes really covers all 169.
    static func cards(for handClass: HandClass) throws -> [Card] {
        let cards: [Card] = switch handClass.suitedness {
        case .pair:
            [Card(rank: handClass.highRank, suit: .spades), Card(rank: handClass.lowRank, suit: .hearts)]
        case .suited:
            [Card(rank: handClass.highRank, suit: .spades), Card(rank: handClass.lowRank, suit: .spades)]
        case .offsuit:
            [Card(rank: handClass.highRank, suit: .spades), Card(rank: handClass.lowRank, suit: .hearts)]
        }
        guard cards[0] != cards[1], HandClass(cards[0], cards[1]) == handClass else {
            throw BuildError.impossibleHolding("\(handClass) 生成出 \(cards.map(\.code))")
        }
        return cards
    }

    /// Preflop, one big blind to call, nobody has raised.
    ///
    /// The spot every profile's entry rate is measured on: putting money in
    /// here is exactly what "entering the pot" means.
    static func preflopFacingBlind(
        handClass: HandClass,
        seatOffsetFromButton offset: Int
    ) throws -> DecisionPoint {
        let hole = try cards(for: handClass)
        let context = BettingDecisionContext(
            pot: BBAmount(centiBB: 150),
            effectiveStack: BBAmount(centiBB: 10_000),
            amountToCall: BBAmount(centiBB: 100),
            minimumRaiseTo: BBAmount(centiBB: 200),
            configuredBetSizes: [200, 225, 350].map { BBAmount(centiBB: $0) }
        )
        return point(
            street: .preflop,
            facing: .unopened,
            hole: hole,
            board: [],
            context: context,
            seatOffsetFromButton: offset
        )
    }

    /// A flop with top pair and nothing bet yet — a holding at the middle of
    /// the strength scale, which is where the stated aggression figure is
    /// defined.
    static func postflopUnopened() throws -> DecisionPoint {
        let context = BettingDecisionContext(
            pot: BBAmount(centiBB: 600),
            effectiveStack: BBAmount(centiBB: 9_700),
            amountToCall: BBAmount(centiBB: 0),
            minimumRaiseTo: nil,
            configuredBetSizes: [100, 300, 600].map { BBAmount(centiBB: $0) }
        )
        return point(
            street: .flop,
            facing: .unopened,
            hole: [Card(code: "Kh")!, Card(code: "Qd")!],
            board: [Card(code: "Kc")!, Card(code: "7s")!, Card(code: "2d")!],
            context: context,
            seatOffsetFromButton: 5
        )
    }

    /// The same flop and holding, facing a bet with chips behind — where the
    /// stated calling tendency is defined.
    static func postflopFacingBet() throws -> DecisionPoint {
        let context = BettingDecisionContext(
            pot: BBAmount(centiBB: 900),
            effectiveStack: BBAmount(centiBB: 9_700),
            amountToCall: BBAmount(centiBB: 300),
            minimumRaiseTo: BBAmount(centiBB: 600),
            configuredBetSizes: [600, 900, 1_500].map { BBAmount(centiBB: $0) }
        )
        return point(
            street: .flop,
            facing: .singleRaise,
            hole: [Card(code: "Kh")!, Card(code: "Qd")!],
            board: [Card(code: "Kc")!, Card(code: "7s")!, Card(code: "2d")!],
            context: context,
            seatOffsetFromButton: 5
        )
    }

    /// The spec's short-stack spot: 3BB behind, facing a 5BB bet already capped
    /// to the whole stack.
    ///
    /// The legal set here is exactly `{.fold, .call(to: 3BB)}` — the call *is*
    /// the shove, and there is no separate all-in to offer.
    static func shortStackFacingShove(
        handClass: HandClass,
        seatOffsetFromButton offset: Int = 3
    ) throws -> DecisionPoint {
        let context = BettingDecisionContext(
            pot: BBAmount(centiBB: 800),
            effectiveStack: BBAmount(centiBB: 300),
            amountToCall: BBAmount(centiBB: 300),
            minimumRaiseTo: nil,
            configuredBetSizes: []
        )
        return point(
            street: .preflop,
            facing: .singleRaise,
            hole: try cards(for: handClass),
            board: [],
            context: context,
            seatOffsetFromButton: offset
        )
    }

    private static func point(
        street: Street,
        facing: FacingAction,
        hole: [Card],
        board: [Card],
        context: BettingDecisionContext,
        seatOffsetFromButton offset: Int
    ) -> DecisionPoint {
        let handClass = HandClass(hole[0], hole[1])
        return DecisionPoint(
            handIndex: 0,
            seat: TableRules.seat(atOffset: offset, buttonSeat: 0),
            seatOffsetFromButton: offset,
            street: street,
            holeCards: hole,
            board: board,
            pot: context.pot,
            context: context,
            legalActions: context.legalActions(),
            facing: facing,
            handClass: handClass,
            signature: SpotSignature(
                street: street,
                heroSeatOffsetFromButton: offset,
                handClass: handClass,
                facing: facing,
                stackBucket: StackBucket(effectiveStack: context.effectiveStack)
            )
        )
    }
}
