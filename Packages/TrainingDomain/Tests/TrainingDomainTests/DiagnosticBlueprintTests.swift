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
    //
    // Asserted against a committed sequence, not against a second call in the
    // same process. Swift seeds hashing per process, so `Set`/`Dictionary`
    // iteration order and `hashValue` are stable *within* one run and differ
    // *between* runs — exactly the bug this test exists to catch, and exactly
    // the bug `draw(from:) == draw(from:)` cannot see. This project has been
    // bitten by that three times. The golden below was captured from three
    // separate `swift test` processes that all agreed; a draw that starts
    // depending on hash order will disagree with it on some future run.
    @Test("同一内容包的选题结果与committed序列一致")
    func drawsDeterministically() throws {
        let drawn = blueprint.draw(from: widePack()).map(\.scenarioID)

        #expect(drawn == Self.goldenDraw)
    }

    /// The exact 12 scenario IDs `cash6MaxDefault` draws from
    /// `DiagnosticFixture.pack()`, in order.
    ///
    /// Regenerate deliberately, never by pasting whatever the run printed: a
    /// change here is a change to which diagnostic every existing user resumes
    /// into.
    private static let goldenDraw = [
        "flop-cbet-s0-t0-k0",
        "preflop-range-s1-t1-k1",
        "river-bluff-catch-s2-t2-k0",
        "turn-barrel-s3-t3-k0",
        "flop-cbet-s4-t0-k0",
        "preflop-range-s5-t0-k0",
        "river-bluff-catch-s0-t0-k0",
        "turn-barrel-s0-t0-k0",
        "flop-cbet-s0-t0-k1",
        "preflop-range-s0-t0-k0",
        "river-bluff-catch-s0-t0-k1",
        "turn-barrel-s0-t0-k1",
    ]

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
    //
    // "Balanced" is asserted as a distribution, not as non-emptiness: every
    // declared dimension is present exactly once and every one carries the
    // identical prior priority. A planner that returned one item, or that
    // ranked an unmeasured dimension above another unmeasured one, would pass
    // the old "non-empty, no duplicate dimensions" pair and fail this.
    //
    // 54 is the prior spelled out: an unseen ability scores the baseline 60
    // (weakness 100 - 60 = 40) and is treated as 7 days stale (staleness
    // min(7 * 2, 30) = 14). Pinned as a number so a silent change to either
    // half of the prior is a failure rather than a shrug.
    @Test("跳过诊断时用均衡先验")
    func fallsBackToABalancedPriorWhenSkipped() throws {
        let plan = TrainingPlanner().makePlan(
            profile: PlayerProfile(abilities: [:]),
            catalog: DiagnosticFixture.catalog(),
            now: CurriculumFixture.epoch
        )

        #expect(
            Set(plan.items.map(\.abilityDimension)) == blueprint.dimensions,
            "先验漏掉或多出了维度：\(plan.items.map(\.abilityDimension))"
        )
        #expect(plan.items.count == blueprint.dimensions.count)
        #expect(
            plan.items.map(\.priority) == Array(
                repeating: 54,
                count: blueprint.dimensions.count
            ),
            "先验不再均衡：\(plan.items.map { "\($0.abilityDimension)=\($0.priority)" })"
        )
        #expect(plan.items.allSatisfy { $0.reason == .weakness })
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
