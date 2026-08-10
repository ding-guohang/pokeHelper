import Foundation
import Testing
@testable import TrainingDomain

@Suite("今日计划优先级")
struct TrainingPlanPriorityTests {
    private let planner = TrainingPlanner()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Two dimensions that are identical in every ranking input, so a test can
    /// vary exactly one of them.
    private func tiedProfile(
        highConfidenceErrorsIn dimension: String? = nil
    ) -> PlayerProfile {
        PlayerProfile(abilities: ["alpha", "beta"].reduce(into: [:]) { result, name in
            result[name] = AbilitySnapshot(
                dimension: name,
                sampleCount: 10,
                meanScore: 70,
                meanLossRateBasisPoints: 300,
                highConfidenceErrorCount: name == dimension ? 1 : 0,
                lastPracticedAt: now
            )
        })
    }

    /// Node IDs are deliberately not equal to ability dimensions.
    ///
    /// Shipped content has several nodes per dimension. A fixture that set the
    /// two fields to the same string is why the planner spent a milestone
    /// comparing one namespace against the other with every test green.
    private static func node(for dimension: String) -> String {
        "node-\(dimension)"
    }

    private func catalog(
        _ entries: [(id: String, dimension: String, minutes: Int)]
    ) -> [TrainingCatalogItem] {
        entries.map {
            TrainingCatalogItem(
                id: $0.id,
                scenarioID: "scenario-\($0.id)",
                abilityDimension: $0.dimension,
                curriculumNodeID: Self.node(for: $0.dimension),
                estimatedMinutes: $0.minutes
            )
        }
    }

    // GIVEN A 与 B 各项相同，A 复练已到期、B 未到期
    // AND A 的 catalog ID 字典序排在 B 之后
    // THEN A 排在 B 之前，且 priority 严格大于 B
    //
    // The catalog IDs are deliberately ordered against the expected result. The
    // planner falls back to ID order on a tie, so an implementation with no
    // due-repetition term at all would still put the "right" item first if the
    // IDs happened to sort that way.
    @Test("到期复练排在未到期项目之前")
    func dueRepetitionOutranksAnIdenticalItemThatIsNotDue() throws {
        let plan = planner.makePlan(
            profile: tiedProfile(),
            catalog: catalog([
                (id: "z-due", dimension: "alpha", minutes: 5),
                (id: "a-not-due", dimension: "beta", minutes: 5),
            ]),
            dueRepetitionNodeIDs: [Self.node(for: "alpha")],
            now: now
        )

        #expect(plan.items.map { $0.id } == ["z-due", "a-not-due"])
        #expect(plan.items[0].priority > plan.items[1].priority)
    }

    // GIVEN A 有高信心错误但复练未到期，B 无高信心错误但复练已到期
    // THEN A 排在 B 之前
    @Test("高信心错误压过复练到期")
    func highConfidenceErrorOutranksADueRepetition() throws {
        let plan = planner.makePlan(
            profile: tiedProfile(highConfidenceErrorsIn: "alpha"),
            catalog: catalog([
                (id: "alpha-item", dimension: "alpha", minutes: 5),
                (id: "beta-item", dimension: "beta", minutes: 5),
            ]),
            dueRepetitionNodeIDs: [Self.node(for: "beta")],
            now: now
        )

        #expect(plan.items[0].id == "alpha-item")
        #expect(plan.items[0].priority > plan.items[1].priority)
    }

