import Foundation
import HandHistory
import PokerCore
import StrategyContent
import TrainingDomain
import XCTest
@testable import PokerCoach

/// A remediation drill is the ordinary training flow, so the event it records is
/// a plain training event.
///
/// Starting the covering scenario through the remediation bridge and starting
/// the same scenario directly produce events that agree on every meaningful
/// field — scenario, content version, ability dimension, submission and the full
/// grade — and differ only in the three fields any two independent answers
/// differ in: their id, their timestamp and the device they were taken on. The
/// ability profile therefore cannot tell a remediation answer from a direct one,
/// which is the point: the imported hand chose *which* spot to drill, not *how*
/// it is scored or stored.
final class HandRemediationEventTests: XCTestCase {
    private let localUserID = UUID(uuidString: "10000000-0000-0000-0000-0000000000AA")!

    @MainActor
    private func shippedProvider() throws -> (provider: InMemoryStrategyPackProvider, pack: StrategyPack) {
        let installed = try BundledContentLoader(bundle: .main).loadPreferredPack()
        return (InMemoryStrategyPackProvider(pack: installed.pack), installed.pack)
    }

    /// The covering scenario of appendix G's 32o button open, taken from the key
    /// node the analysis selects — the same value a user would reach by tapping
    /// "练这个漏洞", not a literal typed here.
    @MainActor
    private func appendixGRemediationScenarioID(
        matcher: ImportedHandContentMatcher
    ) throws -> String {
        let signatures = try ObservedHand.parsed(HandImportFixtureText.btnOpenTrash)
            .heroDecisionSignatures()
        let nodes = selectKeyNodes(signatures.map { ($0, matcher.classify($0)) })
        let deviation = try XCTUnwrap(
            nodes.first { $0.reason == .deviation },
            "附录 G 应含一个偏离节点"
        )
        return try XCTUnwrap(
            remediationScenarioID(for: deviation),
            "偏离节点应能发起补救"
        )
    }

    @MainActor
    private func makeSession(
        scenarioID: String,
        provider: any StrategyPackProviding,
        store: any TrainingEventStore,
        eventID: UUID,
        occurredAt: Date,
        deviceID: UUID
    ) -> DecisionSessionViewModel {
        DecisionSessionViewModel(
            scenarioID: scenarioID,
            strategyProvider: provider,
            scorer: DecisionScorer(),
            eventStore: store,
            localUserID: localUserID,
            deviceID: deviceID,
            makeEventID: { eventID },
            now: { occurredAt }
        )
    }

    // GIVEN 同一覆盖场景，一个经补救桥发起、一个直接发起，注入固定但各异的 id/时间/设备
    // WHEN 两者提交相同 action+confidence 并完成
    // THEN 事件各 +1；除 id/occurredAt/deviceID 外逐字段相等；补救事件计入该场景维度
    @MainActor
    func testRemediationEventIsIndistinguishableFromADirectTrainingEvent() async throws {
        let (provider, pack) = try shippedProvider()
        let matcher = ImportedHandContentMatcher(scenarios: pack.scenarios)

        let remediationID = try appendixGRemediationScenarioID(matcher: matcher)
        XCTAssertEqual(remediationID, "rfi-btn", "附录 G 的 BTN 开池应被 rfi-btn 覆盖")

        let remediationStore = InMemoryTrainingEventStore()
        let directStore = InMemoryTrainingEventStore()

        let remediationSession = makeSession(
            scenarioID: remediationID,
            provider: provider,
            store: remediationStore,
            eventID: UUID(uuidString: "30000000-0000-0000-0000-0000000000A1")!,
            occurredAt: Date(timeIntervalSince1970: 1_786_000_100),
            deviceID: UUID(uuidString: "20000000-0000-0000-0000-0000000000A1")!
        )
        let directSession = makeSession(
            scenarioID: "rfi-btn",
            provider: provider,
            store: directStore,
            eventID: UUID(uuidString: "30000000-0000-0000-0000-0000000000B2")!,
            occurredAt: Date(timeIntervalSince1970: 1_786_000_200),
            deviceID: UUID(uuidString: "20000000-0000-0000-0000-0000000000B2")!
        )

        await remediationSession.load()
        await directSession.load()
        XCTAssertEqual(remediationSession.state, .answering)
        XCTAssertEqual(directSession.state, .answering)

        // An action that is both a strategy option (so it can be graded) and a
        // legal action (so it can be selected); the two sessions share a scenario
        // so the choice is identical.
        let scenario = try XCTUnwrap(remediationSession.scenario)
        let action = try XCTUnwrap(
            scenario.options
                .map(\.action)
                .first { remediationSession.legalActions.contains($0) },
            "rfi-btn 应有一个既合法又在策略选项中的行动"
        )

        for session in [remediationSession, directSession] {
            session.select(action: action)
            session.setConfidence(.verySure)
            await session.submit()
            session.continueSession()
            XCTAssertEqual(session.state, .completed)
        }

        let remediationEvents = await remediationStore.allEvents()
        let directEvents = await directStore.allEvents()
        XCTAssertEqual(remediationEvents.count, 1, "补救应恰记录一条事件")
        XCTAssertEqual(directEvents.count, 1, "直接训练应恰记录一条事件")

        let remediation = remediationEvents[0]
        let direct = directEvents[0]

        // Structurally identical — compared field by field, deliberately NOT via
        // TrainingEvent.==, which folds id/occurredAt/deviceID into equality.
        XCTAssertEqual(remediation.scenarioID, "rfi-btn")
        XCTAssertEqual(remediation.scenarioID, direct.scenarioID)
        XCTAssertEqual(remediation.strategyPackID, direct.strategyPackID)
        XCTAssertEqual(remediation.strategyContentVersion, direct.strategyContentVersion)
        XCTAssertEqual(remediation.abilityDimension, direct.abilityDimension)
        XCTAssertEqual(remediation.localUserID, direct.localUserID)
        XCTAssertEqual(remediation.submission, direct.submission)

        XCTAssertEqual(remediation.grade.selectedAction, direct.grade.selectedAction)
        XCTAssertEqual(
            remediation.grade.selectedFrequencyBasisPoints,
            direct.grade.selectedFrequencyBasisPoints
        )
        XCTAssertEqual(remediation.grade.selectedEV, direct.grade.selectedEV)
        XCTAssertEqual(remediation.grade.bestEV, direct.grade.bestEV)
        XCTAssertEqual(remediation.grade.evLoss, direct.grade.evLoss)
        XCTAssertEqual(
            remediation.grade.lossRateBasisPoints,
            direct.grade.lossRateBasisPoints
        )
        XCTAssertEqual(remediation.grade.score, direct.grade.score)
        XCTAssertEqual(remediation.grade.quality, direct.grade.quality)
        XCTAssertEqual(
            remediation.grade.isStrategicallyAvailable,
            direct.grade.isStrategicallyAvailable
        )

        // And the only things that differ are the three that any two independent
        // answers differ in.
        XCTAssertNotEqual(remediation.id, direct.id)
        XCTAssertNotEqual(remediation.occurredAt, direct.occurredAt)
        XCTAssertNotEqual(remediation.deviceID, direct.deviceID)

        // The remediation event lands in the covering scenario's ability
        // dimension when reduced, exactly as a direct answer would.
        let profile = PlayerModelReducer().reduce(events: [remediation])
        let dimension = scenario.abilityDimension
        let snapshot = try XCTUnwrap(
            profile[dimension],
            "补救事件应计入场景 \(dimension) 维度"
        )
        XCTAssertEqual(snapshot.sampleCount, 1)
    }
}
