import Foundation
import StrategyContent
import Testing
@testable import TrainingDomain

@Suite("节点掌握判定")
struct NodeMasteryTests {
    private let evaluator = MasteryEvaluator()

    private func evaluate(_ events: [TrainingEvent]) -> NodeMastery {
        evaluator.evaluate(
            nodeID: MasteryFixture.nodeID,
            events: events,
            pack: MasteryFixture.pack()
        )
    }

    // GIVEN 20 次作答、最近 10 次达标、verySure 全达标、2 次复练通过
    // WHEN 在 3 个未作答过的 scenario ID 上均达标
    // THEN mastered，且五项信号带实际值
    //
    // This is the only scenario that can fail an implementation returning a
    // constant false. Written and observed failing first, against a skeleton
    // that did exactly that, because the five negative cases below all pass
    // against such a skeleton.
    @Test("五项信号齐备时判定掌握")
    func marksMasteredWhenEverySignalHolds() throws {
        let mastery = evaluate(MasteryFixture.allSignalsSatisfied())

        #expect(mastery.isMastered)
        #expect(mastery.signals.count == 5)
        #expect(mastery.signal(.sample).actual == 20)
        #expect(mastery.signal(.sample).required == 20)
        #expect(mastery.signal(.recentStability).actual == 10)
        #expect(mastery.signal(.recentStability).required == 9)
        #expect(mastery.signal(.repetition).actual == 2)
        #expect(mastery.signal(.repetition).required == 2)
        #expect(mastery.signal(.transfer).actual == 3)
        #expect(mastery.signal(.transfer).required == 3)
        #expect(mastery.signals.allSatisfy { $0.satisfied })
    }

    @Test("样本不足不判定掌握")
    func withholdsMasteryWhenSampleIsShort() throws {
        let mastery = evaluate(MasteryFixture.allSignalsSatisfied(sampleCount: 4))

        #expect(mastery.isMastered == false)
        #expect(mastery.signal(.sample).actual == 4)
        #expect(mastery.signal(.sample).required == 20)
        #expect(mastery.signal(.sample).satisfied == false)
    }

    @Test("近期稳定性不足不判定掌握")
    func withholdsMasteryWhenRecentStabilityIsShort() throws {
        let mastery = evaluate(
            MasteryFixture.allSignalsSatisfied(recentFailureCount: 3)
        )

        #expect(mastery.isMastered == false)
        #expect(mastery.signal(.recentStability).actual == 7)
        #expect(mastery.signal(.recentStability).required == 9)
        #expect(mastery.signal(.sample).satisfied)
    }

    @Test("高信心错误阻止掌握")
    func withholdsMasteryOnAHighConfidenceError() throws {
        let mastery = evaluate(
            MasteryFixture.allSignalsSatisfied(
                highConfidenceErrorInRecentWindow: true
            )
        )

        #expect(mastery.isMastered == false)
        #expect(mastery.signal(.confidenceCalibration).satisfied == false)
        // Nine of the last ten still pass, so this must be the calibration
        // signal failing and not stability failing by accident.
        #expect(mastery.signal(.recentStability).satisfied)
    }

    @Test("复练未完成不判定掌握")
    func withholdsMasteryWhenRepetitionIsIncomplete() throws {
        let mastery = evaluate(
            MasteryFixture.allSignalsSatisfied(completedRepetitions: 1)
        )

        #expect(mastery.isMastered == false)
        #expect(mastery.signal(.repetition).actual == 1)
        #expect(mastery.signal(.repetition).required == 2)
    }

    @Test("迁移未通过不判定掌握")
    func withholdsMasteryWhenTransferFails() throws {
        let mastery = evaluate(
            MasteryFixture.allSignalsSatisfied(transferPassCount: 2)
        )

        #expect(mastery.isMastered == false)
        #expect(mastery.signal(.transfer).actual == 2)
        #expect(mastery.signal(.transfer).required == 3)
    }

