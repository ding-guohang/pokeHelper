import Foundation
import Testing
@testable import PokerCore

@Test func unopenedNodeOffersCheckAndConfiguredBets() {
    let context = BettingDecisionContext(
        pot: .init(centiBB: 650),
        effectiveStack: .init(centiBB: 9_700),
        amountToCall: .init(centiBB: 0),
        minimumRaiseTo: nil,
        configuredBetSizes: [.init(centiBB: 217), .init(centiBB: 488)]
    )

    #expect(context.legalActions() == [
        .check,
        .bet(to: .init(centiBB: 217)),
        .bet(to: .init(centiBB: 488)),
        .allIn(to: .init(centiBB: 9_700)),
    ])
}

@Test func facingBetOffersFoldCallAndLegalRaises() {
    let context = BettingDecisionContext(
        pot: .init(centiBB: 1_000),
        effectiveStack: .init(centiBB: 8_000),
        amountToCall: .init(centiBB: 300),
        minimumRaiseTo: .init(centiBB: 900),
        configuredBetSizes: [.init(centiBB: 750), .init(centiBB: 1_200)]
    )

    #expect(context.legalActions() == [
        .fold,
        .call(to: .init(centiBB: 300)),
        .raise(to: .init(centiBB: 1_200)),
        .allIn(to: .init(centiBB: 8_000)),
    ])
}

@Test func facingBetDoesNotOfferRaiseWhenMinimumRaiseIsNotAboveCall() {
    let context = BettingDecisionContext(
        pot: .init(centiBB: 1_000),
        effectiveStack: .init(centiBB: 2_000),
        amountToCall: .init(centiBB: 300),
        minimumRaiseTo: .init(centiBB: 200),
        configuredBetSizes: [.init(centiBB: 250)]
    )

    #expect(context.legalActions() == [
        .fold,
        .call(to: .init(centiBB: 300)),
        .allIn(to: .init(centiBB: 2_000)),
    ])
}

@Test func legalActionsExcludeNonPositiveAndAllInConfiguredSizes() {
    let context = BettingDecisionContext(
        pot: .init(centiBB: 1_000),
        effectiveStack: .init(centiBB: 2_000),
        amountToCall: .init(centiBB: 300),
        minimumRaiseTo: .init(centiBB: 900),
        configuredBetSizes: [.init(centiBB: 0), .init(centiBB: 900), .init(centiBB: 2_000), .init(centiBB: 2_500)]
    )

    #expect(context.legalActions() == [
        .fold,
        .call(to: .init(centiBB: 300)),
        .raise(to: .init(centiBB: 900)),
        .allIn(to: .init(centiBB: 2_000)),
    ])
}

@Test func callingAnOpponentAllInDoesNotOfferAnActiveAllInAction() {
    let context = BettingDecisionContext(
        pot: .init(centiBB: 1_000),
        effectiveStack: .init(centiBB: 2_000),
        amountToCall: .init(centiBB: 2_000),
        minimumRaiseTo: nil,
        configuredBetSizes: []
    )

    #expect(context.legalActions() == [
        .fold,
        .call(to: .init(centiBB: 2_000)),
    ])
}

@Test func decisionActionCodableUsesStableFlatJSON() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    #expect(String(decoding: try encoder.encode(DecisionAction.check), as: UTF8.self) == #"{"kind":"check"}"#)
    #expect(String(decoding: try encoder.encode(DecisionAction.bet(to: .init(centiBB: 217))), as: UTF8.self) == #"{"kind":"bet","toCentiBB":217}"#)
    #expect(String(decoding: try encoder.encode(DecisionAction.raise(to: .init(centiBB: 1_200))), as: UTF8.self) == #"{"kind":"raise","toCentiBB":1200}"#)

    let action = DecisionAction.allIn(to: .init(centiBB: 9_700))
    #expect(try JSONDecoder().decode(DecisionAction.self, from: encoder.encode(action)) == action)
}

@Test func decisionActionCodableRejectsAmountsWithWrongShape() {
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(DecisionAction.self, from: Data(#"{"kind":"call"}"#.utf8))
    }
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(DecisionAction.self, from: Data(#"{"kind":"check","toCentiBB":0}"#.utf8))
    }
}

@Test func bettingDecisionContextCodableRejectsCallsAboveTheEffectiveStack() {
    let invalidContext = Data(#"{"pot":{"centiBB":1000},"effectiveStack":{"centiBB":200},"amountToCall":{"centiBB":300},"minimumRaiseTo":null,"configuredBetSizes":[]}"#.utf8)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(BettingDecisionContext.self, from: invalidContext)
    }
}

@Test func bettingDecisionContextCodableRejectsMinimumRaiseNotAboveCall() {
    let invalidContext = Data(#"{"pot":{"centiBB":1000},"effectiveStack":{"centiBB":2000},"amountToCall":{"centiBB":300},"minimumRaiseTo":{"centiBB":200},"configuredBetSizes":[{"centiBB":250}]}"#.utf8)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(BettingDecisionContext.self, from: invalidContext)
    }
}

// The one spot where a call and an all-in are the same action.
//
// M2A's session state machine caps the amount owed at the effective stack, so
// a player facing a 5BB bet with 3BB behind is handed
// `amountToCall == effectiveStack`. The legal set is then exactly fold-or-call
// with no separate all-in entry: an `.allIn(to:)` sitting beside an identical
// `.call(to:)` would offer the same action twice under two names.
@Test func aCallForTheWholeStackIsTheAllIn() {
    let context = BettingDecisionContext(
        pot: BBAmount(centiBB: 800),
        effectiveStack: BBAmount(centiBB: 300),
        amountToCall: BBAmount(centiBB: 300),
        minimumRaiseTo: BBAmount(centiBB: 600),
        configuredBetSizes: [BBAmount(centiBB: 600), BBAmount(centiBB: 900)]
    )

    #expect(context.legalActions() == [.fold, .call(to: BBAmount(centiBB: 300))])
}

// The boundary from the other side: one centi-BB behind and the all-in is a
// distinct, larger action again.
@Test func allInSeparatesFromCallAsSoonAsThereIsSomethingBehind() {
    let context = BettingDecisionContext(
        pot: BBAmount(centiBB: 800),
        effectiveStack: BBAmount(centiBB: 301),
        amountToCall: BBAmount(centiBB: 300),
        minimumRaiseTo: BBAmount(centiBB: 600),
        configuredBetSizes: []
    )

    #expect(context.legalActions() == [
        .fold,
        .call(to: BBAmount(centiBB: 300)),
        .allIn(to: BBAmount(centiBB: 301)),
    ])
}
