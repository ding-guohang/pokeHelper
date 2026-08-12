import HandHistory
import PokerCore
import XCTest
@testable import PokerCoach

/// The bridge from a reviewed key node to the scenario a remediation drill would
/// run.
///
/// A covered deviation points at the scenario whose range table measured the
/// departure, so the same spot can be practised. An all-in points at nothing —
/// an uncovered commitment has no authored scenario to train against — so it
/// offers no remediation.
final class HandRemediationTests: XCTestCase {
    private func signature(
        handClass: String,
        kind: ActionKind,
        amountCentiBB: Int?,
        isAllIn: Bool
    ) -> HeroDecisionSignature {
        HeroDecisionSignature(
            street: .preflop,
            actionIndexInStreet: 0,
            signature: SpotSignature(
                street: .preflop,
                heroSeatOffsetFromButton: 0,
                handClass: HandClass(notation: handClass)!,
                facing: .unopened,
                stackBucket: .deep
            ),
            action: ObservedAction(seat: 1, kind: kind, amountCentiBB: amountCentiBB),
            isAllIn: isAllIn
        )
    }

    // GIVEN 一个偏离节点，覆盖场景为 "rfi-btn"
    // WHEN 求补救场景
    // THEN 返回该节点的 coveringScenarioID
    func testDeviationRemediatesItsCoveringScenario() {
        let node = KeyNode(
            signature: signature(
                handClass: "32o", kind: .raiseTo, amountCentiBB: 300, isAllIn: false
            ),
            reason: .deviation,
            deviationMagnitude: 10_000,
            coveringScenarioID: "rfi-btn"
        )

        XCTAssertEqual(remediationScenarioID(for: node), "rfi-btn")
    }

    // GIVEN 一个全下节点，没有覆盖场景
    // WHEN 求补救场景
    // THEN 返回 nil：全下不提供补救
    //
    // 恒返回非 nil 的桥会让这条断言变红。
    func testAllInHasNoRemediation() {
        let node = KeyNode(
            signature: signature(
                handClass: "AKo", kind: .bet, amountCentiBB: 9_300, isAllIn: true
            ),
            reason: .allIn,
            deviationMagnitude: nil,
            coveringScenarioID: nil
        )

        XCTAssertNil(remediationScenarioID(for: node))
    }
}
