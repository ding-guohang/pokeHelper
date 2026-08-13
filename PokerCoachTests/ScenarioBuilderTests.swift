import Foundation
import HandHistory
import HandHistoryPersistence
import PokerCore
import StrategyContent
import TrainingDomain
import XCTest
@testable import PokerCoach

/// The manual scenario builder classifies a hand-built spot and, when content
/// covers it, offers the same remediation drill an imported deviation would.
///
/// A covered spot exposes the covering scenario's ID for "练这个漏洞"; an
/// uncovered spot exposes none, and there is nothing to train against.
final class ScenarioBuilderTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    @MainActor
    private func makeViewModel(
        matcher: ImportedHandContentMatcher
    ) throws -> ScenarioBuilderViewModel {
        let provider = InMemoryStrategyPackProvider(
            pack: try DecisionSessionFixture.makePack()
        )
        return ScenarioBuilderViewModel(
            matcher: matcher,
            store: try FileConstructedSpotStore(directory: temporaryDirectory()),
            makeRemediationSession: { scenarioID in
                DecisionSessionViewModel(
                    scenarioID: scenarioID,
                    strategyProvider: provider,
                    scorer: DecisionScorer(),
                    eventStore: InMemoryTrainingEventStore(),
                    localUserID: UUID(),
                    deviceID: UUID()
                )
            }
        )
    }

    /// The BTN open the builder's inputs describe, so a test can pin the exact
    /// coverage key the fixture content must cover.
    private func btnOpenSpot() throws -> ConstructedSpot {
        try ConstructedSpot(
            heroSeatOffsetFromButton: 0,
            holeCardCodes: ["Ah", "Kh"],
            facing: .unopened,
            effectiveStackCentiBB: 10_000,
            action: .raise(to: BBAmount(centiBB: 250))
        )
    }

    // GIVEN 装入覆盖该构造 spot 的内容
    // WHEN 构造该 spot
    // THEN 暴露补救 scenarioID == 覆盖场景
    @MainActor
    func testCoveredSpotExposesTheCoveringScenarioForRemediation() throws {
        let signature = try btnOpenSpot().signature()
        let scenario = try HandLabContentFixture.scenario(
            id: "covers-constructed-btn",
            covering: signature.coverageKey,
            handClass: signature.handClass,
            actionKey: RangeBaseline.raiseKey,
            weightBasisPoints: 6_234
        )
        let viewModel = try makeViewModel(
            matcher: ImportedHandContentMatcher(scenarios: [scenario])
        )
        viewModel.heroSeatOffsetFromButton = 0
        viewModel.firstCardCode = "Ah"
        viewModel.secondCardCode = "Kh"
        viewModel.facing = .unopened
        viewModel.effectiveStackBB = 100
        viewModel.actionVerb = .raise
        viewModel.actionToBB = 2.5

        viewModel.build()

        XCTAssertNil(viewModel.validationError)
        XCTAssertEqual(viewModel.coverage, .covered(scenarioID: "covers-constructed-btn", weightBasisPoints: 6_234))
        XCTAssertEqual(viewModel.remediationScenarioID, "covers-constructed-btn")
        XCTAssertNotNil(viewModel.remediationSession())
    }

    // GIVEN 内容为空
    // WHEN 构造同一 spot
    // THEN uncovered，不暴露补救、无训练
    @MainActor
    func testUncoveredSpotExposesNoRemediation() throws {
        let viewModel = try makeViewModel(
            matcher: ImportedHandContentMatcher(scenarios: [])
        )
        viewModel.heroSeatOffsetFromButton = 0
        viewModel.firstCardCode = "Ah"
        viewModel.secondCardCode = "Kh"
        viewModel.facing = .unopened
        viewModel.effectiveStackBB = 100
        viewModel.actionVerb = .raise

        viewModel.build()

        XCTAssertEqual(viewModel.coverage, .uncovered)
        XCTAssertNil(viewModel.remediationScenarioID)
        XCTAssertNil(viewModel.remediationSession())
    }

    // GIVEN 非法输入（同一张牌两次）
    // WHEN 构造
    // THEN 暴露对应校验错误、无覆盖结果
    @MainActor
    func testInvalidInputSurfacesTheValidationError() throws {
        let viewModel = try makeViewModel(
            matcher: ImportedHandContentMatcher(scenarios: [])
        )
        viewModel.firstCardCode = "Ah"
        viewModel.secondCardCode = "Ah"

        viewModel.build()

        XCTAssertEqual(viewModel.validationError, .duplicateCards)
        XCTAssertNil(viewModel.coverage)
    }
}
