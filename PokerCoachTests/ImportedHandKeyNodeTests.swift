import Foundation
import HandHistory
import PokerCore
import StrategyContent
import XCTest
@testable import PokerCoach

/// Which imported hero decisions are surfaced for review, and why.
///
/// A covered line the range rarely takes is a deviation; committing the whole
/// stack is an all-in. Deviations sort first and by magnitude, at most five are
/// kept, and a hand with nothing worth reviewing yields nothing.
final class ImportedHandKeyNodeTests: XCTestCase {
    @MainActor
    private func shippedMatcher() throws -> ImportedHandContentMatcher {
        let installed = try BundledContentLoader(bundle: .main).loadPreferredPack()
        return ImportedHandContentMatcher(scenarios: installed.pack.scenarios)
    }

    @MainActor
    private func keyNodes(
        of text: String,
        matcher: ImportedHandContentMatcher
    ) throws -> (signatures: [HeroDecisionSignature], nodes: [KeyNode]) {
        let signatures = try ObservedHand.parsed(text).heroDecisionSignatures()
        XCTAssertFalse(signatures.isEmpty, "夹具应产出英雄决策签名")
        let classified = signatures.map { ($0, matcher.classify($0)) }
        return (signatures, selectKeyNodes(classified))
    }

    // GIVEN 附录 G 英雄 BTN 用 32o 开池、附录 A 用 AKo 开池，装入随包内容
    // WHEN 选关键节点
    // THEN 32o 翻前标偏离且幅度 10000；AKo 翻前不标偏离（成对）
    @MainActor
    func testTrashOpenIsADeviationAndAKoOpenIsNot() throws {
        let matcher = try shippedMatcher()

        // 32o has no cell in the shipped rfi-btn range, so opening it looks up as
        // weight 0 — a full-magnitude deviation.
        let trash = try keyNodes(of: HandImportFixtureText.btnOpenTrash, matcher: matcher)
        let trashPreflop = try XCTUnwrap(trash.signatures.first)
        XCTAssertEqual(trashPreflop.signature.handClass, HandClass(notation: "32o"))
        let trashNode = try XCTUnwrap(
            trash.nodes.first { $0.signature == trashPreflop },
            "32o 开池应入选关键节点"
        )
        XCTAssertEqual(trashNode.reason, .deviation)
        XCTAssertEqual(trashNode.deviationMagnitude, 10_000)

        // AKo is a full-weight open in the same range, so appendix A's preflop is
        // not a deviation and, with no all-in either, yields no key nodes.
        let clean = try keyNodes(of: HandImportFixtureText.appendixA, matcher: matcher)
        let cleanPreflop = try XCTUnwrap(clean.signatures.first)
        XCTAssertEqual(cleanPreflop.signature.handClass, HandClass(notation: "AKo"))
        XCTAssertEqual(
            matcher.classify(cleanPreflop),
            .covered(scenarioID: "rfi-btn", weightBasisPoints: 10_000)
        )
        XCTAssertFalse(
            clean.nodes.contains { $0.signature == cleanPreflop && $0.reason == .deviation },
            "AKo 满权重开池不应被标为偏离"
        )
        XCTAssertTrue(clean.nodes.isEmpty, "附录 A 对随包内容无可复盘节点")
    }

    // GIVEN 附录 H 英雄某决策投入达起始筹码
    // WHEN 选关键节点
    // THEN 该全下节点入选、理由 allIn，依据是投入==起始筹码而非文本
    @MainActor
    func testAllInDecisionIsSelected() throws {
        let matcher = try shippedMatcher()
        let result = try keyNodes(of: HandImportFixtureText.heroAllIn, matcher: matcher)

        let allInSignature = try XCTUnwrap(
            result.signatures.first { $0.isAllIn },
            "附录 H 应有一个投入达起始筹码的决策"
        )
        let allInNode = try XCTUnwrap(
            result.nodes.first { $0.signature == allInSignature },
            "全下决策应入选关键节点"
        )
        XCTAssertEqual(allInNode.reason, .allIn)
        XCTAssertTrue(allInNode.signature.isAllIn, "入选依据是投入达起始筹码这一事实")
    }

    // GIVEN 附录 G 从 BTN 用 32o 开池、附录 I 从 CO 用 32o 开池，装入随包内容
    // WHEN 选关键节点
    // THEN 各自偏离节点保留其覆盖场景：G 为 "rfi-btn"、I 为 "rfi-co"，且两者不同
    //
    // 覆盖场景来自分析判定的那个场景本身——把它写死成常量会让附录 I 断言变红。
    @MainActor
    func testDeviationRetainsItsCoveringScenarioID() throws {
        let matcher = try shippedMatcher()

        let btn = try keyNodes(of: HandImportFixtureText.btnOpenTrash, matcher: matcher)
        let btnPreflop = try XCTUnwrap(btn.signatures.first)
        let btnNode = try XCTUnwrap(
            btn.nodes.first { $0.signature == btnPreflop && $0.reason == .deviation },
            "附录 G 的 32o BTN 开池应是偏离节点"
        )
        XCTAssertEqual(btnNode.coveringScenarioID, "rfi-btn")

        let co = try keyNodes(of: HandImportFixtureText.coOpenTrash, matcher: matcher)
        let coPreflop = try XCTUnwrap(co.signatures.first)
        XCTAssertEqual(coPreflop.signature.handClass, HandClass(notation: "32o"))
        let coNode = try XCTUnwrap(
            co.nodes.first { $0.signature == coPreflop && $0.reason == .deviation },
            "附录 I 的 32o CO 开池应是偏离节点"
        )
        XCTAssertEqual(coNode.coveringScenarioID, "rfi-co")

        XCTAssertNotEqual(
            btnNode.coveringScenarioID,
            coNode.coveringScenarioID,
            "BTN 与 CO 开池必须覆盖到不同的场景"
        )
    }

