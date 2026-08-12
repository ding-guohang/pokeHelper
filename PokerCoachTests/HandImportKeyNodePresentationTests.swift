import HandHistory
import PokerCore
import XCTest
@testable import PokerCoach

/// The pure mapping from selected key nodes to display rows.
///
/// The screen has no arithmetic of its own: a deviation shows the covering
/// range's own weight (the complement of the magnitude analysis found) and the
/// departure, an all-in with no weight to compare says "无内容可对照", and the
/// street, position and hero line are read straight off the signature. No EV,
/// no score — an imported hand is not a training answer.
final class HandImportKeyNodePresentationTests: XCTestCase {
    private func signature(
        street: Street,
        offset: Int,
        handClass: String,
        kind: ActionKind,
        amountCentiBB: Int?,
        isAllIn: Bool
    ) -> HeroDecisionSignature {
        HeroDecisionSignature(
            street: street,
            actionIndexInStreet: 0,
            signature: SpotSignature(
                street: street,
                heroSeatOffsetFromButton: offset,
                handClass: HandClass(notation: handClass)!,
                facing: .unopened,
                stackBucket: .deep
            ),
            action: ObservedAction(seat: 1, kind: kind, amountCentiBB: amountCentiBB),
            isAllIn: isAllIn
        )
    }

    // GIVEN 一个满幅度偏离的翻前节点
    // WHEN 映射为展示行
    // THEN 街/位/行动如实呈现，内容频率 0%、偏离 100%
    func testFullMagnitudeDeviationShowsZeroFrequencyAndFullDeparture() {
        let node = KeyNode(
            signature: signature(
                street: .preflop, offset: 0, handClass: "32o",
                kind: .raiseTo, amountCentiBB: 300, isAllIn: false
            ),
            reason: .deviation,
            deviationMagnitude: 10_000,
            coveringScenarioID: "rfi-btn"
        )

        let presentation = HandImportKeyNodePresentation(keyNodes: [node], tableSize: 6)
        let row = try? XCTUnwrap(presentation.rows.first)

        XCTAssertEqual(presentation.rows.count, 1)
        XCTAssertEqual(row?.street, "翻前")
        XCTAssertEqual(row?.position, "BTN")
        XCTAssertEqual(row?.heroAction, "加注至 3 BB")
        XCTAssertEqual(row?.reasonLabel, "偏离")
        XCTAssertEqual(row?.isDeviation, true)
        XCTAssertEqual(row?.comparison, .covered(contentFrequency: "0%", deviation: "100%"))
    }

    // GIVEN 一个部分偏离节点（幅度 3766，权重 6234）
    // WHEN 映射
    // THEN 频率与偏离都以修剪后的百分比呈现，权重是幅度的补
    func testPartialDeviationRendersTrimmedPercentages() {
        let node = KeyNode(
            signature: signature(
                street: .preflop, offset: 3, handClass: "KJo",
                kind: .raiseTo, amountCentiBB: 250, isAllIn: false
            ),
            reason: .deviation,
            deviationMagnitude: 3_766,
            coveringScenarioID: "rfi-utg"
        )

        let presentation = HandImportKeyNodePresentation(keyNodes: [node], tableSize: 6)
        XCTAssertEqual(
            presentation.rows.first?.comparison,
            .covered(contentFrequency: "62.34%", deviation: "37.66%")
        )
    }

    // GIVEN 一个全下节点，没有可对照的权重
    // WHEN 映射
    // THEN 理由为全下，对照为“无内容可对照”，不编造频率
    func testAllInWithoutWeightIsUncovered() {
        let node = KeyNode(
            signature: signature(
                street: .turn, offset: 0, handClass: "AKo",
                kind: .bet, amountCentiBB: 9_300, isAllIn: true
            ),
            reason: .allIn,
            deviationMagnitude: nil,
            coveringScenarioID: nil
        )

        let presentation = HandImportKeyNodePresentation(keyNodes: [node], tableSize: 6)
        let row = presentation.rows.first

        XCTAssertEqual(row?.reasonLabel, "全下")
        XCTAssertEqual(row?.isDeviation, false)
        XCTAssertEqual(row?.comparison, .uncovered)
        XCTAssertEqual(row?.street, "转牌")
        XCTAssertEqual(row?.heroAction, "下注 93 BB")
    }

    func testEmptySelectionMapsToNoRows() {
        XCTAssertTrue(
            HandImportKeyNodePresentation(keyNodes: [], tableSize: 6).rows.isEmpty
        )
    }
}
