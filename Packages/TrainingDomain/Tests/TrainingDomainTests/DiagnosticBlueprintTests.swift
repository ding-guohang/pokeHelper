import Foundation
import StrategyContent
import Testing
@testable import TrainingDomain

@Suite("初始诊断")
struct DiagnosticBlueprintTests {
    private let blueprint = DiagnosticBlueprint.cash6MaxDefault

    /// A pack wide enough for the blueprint to sample across every axis it
    /// declares: several seats, several streets, two stack depths.
    private func widePack() -> StrategyPack {
        DiagnosticFixture.pack()
    }

    // GIVEN 蓝图声明的能力维度全集为 D
    // WHEN 用户完成全部 12 道题
    // THEN 画像覆盖 D，且题目跨座位、街道与筹码档
    @Test("选题覆盖蓝图声明的采样面")
    func drawsTwelveQuestionsCoveringEveryDeclaredAxis() throws {
        let questions = blueprint.draw(from: widePack())

        #expect(questions.count == 12)
        #expect(Set(questions.map(\.heroSeatOffsetFromButton)).count >= 3)
        #expect(Set(questions.map(\.street)).count >= 3)
        #expect(Set(questions.map(\.effectiveStackCentiBB)).count >= 2)
        #expect(Set(questions.map(\.abilityDimension)) == blueprint.dimensions)
    }

    @Test("题目互不重复")
    func drawsDistinctScenarios() throws {
        let questions = blueprint.draw(from: widePack())

        #expect(Set(questions.map(\.scenarioID)).count == questions.count)
    }

    // Two devices with the same content must offer the same diagnostic, or a
    // resumed session would not line up with the one it resumes.
    @Test("同一内容包两次选题结果相同")
    func drawsDeterministically() throws {
        let pack = widePack()

        #expect(blueprint.draw(from: pack) == blueprint.draw(from: pack))
    }

    // GIVEN 完成前 5 题后退出
    // THEN 进度 5/12，剩余 7 题与已完成的不相交
    @Test("中断后从断点继续")
    func resumesFromTheInterruptionPoint() throws {
        let session = DiagnosticSession(blueprint: blueprint, pack: widePack())
        let answered = Set(session.questions.prefix(5).map(\.scenarioID))

        let resumed = session.resuming(answeredScenarioIDs: answered)

        #expect(resumed.completedCount == 5)
        #expect(resumed.totalCount == 12)
        #expect(resumed.remaining.count == 7)
        #expect(Set(resumed.remaining.map(\.scenarioID)).isDisjoint(with: answered))
        #expect(resumed.isComplete == false)
    }

    // Restarting from scratch would also satisfy "no repeats" if the fresh
    // draw happened to avoid the answered five, so progress is asserted too.
    @Test("恢复后再答完剩余题目即结束")
    func finishesAfterTheRemainingQuestions() throws {
        let session = DiagnosticSession(blueprint: blueprint, pack: widePack())
        let all = Set(session.questions.map(\.scenarioID))

        let resumed = session.resuming(answeredScenarioIDs: all)

        #expect(resumed.completedCount == 12)
        #expect(resumed.remaining.isEmpty)
        #expect(resumed.isComplete)
    }

    // Answers to scenarios outside the diagnostic must not count as progress.
    @Test("非诊断题目不计入进度")
    func ignoresAnswersToScenariosOutsideTheDiagnostic() throws {
        let session = DiagnosticSession(blueprint: blueprint, pack: widePack())

        let resumed = session.resuming(answeredScenarioIDs: ["not-in-diagnostic"])

        #expect(resumed.completedCount == 0)
        #expect(resumed.remaining.count == 12)
    }

    // GIVEN 内容不足以铺满蓝图
    // THEN 诊断仍然可用，只是题目更少，而不是崩溃或空手而归
    @Test("内容不足时缩短诊断而不是失败")
    func shortensTheDiagnosticWhenContentIsThin() throws {
        let questions = blueprint.draw(from: DiagnosticFixture.thinPack())

        #expect(questions.isEmpty == false)
        #expect(questions.count < 12)
        #expect(Set(questions.map(\.scenarioID)).count == questions.count)
    }

    // GIVEN 用户跳过诊断
    // THEN 今日计划非空，且各项分属互不相同的维度
    @Test("跳过诊断时用均衡先验")
    func fallsBackToABalancedPriorWhenSkipped() throws {
        let plan = TrainingPlanner().makePlan(
            profile: PlayerProfile(abilities: [:]),
            catalog: DiagnosticFixture.catalog(),
            now: CurriculumFixture.epoch
        )

        #expect(plan.items.isEmpty == false)
        #expect(Set(plan.items.map(\.abilityDimension)).count == plan.items.count)
    }

    // 收敛的可观测代理：某维度连续三次 blunder 后，它排到计划第一位。
    @Test("作答后真实历史压过先验")
    func realHistoryOverridesThePriorAfterRepeatedFailure() throws {
        let events = (0 ..< 3).map { index in
            CurriculumFixture.event(
                abilityDimension: "turn-barrel",
                quality: .blunder,
                confidence: .verySure,
                daysAfterEpoch: Double(index)
            )
        }
        let profile = PlayerModelReducer().reduce(events: events)

        let plan = TrainingPlanner().makePlan(
            profile: profile,
            catalog: DiagnosticFixture.catalog(),
            now: CurriculumFixture.epoch.addingTimeInterval(3 * 86_400)
        )

        #expect(plan.items[0].abilityDimension == "turn-barrel")
    }
}
