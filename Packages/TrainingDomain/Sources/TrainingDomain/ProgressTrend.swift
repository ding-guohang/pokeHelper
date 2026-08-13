import Foundation

/// One calendar day of training activity, aggregated from the user's own graded
/// decisions. Pure counts and totals — the mean is integer division at read
/// time, matching `PlayerModelReducer`'s rounding — so nothing here is a float
/// truth, and none of it is strategy content.
public struct DailyProgress: Hashable, Sendable {
    public let dayStart: Date
    public let sampleCount: Int
    public let scoreTotal: Int
    public let blunderCount: Int

    public init(dayStart: Date, sampleCount: Int, scoreTotal: Int, blunderCount: Int) {
        self.dayStart = dayStart
        self.sampleCount = sampleCount
        self.scoreTotal = scoreTotal
        self.blunderCount = blunderCount
    }

    /// Mean 0–100 score for the day, by integer division (0 for an empty day).
    public var meanScore: Int {
        sampleCount == 0 ? 0 : scoreTotal / sampleCount
    }
}

/// Aggregates training events into a per-day progress trend.
///
/// This only sums and counts the user's already-graded decisions; it reads no
/// strategy content and produces no new event. The calendar is passed in rather
/// than read from a global, so day boundaries are the caller's local timezone
/// concern and the function stays pure and testable.
public enum ProgressTrend {
    public static func daily(events: [TrainingEvent], calendar: Calendar) -> [DailyProgress] {
        var byDay: [Date: (sampleCount: Int, scoreTotal: Int, blunderCount: Int)] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.occurredAt)
            var bucket = byDay[day] ?? (0, 0, 0)
            bucket.sampleCount += 1
            bucket.scoreTotal += event.grade.score
            if event.grade.quality == .blunder { bucket.blunderCount += 1 }
            byDay[day] = bucket
        }
        return byDay
            .map { DailyProgress(dayStart: $0.key, sampleCount: $0.value.sampleCount, scoreTotal: $0.value.scoreTotal, blunderCount: $0.value.blunderCount) }
            .sorted { $0.dayStart < $1.dayStart }
    }
}
