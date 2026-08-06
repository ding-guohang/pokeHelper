public struct BettingDecisionContext: Hashable, Codable, Sendable {
    public let pot: BBAmount
    public let effectiveStack: BBAmount
    public let amountToCall: BBAmount
    public let minimumRaiseTo: BBAmount?
    public let configuredBetSizes: [BBAmount]

    public init(
        pot: BBAmount,
        effectiveStack: BBAmount,
        amountToCall: BBAmount,
        minimumRaiseTo: BBAmount?,
        configuredBetSizes: [BBAmount]
    ) {
        precondition(amountToCall <= effectiveStack, "Call amount cannot exceed the effective stack")

        self.pot = pot
        self.effectiveStack = effectiveStack
        self.amountToCall = amountToCall
        self.minimumRaiseTo = minimumRaiseTo
        self.configuredBetSizes = configuredBetSizes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pot = try container.decode(BBAmount.self, forKey: .pot)
        let effectiveStack = try container.decode(BBAmount.self, forKey: .effectiveStack)
        let amountToCall = try container.decode(BBAmount.self, forKey: .amountToCall)
        let minimumRaiseTo = try container.decodeIfPresent(BBAmount.self, forKey: .minimumRaiseTo)
        let configuredBetSizes = try container.decode([BBAmount].self, forKey: .configuredBetSizes)

        guard amountToCall <= effectiveStack else {
            throw DecodingError.dataCorruptedError(
                forKey: .amountToCall,
                in: container,
                debugDescription: "Call amount cannot exceed the effective stack"
            )
        }

        self.init(
            pot: pot,
            effectiveStack: effectiveStack,
            amountToCall: amountToCall,
            minimumRaiseTo: minimumRaiseTo,
            configuredBetSizes: configuredBetSizes
        )
    }

    public func legalActions() -> Set<DecisionAction> {
        var actions: Set<DecisionAction> = [.allIn(to: effectiveStack)]

        if amountToCall == BBAmount(centiBB: 0) {
            actions.insert(.check)
            for size in configuredBetSizes where size.centiBB > 0 && size < effectiveStack {
                actions.insert(.bet(to: size))
            }
        } else {
            actions.insert(.fold)
            actions.insert(.call(to: amountToCall))

            if let minimumRaiseTo {
                for size in configuredBetSizes where size.centiBB > 0 && size >= minimumRaiseTo && size < effectiveStack {
                    actions.insert(.raise(to: size))
                }
            }
        }

        return actions
    }
}