    // GIVEN 四个画像，各自只具备一种入选依据
    // THEN 首项原因依次为四个不同的枚举值
    @Test("每个计划项给出被选中的原因")
    func reportsWhyEachItemWasChosen() throws {
        func firstReason(
            meanScore: Int,
            highConfidenceErrorCount: Int = 0,
            due: Bool = false,
            onPath: Bool = false
        ) -> PlanItemReason? {
            let profile = PlayerProfile(abilities: [
                "alpha": AbilitySnapshot(
                    dimension: "alpha",
                    sampleCount: 10,
                    meanScore: meanScore,
                    meanLossRateBasisPoints: 0,
                    highConfidenceErrorCount: highConfidenceErrorCount,
                    lastPracticedAt: now
                ),
            ])
            return planner.makePlan(
                profile: profile,
                catalog: catalog([(id: "alpha-item", dimension: "alpha", minutes: 5)]),
                dueRepetitionNodeIDs: due ? [Self.node(for: "alpha")] : [],
                pathDimensions: onPath ? ["alpha"] : [],
                now: now
            ).items.first?.reason
        }

        #expect(firstReason(meanScore: 40) == .weakness)
        #expect(firstReason(meanScore: 100, highConfidenceErrorCount: 1) == .highConfidenceError)
        #expect(firstReason(meanScore: 100, due: true) == .repetitionDue)
        #expect(firstReason(meanScore: 100, onPath: true) == .pathProgress)
    }

    @Test("入选原因在相同输入下保持稳定")
    func reportsTheSameReasonForTheSameInput() throws {
        let profile = tiedProfile(highConfidenceErrorsIn: "alpha")
        let items = catalog([(id: "alpha-item", dimension: "alpha", minutes: 5)])

        let first = planner.makePlan(profile: profile, catalog: items, now: now)
        let second = planner.makePlan(profile: profile, catalog: items, now: now)

        #expect(first == second)
    }

    // GIVEN 目标 5–10 分钟，候选充足
    // THEN 总时长落在区间内，且再加任意一项都会超过上限
    @Test("计划填满时长窗口但不超出上限")
    func fillsTheWindowWithoutOverrunningIt() throws {
        let entries = (0 ..< 8).map {
            (id: "item-\($0)", dimension: "alpha", minutes: 3)
        }
        let candidates = catalog(entries)

        let plan = planner.makePlan(
            profile: tiedProfile(),
            catalog: candidates,
            now: now
        )
        let total = plan.items.map(\.catalogItem.estimatedMinutes).reduce(0, +)

        #expect(total <= 10)
        #expect(total >= 5)
        let selected = Set(plan.items.map(\.id))
        for candidate in candidates where !selected.contains(candidate.id) {
            #expect(
                total + candidate.estimatedMinutes > 10,
                "计划没有填满窗口：还能放下 \(candidate.id)"
            )
        }
    }

    // A single candidate longer than the window is still better than an empty
    // plan: the user opened the app to train.
    @Test("唯一候选超出上限时仍然入选")
    func keepsAnOversizedSoleCandidateRatherThanReturningNothing() throws {
        let plan = planner.makePlan(
            profile: tiedProfile(),
            catalog: catalog([(id: "long", dimension: "alpha", minutes: 25)]),
            now: now
        )

        #expect(plan.items.map { $0.id } == ["long"])
    }

    @Test("空 catalog 得到空计划")
    func returnsAnEmptyPlanWithNoCandidates() throws {
        let plan = planner.makePlan(profile: tiedProfile(), catalog: [], now: now)

        #expect(plan.items.isEmpty)
    }

    // GIVEN 画像 A 中 bet-sizing 最弱、画像 B 中 preflop-range 最弱
    // THEN 两者首项维度不同
    @Test("今日计划来自画像而非用户选择")
    func derivesTheFirstItemFromTheProfile() throws {
        func plan(weakest: String) -> DailyPlan {
            let profile = PlayerProfile(
                abilities: ["bet-sizing", "preflop-range"].reduce(into: [:]) { result, name in
                    result[name] = AbilitySnapshot(
                        dimension: name,
                        sampleCount: 10,
                        meanScore: name == weakest ? 30 : 90,
                        meanLossRateBasisPoints: 0,
                        highConfidenceErrorCount: 0,
                        lastPracticedAt: now
                    )
                }
            )
            return planner.makePlan(
                profile: profile,
                catalog: catalog([
                    (id: "a-bet", dimension: "bet-sizing", minutes: 5),
                    (id: "b-preflop", dimension: "preflop-range", minutes: 5),
                ]),
                now: now
            )
        }

        #expect(plan(weakest: "bet-sizing").items[0].abilityDimension == "bet-sizing")
        #expect(plan(weakest: "preflop-range").items[0].abilityDimension == "preflop-range")
    }
}