    // 「查看未掌握原因」要求五项逐行可读，不是一个笼统结论。
    @Test("五项信号按固定顺序逐项可读")
    func exposesEverySignalInAFixedOrder() throws {
        let mastery = evaluate(MasteryFixture.allSignalsSatisfied(sampleCount: 4))

        #expect(mastery.signals.map { $0.kind } == [
            .sample,
            .recentStability,
            .confidenceCalibration,
            .repetition,
            .transfer,
        ])
        // Calibration's requirement is "every very-sure answer in the window
        // passed", so its required value is legitimately zero when the user
        // never claimed to be sure. The other four always carry a threshold.
        for kind in [MasterySignal.Kind.sample, .recentStability, .repetition, .transfer] {
            #expect(mastery.signal(kind).required > 0, "\(kind) 没有给出要求值")
        }
        #expect(mastery.signal(.confidenceCalibration).satisfied)
    }

    @Test("没有任何作答的节点未掌握")
    func reportsAnUntouchedNodeAsUnmastered() throws {
        let mastery = evaluate([])

        #expect(mastery.isMastered == false)
        #expect(mastery.signals.allSatisfy { $0.actual == 0 })
        // Calibration and repetition are vacuously satisfied here: nobody
        // claimed certainty, and nothing has been failed, so there is neither
        // miscalibration nor anything to consolidate. The three counted signals
        // are what must be unmet.
        for kind in [MasterySignal.Kind.sample, .recentStability, .transfer] {
            #expect(mastery.signal(kind).satisfied == false)
        }
        #expect(mastery.signal(.confidenceCalibration).satisfied)
        #expect(mastery.signal(.repetition).required == 0)
    }

    // Mastery is read off the deduplicated event set, so it must not depend on
    // the order those events happen to sit in locally.
    @Test("事件顺序不影响判定")
    func evaluatesIdenticallyRegardlessOfInputOrder() throws {
        let events = MasteryFixture.allSignalsSatisfied()

        #expect(evaluate(events) == evaluate(events.reversed()))
    }

    // Events belonging to another node must not prop up this one's signals.
    @Test("其它节点的事件不计入本节点")
    func ignoresEventsFromOtherNodes() throws {
        let pack = CurriculumFixture.pack(
            scenarios: [("s-000", "turn-barrel"), ("other-1", "flop-cbet")],
            nodes: [("turn-barrel", []), ("flop-cbet", [])]
        )
        let events = (0 ..< 30).map { index in
            CurriculumFixture.event(
                scenarioID: "other-1",
                quality: .excellent,
                daysAfterEpoch: Double(index)
            )
        }

        let mastery = evaluator.evaluate(
            nodeID: "turn-barrel",
            events: events,
            pack: pack
        )

        #expect(mastery.signal(.sample).actual == 0)
        #expect(mastery.isMastered == false)
    }
}

@Suite("掌握判定的内容与历史边界")
struct NodeMasteryBoundaryTests {
    private let evaluator = MasteryEvaluator()

    // A user who never makes a mistake had nothing to consolidate, so demanding
    // completed repetitions made flawless play permanently unrewardable.
    @Test("从不犯错的用户也能掌握")
    func aFlawlessHistoryCanReachMastery() throws {
        let pack = MasteryFixture.pack()
        let events = (0 ..< 20).map { index in
            CurriculumFixture.event(
                scenarioID: MasteryFixture.scenarioID(index),
                quality: .excellent,
                daysAfterEpoch: Double(index)
            )
        }

        let mastery = evaluator.evaluate(
            nodeID: MasteryFixture.nodeID,
            events: events,
            pack: pack
        )

        #expect(mastery.signal(.repetition).required == 0)
        #expect(mastery.isMastered)
    }

    // Once a node has been failed the requirement returns.
    @Test("一旦答错过就必须完成复练")
    func afailedNodeStillRequiresRepetitions() throws {
        let mastery = evaluator.evaluate(
            nodeID: MasteryFixture.nodeID,
            events: MasteryFixture.allSignalsSatisfied(completedRepetitions: 0),
            pack: MasteryFixture.pack()
        )

        #expect(mastery.signal(.repetition).required == 2)
        #expect(mastery.isMastered == false)
    }

    // Transfer cannot be demonstrated over more scenarios than a node has, so
    // requiring three of them made a one-scenario node unmasterable forever.
    @Test("迁移要求不超过节点可用场景数")
    func transferRequirementIsCappedByAvailableContent() throws {
        let pack = CurriculumFixture.pack(
            scenarios: [("only-one", "thin-node")],
            nodes: [("thin-node", [])]
        )
        let events = (0 ..< 20).map { index in
            CurriculumFixture.event(
                scenarioID: "only-one",
                quality: .excellent,
                daysAfterEpoch: Double(index)
            )
        }

        let mastery = evaluator.evaluate(
            nodeID: "thin-node",
            events: events,
            pack: pack
        )

        #expect(mastery.signal(.transfer).required == 1)
        #expect(mastery.signal(.transfer).satisfied)
    }
}
