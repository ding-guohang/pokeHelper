import Foundation
import HandHistory
import PokerCore
import StrategyContent
import XCTest
@testable import PokerCoach

/// The matcher's construct-side entry: a hand-built preflop spot is judged
/// against installed content the same way an imported hero decision is.
///
/// A `ConstructedSpot` carries only pure poker facts; the app layer asks whether
/// content covers it through `classify(signature:action:)`, the core the
/// observed-hand overload also routes through. A covered spot reports the
/// covering scenario's own range-table weight for the line taken — never a
/// fabricated one — and an uncovered spot reports nothing.
final class ConstructedSpotMatchTests: XCTestCase {
    /// A BTN preflop open that the fixture content covers, holding AKs, 100BB
    /// deep, raising — the same shape a `rfi-btn` scenario teaches.
    private func btnOpenSpot() throws -> ConstructedSpot {
        try ConstructedSpot(
            heroSeatOffsetFromButton: 0,
            holeCardCodes: ["Ah", "Kh"],
            facing: .unopened,
            effectiveStackCentiBB: 10_000,
            action: .raise(to: BBAmount(centiBB: 300))
        )
    }

    // GIVEN 装入覆盖该构造 spot 覆盖键的内容，权重 6234
    // WHEN 判定该构造 spot
    // THEN covered，且权重等于对该场景查表所得（非编造）
    @MainActor
    func testConstructedSpotIsCoveredWithTheRangeTableWeight() throws {
        let spot = try btnOpenSpot()
        let signature = spot.signature()

        // A non-round weight, so a constant-covered stub that always answers
        // 10,000 cannot pass.
        let scenario = try HandLabContentFixture.scenario(
            id: "covers-constructed-btn",
            covering: signature.coverageKey,
            handClass: signature.handClass,
            actionKey: RangeBaseline.raiseKey,
            weightBasisPoints: 6_234
        )
        let matcher = ImportedHandContentMatcher(scenarios: [scenario])

        // The weight is the covering scenario's own table lookup, not a number
        // the matcher invented.
        let expected = scenario.rangeWeightBasisPoints(
            forHandClass: signature.handClass,
            action: spot.action
        )
        XCTAssertEqual(expected, 6_234)
        XCTAssertEqual(
            matcher.classify(signature: signature, action: spot.action),
            .covered(scenarioID: "covers-constructed-btn", weightBasisPoints: 6_234)
        )
    }

    // GIVEN 内容为空
    // WHEN 判定同一构造 spot
    // THEN uncovered（与命中成对，排除恒 covered/恒 uncovered）
    @MainActor
    func testConstructedSpotIsUncoveredWithEmptyContent() throws {
        let spot = try btnOpenSpot()
        let matcher = ImportedHandContentMatcher(scenarios: [])

        XCTAssertEqual(
            matcher.classify(signature: spot.signature(), action: spot.action),
            .uncovered
        )
    }
}
