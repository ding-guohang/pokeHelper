import Foundation
import PokerCore
import Testing
@testable import TrainingDomain

@Suite("训练进度趋势")
struct ProgressTrendTests {
    /// A UTC calendar so day boundaries are deterministic across machines.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func event(occurredAt: Date, score: Int, quality: DecisionQuality) -> TrainingEvent {
        TrainingEvent(
            id: UUID(),
            localUserID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            deviceID: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            occurredAt: occurredAt,
            scenarioID: "scenario-1",
            strategyPackID: "cash-pack",
            strategyContentVersion: "2026.08.06",
            abilityDimension: "bet-sizing",
            submission: DecisionSubmission(action: .check, confidence: .unsure),
            grade: DecisionGrade(
                selectedAction: .check,
                selectedFrequencyBasisPoints: 10_000,
                selectedEV: EVAmount(milliBB: 0),
                bestEV: EVAmount(milliBB: 0),
                evLoss: EVAmount(milliBB: 0),
                lossRateBasisPoints: 0,
                score: score,
                quality: quality,
                isStrategicallyAvailable: true
            )
        )
    }

    // GIVEN 第 1 天两事件（80、60，其中 60 为 blunder）、第 2 天一事件（100）
    // WHEN 按日聚合
    // THEN 两日升序，逐日计数/总分/失误与均值精确
    @Test("多日事件按日聚合且均值精确")
    func aggregatesByDayWithExactMeans() {
        let day1a = calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 10))!
        let day1b = calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 15))!
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 9))!

        // Passed out of order to prove the result is sorted ascending by day.
        let events = [
            event(occurredAt: day2, score: 100, quality: .excellent),
            event(occurredAt: day1a, score: 80, quality: .acceptable),
            event(occurredAt: day1b, score: 60, quality: .blunder),
        ]

        let trend = ProgressTrend.daily(events: events, calendar: calendar)

        #expect(trend.count == 2)

        #expect(trend[0].dayStart == calendar.startOfDay(for: day1a))
        #expect(trend[0].sampleCount == 2)
        #expect(trend[0].scoreTotal == 140)
        #expect(trend[0].blunderCount == 1)
        #expect(trend[0].meanScore == 70)

        #expect(trend[1].dayStart == calendar.startOfDay(for: day2))
        #expect(trend[1].sampleCount == 1)
        #expect(trend[1].scoreTotal == 100)
        #expect(trend[1].blunderCount == 0)
        #expect(trend[1].meanScore == 100)
    }

    @Test("无事件给空结果")
    func emptyEventsGiveEmptyTrend() {
        #expect(ProgressTrend.daily(events: [], calendar: calendar).isEmpty)
    }

    @Test("空日均值为零而非崩溃")
    func emptyDayMeanIsZero() {
        #expect(DailyProgress(dayStart: Date(timeIntervalSince1970: 0), sampleCount: 0, scoreTotal: 0, blunderCount: 0).meanScore == 0)
    }
}