    // GIVEN 附录 H 的全下节点
    // WHEN 选关键节点
    // THEN 其 coveringScenarioID 为 nil：全下不来自被覆盖的范围表
    @MainActor
    func testAllInHasNoCoveringScenarioID() throws {
        let matcher = try shippedMatcher()
        let result = try keyNodes(of: HandImportFixtureText.heroAllIn, matcher: matcher)

        let allInNode = try XCTUnwrap(
            result.nodes.first { $0.reason == .allIn },
            "附录 H 应有一个全下节点"
        )
        XCTAssertNil(allInNode.coveringScenarioID)
    }

    // GIVEN 附录 A + 空内容
    // WHEN 选关键节点
    // THEN 为空
    @MainActor
    func testNoContentAndNoAllInYieldsNoKeyNodes() throws {
        let matcher = ImportedHandContentMatcher(scenarios: [])
        let result = try keyNodes(of: HandImportFixtureText.appendixA, matcher: matcher)
        XCTAssertTrue(result.nodes.isEmpty, "空内容且无全下应无关键节点")
    }

    /// A hero decision on `handClass`, used only to give `selectKeyNodes` a
    /// distinct signature to attach each covered deviation to. The situation is
    /// arbitrary — the cap and ordering depend on the `NodeCoverage` weights, not
    /// on how these signatures were produced.
    private func decision(handClass notation: String) throws -> HeroDecisionSignature {
        let handClass = try XCTUnwrap(HandClass(notation: notation))
        return HeroDecisionSignature(
            street: .preflop,
            actionIndexInStreet: 0,
            signature: SpotSignature(
                street: .preflop,
                heroSeatOffsetFromButton: 0,
                handClass: handClass,
                facing: .unopened,
                stackBucket: .deep
            ),
            action: ObservedAction(seat: 1, kind: .raiseTo, amountCentiBB: 300),
            isAllIn: false
        )
    }

    // GIVEN 6 个被覆盖且低权重（各不相同）的决策，直接喂给 selectKeyNodes
    // WHEN 选关键节点
    // THEN 恰 5 个（上界）、全为 deviation、按偏离幅度降序，最小幅度（最高权重）被丢弃
    //
    // 覆盖能力停留在 selectKeyNodes 这一层，不再经过 matcher.classify —— 关键节点的
    // 上界与排序只取决于收到的 NodeCoverage 权重。翻后现已一律 uncovered，无法再靠
    // 单手多街的翻后覆盖凑出 6 个偏离，因此在此直接构造 6 个 .covered 元组。
    @MainActor
    func testSixDeviationsAreCappedAtFiveMagnitudeDescending() throws {
        // Six distinct sub-threshold weights → six deviations with six distinct
        // magnitudes (magnitude = 10,000 - weight, strictly decreasing in weight).
        let weights = [500, 1_000, 1_500, 2_000, 2_500, 3_000]
        let notations = ["AKo", "AQo", "AJo", "ATo", "A9o", "A8o"]
        var classified: [(HeroDecisionSignature, NodeCoverage)] = []
        for (index, weight) in weights.enumerated() {
            XCTAssertLessThan(
                weight,
                importedHandDeviationWeightThresholdBasisPoints,
                "每个权重都必须低于偏离阈值，否则不算偏离"
            )
            classified.append((
                try decision(handClass: notations[index]),
                .covered(scenarioID: "six-\(index)", weightBasisPoints: weight)
            ))
        }

        let nodes = selectKeyNodes(classified)

        // Cap: six deviations in, exactly five out.
        XCTAssertEqual(nodes.count, 5, "上界为 5")
        XCTAssertTrue(nodes.allSatisfy { $0.reason == .deviation }, "全部应为偏离")

        // Ordering: magnitude descending.
        let magnitudes = nodes.map { $0.deviationMagnitude }
        XCTAssertEqual(
            magnitudes,
            [9_500, 9_000, 8_500, 8_000, 7_500],
            "应按偏离幅度降序保留前五"
        )

        // The dropped one is the smallest magnitude, i.e. the highest weight
        // (3,000 → magnitude 7,000): the least-departing deviation is cut, not
        // the largest.
        let droppedMagnitude = deviationMagnitude(weightBasisPoints: 3_000)
        XCTAssertEqual(droppedMagnitude, 7_000)
        XCTAssertFalse(
            nodes.contains { $0.deviationMagnitude == droppedMagnitude },
            "被丢弃的应是最小幅度（最高权重）的偏离"
        )
    }
}
