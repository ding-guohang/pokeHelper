import Foundation
import HandHistory
import PokerCore
import StrategyContent
import XCTest
@testable import PokerCoach

/// Builds installed-content scenarios whose coverage keys are pinned exactly, so
/// an imported-hand test can decide which hero decisions installed content
/// covers without depending on the shipped pack.
///
/// The only fields the coverage key and the range lookup read are set from the
/// caller — seat, facing, street (via board size), stack bucket (via effective
/// stack) and one range cell for the hero's class. The rest comes from the
/// decision-session fixture, because none of it participates in matching.
@MainActor
enum HandLabContentFixture {
    /// A scenario covering `key`, whose range table gives `handClass` a weight of
    /// `weightBasisPoints` for `actionKey` ("raise" or "call").
    static func scenario(
        id: String,
        covering key: SpotCoverageKey,
        handClass: HandClass,
        actionKey: String,
        weightBasisPoints: Int
    ) throws -> DecisionScenario {
        let template = try DecisionSessionFixture.makePack().scenarios[0]

        var weights = [actionKey: weightBasisPoints]
        if actionKey != RangeBaseline.foldKey {
            weights[RangeBaseline.foldKey] = RangeBaseline.fullWeightBasisPoints - weightBasisPoints
        }

        let effectiveStack = representativeStack(for: key.stackBucket)
        let built = DecisionScenario(
            id: id,
            title: "对照场景 \(id)",
            abilityDimension: template.abilityDimension,
            curriculumNodeID: template.curriculumNodeID,
            heroSeatOffsetFromButton: key.heroSeatOffsetFromButton,
            facing: key.facing,
            heroCards: [
                Card(rank: handClass.highRank, suit: .spades),
                Card(rank: handClass.lowRank, suit: .hearts),
            ],
            board: board(for: key.street),
            decision: BettingDecisionContext(
                pot: BBAmount(centiBB: 150),
                effectiveStack: effectiveStack,
                amountToCall: BBAmount(centiBB: 100),
                minimumRaiseTo: BBAmount(centiBB: 200),
                configuredBetSizes: []
            ),
            options: template.options,
            rangeCells: [
                RangeCell(handClass: handClass.description, actionWeightsBasisPoints: weights),
            ],
            assumptions: template.assumptions,
            explanation: template.explanation
        )
        XCTAssertEqual(
            built.spotCoverageKey,
            key,
            "夹具场景的覆盖键不是要覆盖的那个局面"
        )
        return built
    }

    /// An effective stack that lands squarely inside the given bucket.
    private static func representativeStack(for bucket: StackBucket) -> BBAmount {
        switch bucket {
        case .short: BBAmount(centiBB: 1_000)
        case .medium: BBAmount(centiBB: 4_000)
        case .deep: BBAmount(centiBB: 10_000)
        case .veryDeep: BBAmount(centiBB: 15_000)
        }
    }

    /// A board of the size a street has, in a suit the spade/heart hero cards
    /// never collide with.
    private static func board(for street: Street) -> [Card] {
        let pool = [
            Card(rank: .two, suit: .clubs),
            Card(rank: .three, suit: .clubs),
            Card(rank: .four, suit: .clubs),
            Card(rank: .five, suit: .clubs),
            Card(rank: .six, suit: .clubs),
        ]
        switch street {
        case .preflop: return []
        case .flop: return Array(pool.prefix(3))
        case .turn: return Array(pool.prefix(4))
        case .river: return Array(pool.prefix(5))
        }
    }
}

extension ObservedHand {
    /// Parses `text` as a clean PokerStars hand for a test, failing the test
    /// rather than returning an optional when the text does not parse cleanly.
    static func parsed(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> ObservedHand {
        switch PokerStarsParser.parse(text) {
        case let .parsed(hand, conflicts):
            XCTAssertTrue(conflicts.isEmpty, "夹具应当干净解析，冲突：\(conflicts)", file: file, line: line)
            return hand
        case let .unsupported(reason, sourceLine):
            XCTFail("夹具应当被支持，实际：\(reason) @\(sourceLine)", file: file, line: line)
            throw NSError(domain: "HandLabContentFixture", code: 1)
        }
    }
}
