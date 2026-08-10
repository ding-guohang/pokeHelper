import Foundation
import StrategyContent
import Testing
@testable import TrainingDomain

@Suite("复练调度")
struct RepetitionSchedulerTests {
    private let scheduler = RepetitionScheduler()
    private let epoch = CurriculumFixture.epoch

    // GIVEN 某节点首次答错，此前无复练记录
    // THEN intervalDays 为 1，nextDueAt 为次日
    @Test("首次答错后间隔为一天")
    func firstFailureSchedulesOneDayOut() throws {
        let schedule = try #require(
            scheduler.schedule(
                forNode: "turn-barrel",
                events: [CurriculumFixture.event(quality: .blunder, daysAfterEpoch: 0)]
            )
        )

        #expect(schedule.intervalDays == 1)
        #expect(schedule.nextDueAt == epoch.addingTimeInterval(86_400))
    }

    // A node that has never been failed is not in the repetition rotation at
    // all — otherwise every dimension would be "due" forever.
    @Test("从未答错的节点没有复练安排")
    func aNodeThatWasNeverFailedHasNoSchedule() throws {
        #expect(
            scheduler.schedule(
                forNode: "turn-barrel",
                events: [
                    CurriculumFixture.event(quality: .excellent, daysAfterEpoch: 0),
                    CurriculumFixture.event(quality: .acceptable, daysAfterEpoch: 1),
                ]
            ) == nil
        )
    }

    // GIVEN intervalDays 为 3，到期复练得到 acceptable
    // THEN intervalDays 变为 7
    @Test("答对沿阶梯前进")
    func correctRepetitionAdvancesOneRung() throws {
        // fail → 1d → pass (→3) → pass (→7)
        let schedule = try #require(
            scheduler.schedule(
                forNode: "turn-barrel",
                events: [
                    CurriculumFixture.event(quality: .blunder, daysAfterEpoch: 0),
                    CurriculumFixture.event(quality: .acceptable, daysAfterEpoch: 1),
                    CurriculumFixture.event(quality: .acceptable, daysAfterEpoch: 4),
                ]
            )
        )

        #expect(schedule.intervalDays == 7)
        #expect(schedule.nextDueAt == epoch.addingTimeInterval(11 * 86_400))
    }

    // GIVEN intervalDays 为 7，到期复练得到 blunder
    // THEN intervalDays 变为 3
    @Test("答错退一级")
    func incorrectRepetitionFallsBackOneRung() throws {
        let schedule = try #require(
            scheduler.schedule(
                forNode: "turn-barrel",
                events: [
                    CurriculumFixture.event(quality: .blunder, daysAfterEpoch: 0),
                    CurriculumFixture.event(quality: .acceptable, daysAfterEpoch: 1),
                    CurriculumFixture.event(quality: .acceptable, daysAfterEpoch: 4),
                    CurriculumFixture.event(quality: .blunder, daysAfterEpoch: 11),
                ]
            )
        )

        #expect(schedule.intervalDays == 3)
    }

    // Without a floor the interval decays to zero and the same node is served
    // again inside the same session, forever.
    @Test("最低一级答错仍为一天")
    func lowestRungNeverFallsBelowOneDay() throws {
        let schedule = try #require(
            scheduler.schedule(
                forNode: "turn-barrel",
                events: [
                    CurriculumFixture.event(quality: .blunder, daysAfterEpoch: 0),
                    CurriculumFixture.event(quality: .blunder, daysAfterEpoch: 1),
                    CurriculumFixture.event(quality: .blunder, daysAfterEpoch: 2),
                ]
            )
        )

        #expect(schedule.intervalDays == 1)
        #expect(schedule.nextDueAt == epoch.addingTimeInterval(3 * 86_400))
    }

    @Test("阶梯到顶后不再增长")
    func theLadderStopsAtItsTopRung() throws {
        var events = [CurriculumFixture.event(quality: .blunder, daysAfterEpoch: 0)]
        var day = 1.0
        for interval in [1.0, 3, 7, 14, 30, 30, 30] {
            events.append(
                CurriculumFixture.event(quality: .excellent, daysAfterEpoch: day)
            )
            day += interval
        }

        let schedule = try #require(
            scheduler.schedule(forNode: "turn-barrel", events: events)
        )
        #expect(schedule.intervalDays == 30)
    }

    // Practising before the repetition falls due is ordinary practice. Letting
    // it advance the ladder would let a user grind the interval up in one
    // sitting, which is exactly what spacing exists to prevent.
    @Test("未到期的作答不推进阶梯")
    func practiceBeforeTheDueDateDoesNotAdvanceTheLadder() throws {
        let schedule = try #require(
            scheduler.schedule(
                forNode: "turn-barrel",
                events: [
                    CurriculumFixture.event(quality: .blunder, daysAfterEpoch: 0),
                    CurriculumFixture.event(quality: .excellent, daysAfterEpoch: 0.1),
                    CurriculumFixture.event(quality: .excellent, daysAfterEpoch: 0.5),
                ]
            )
        )

        #expect(schedule.intervalDays == 1)
    }

    @Test("事件顺序打乱不改变结果")
    func foldsTheSameWayRegardlessOfInputOrder() throws {
        let events = [
            CurriculumFixture.event(quality: .blunder, daysAfterEpoch: 0),
            CurriculumFixture.event(quality: .acceptable, daysAfterEpoch: 1),
            CurriculumFixture.event(quality: .acceptable, daysAfterEpoch: 4),
        ]

        let forward = scheduler.schedule(forNode: "turn-barrel", events: events)
        let reversed = scheduler.schedule(forNode: "turn-barrel", events: events.reversed())

        #expect(forward == reversed)
    }

    // GIVEN 昨天在 bet-sizing 的 s-101 上 blunder，同日 preflop-range 全对
    // THEN 存在 bet-sizing 复练项且题目不是 s-101，不存在 preflop-range 复练项
    @Test("隔日复练换题且不复练已答对的节点")
    func schedulesADifferentScenarioAndSkipsPassedNodes() throws {
        let pack = CurriculumFixture.pack(
            scenarios: [
                ("s-101", "bet-sizing"),
                ("s-102", "bet-sizing"),
                ("s-201", "preflop-range"),
            ],
            nodes: [("bet-sizing", []), ("preflop-range", [])]
        )
        let events = [
            CurriculumFixture.event(scenarioID: "s-101", quality: .blunder, daysAfterEpoch: 0),
            CurriculumFixture.event(scenarioID: "s-201", quality: .acceptable, daysAfterEpoch: 0),
        ]

        let due = scheduler.dueRepetitions(
            events: events,
            pack: pack,
            now: epoch.addingTimeInterval(86_400)
        )

        let betSizing = try #require(due.first { $0.nodeID == "bet-sizing" })
        #expect(betSizing.scenarioID == "s-102")
        #expect(betSizing.isContentLimited == false)
        #expect(due.contains { $0.nodeID == "preflop-range" } == false)
    }

    // GIVEN bet-sizing 只有 s-101 一个场景且已答错
    // THEN 不出同一题，该节点复练挂起
    @Test("内容不足时挂起而不是重复出题")
    func suspendsRepetitionRatherThanRepeatingTheSameQuestion() throws {
        let pack = CurriculumFixture.pack(
            scenarios: [("s-101", "bet-sizing")],
            nodes: [("bet-sizing", [])]
        )
        let events = [
            CurriculumFixture.event(scenarioID: "s-101", quality: .blunder, daysAfterEpoch: 0),
        ]

        let due = scheduler.dueRepetitions(
            events: events,
            pack: pack,
            now: epoch.addingTimeInterval(86_400)
        )

        let betSizing = try #require(due.first { $0.nodeID == "bet-sizing" })
        #expect(betSizing.scenarioID == nil)
        #expect(betSizing.isContentLimited)
    }

    @Test("未到期的节点不进入今日复练")
    func doesNotSurfaceANodeBeforeItFallsDue() throws {
        let pack = CurriculumFixture.pack(
            scenarios: [("s-101", "bet-sizing"), ("s-102", "bet-sizing")],
            nodes: [("bet-sizing", [])]
        )
        let events = [
            CurriculumFixture.event(scenarioID: "s-101", quality: .blunder, daysAfterEpoch: 0),
        ]

        let due = scheduler.dueRepetitions(
            events: events,
            pack: pack,
            now: epoch.addingTimeInterval(0.5 * 86_400)
        )

        #expect(due.isEmpty)
    }

    @Test("到期节点按到期时间排序")
    func ordersDueNodesByHowLongTheyHaveBeenWaiting() throws {
        let pack = CurriculumFixture.pack(
            scenarios: [
                ("s-101", "bet-sizing"), ("s-102", "bet-sizing"),
                ("s-201", "turn-barrel"), ("s-202", "turn-barrel"),
            ],
            nodes: [("bet-sizing", []), ("turn-barrel", [])]
        )
        let events = [
            CurriculumFixture.event(scenarioID: "s-201", quality: .blunder, daysAfterEpoch: 0),
            CurriculumFixture.event(scenarioID: "s-101", quality: .blunder, daysAfterEpoch: 2),
        ]

        let due = scheduler.dueRepetitions(
            events: events,
            pack: pack,
            now: epoch.addingTimeInterval(5 * 86_400)
        )

        #expect(due.map(\.nodeID) == ["turn-barrel", "bet-sizing"])
    }
}
