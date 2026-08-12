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

    // GIVEN 附录 A + 空内容
    // WHEN 选关键节点
    // THEN 为空
    @MainActor
    func testNoContentAndNoAllInYieldsNoKeyNodes() throws {
        let matcher = ImportedHandContentMatcher(scenarios: [])
        let result = try keyNodes(of: HandImportFixtureText.appendixA, matcher: matcher)
        XCTAssertTrue(result.nodes.isEmpty, "空内容且无全下应无关键节点")
    }

    // GIVEN 一手英雄有 6 个被覆盖且低权重的决策
    // WHEN 选关键节点
    // THEN 恰 5 个（上界）、按偏离幅度降序
    @MainActor
    func testSixDeviationsAreCappedAtFiveMagnitudeDescending() throws {
        let signatures = try ObservedHand.parsed(HandImportFixtureText.sixDeviations)
            .heroDecisionSignatures()
        XCTAssertEqual(signatures.count, 6, "六偏离夹具应有 6 个英雄决策")

        // A content fixture covering each of the six distinct coverage keys, each
        // with a distinct sub-threshold weight, so all six are deviations with
        // distinct magnitudes and the cap and ordering are both observable.
        var scenarios: [DecisionScenario] = []
        var expectedMagnitudes: [Int] = []
        for (index, signature) in signatures.enumerated() {
            let actionKey = signature.action.kind == .call ? RangeBaseline.callKey : RangeBaseline.raiseKey
            let weight = 500 * (index + 1)
            XCTAssertLessThan(weight, importedHandDeviationWeightThresholdBasisPoints)
            scenarios.append(try HandLabContentFixture.scenario(
                id: "six-\(index)",
                covering: signature.signature.coverageKey,
                handClass: signature.signature.handClass,
                actionKey: actionKey,
                weightBasisPoints: weight
            ))
            expectedMagnitudes.append(deviationMagnitude(weightBasisPoints: weight))
        }
        // The six keys really are distinct, otherwise fewer than six get covered.
        XCTAssertEqual(Set(signatures.map { $0.signature.coverageKey }).count, 6)

        let matcher = ImportedHandContentMatcher(scenarios: scenarios)
        let classified = signatures.map { ($0, matcher.classify($0)) }
        let nodes = selectKeyNodes(classified)

        XCTAssertEqual(nodes.count, 5, "上界为 5")
        XCTAssertTrue(nodes.allSatisfy { $0.reason == .deviation })
        let magnitudes = nodes.map { $0.deviationMagnitude }
        XCTAssertEqual(magnitudes, Array(expectedMagnitudes.sorted(by: >).prefix(5)))
    }
}
