import Foundation
import PokerCore

/// One decision the hero actually made, tagged with the spot signature that
/// situates it against curated content.
///
/// `HandHistory` produces these because they are pure poker facts — which
/// street, where the hero sits, the two cards held, how much aggression was
/// faced, how deep the stacks were, and what the hero did. Whether any content
/// covers the spot, and how far the hero's action deviated from it, is a
/// question only the app layer can ask, because only it sees both the imported
/// hand and the installed strategy content.
public struct HeroDecisionSignature: Hashable, Sendable, Codable {
    /// The street the decision was made on.
    public let street: Street
    /// The decision's position in the street's voluntary-action sequence, so a
    /// street where the hero acts more than once still names each decision.
    public let actionIndexInStreet: Int
    /// The spot's identity: street / offset / hand class / facing / stack depth.
    public let signature: SpotSignature
    /// The action the hero actually took at this point.
    public let action: ObservedAction
    /// Whether the hero's committed chips reached their starting stack after
    /// this action — a pure fact about amounts, not the text saying "all-in".
    public let isAllIn: Bool

    public init(
        street: Street,
        actionIndexInStreet: Int,
        signature: SpotSignature,
        action: ObservedAction,
        isAllIn: Bool
    ) {
        self.street = street
        self.actionIndexInStreet = actionIndexInStreet
        self.signature = signature
        self.action = action
        self.isAllIn = isAllIn
    }
}

extension ObservedHand {
    /// The signature of every voluntary decision the hero made, in the order
    /// they occurred.
    ///
    /// The hero is the sole seat whose hole cards are `.known` (this slice does
    /// not read opponents' shown cards, so exactly one seat is named). The
    /// betting is replayed street by street to rebuild, at each hero decision,
    /// how much aggression was faced and how deep the hero's stack still was —
    /// pure `Int`/enum work with no `Set`/`Dictionary` iteration, clock or
    /// randomness, so two processes agree byte for byte.
    public func heroDecisionSignatures() -> [HeroDecisionSignature] {
        guard let hero = seats.first(where: { seat in
            if case .known = seat.holeCards { return true }
            return false
        }), case let .known(cardA, cardB) = hero.holeCards else {
            return []
        }

        let heroSeat = hero.seat
        let heroOffset = hero.seatOffsetFromButton
        let startingStack = hero.startingStackCentiBB
        let handClass = HandClass(cardA, cardB)

        // A blind the hero posted is already part of that seat's preflop
        // "to" amount, so it seeds the preflop street investment. An ante is
        // dead money that never enters a "to" amount but still leaves the
        // stack, so it is carried separately and added to every commitment.
        var heroBlindPost = 0
        var heroAnteTotal = 0
        for post in forcedPosts where post.seat == heroSeat {
            switch post.kind {
            case .smallBlind, .bigBlind: heroBlindPost += post.amountCentiBB
            case .ante: heroAnteTotal += post.amountCentiBB
            }
        }

        var signatures: [HeroDecisionSignature] = []
        // The hero's committed chips from every completed street.
        var heroCommittedBeforeStreet = 0

        for street in streets {
            // The hero's "to" amount on this street so far, seeded with any
            // blind on preflop and never with the ante.
            var heroStreetInvestment = street.street == .preflop ? heroBlindPost : 0
            var priorRaiseCount = 0

            for (actionIndex, action) in street.actions.enumerated() {
                if action.seat == heroSeat {
                    let committedBefore = heroAnteTotal + heroCommittedBeforeStreet + heroStreetInvestment
                    let signature = SpotSignature(
                        street: street.street,
                        heroSeatOffsetFromButton: heroOffset,
                        handClass: handClass,
                        facing: FacingAction(priorRaiseCount: priorRaiseCount),
                        stackBucket: StackBucket(
                            effectiveStack: BBAmount(centiBB: startingStack - committedBefore)
                        )
                    )

                    switch action.kind {
                    case .fold, .check:
                        break
                    case .call, .bet, .raiseTo:
                        // "To" amount: the total in front of the seat after the
                        // action, so the street investment is set, not added to.
                        if let toAmount = action.amountCentiBB {
                            heroStreetInvestment = toAmount
                        }
                    }

                    let committedAfter = heroAnteTotal + heroCommittedBeforeStreet + heroStreetInvestment
                    signatures.append(
                        HeroDecisionSignature(
                            street: street.street,
                            actionIndexInStreet: actionIndex,
                            signature: signature,
                            action: action,
                            isAllIn: committedAfter == startingStack
                        )
                    )
                }

                if action.kind == .raiseTo || action.kind == .bet {
                    priorRaiseCount += 1
                }
            }

            heroCommittedBeforeStreet += heroStreetInvestment
        }

        return signatures
    }
}
