import Foundation
import Observation
import TrainingDomain

/// Drives the training progress trend: reads the user's own training events and
/// aggregates them per day via `ProgressTrend`. It reads no strategy content,
/// writes nothing, and produces no event — purely a view onto history already
/// recorded.
@MainActor
@Observable
final class ProgressTrendViewModel {
    private let eventStore: TrainingEventStore
    private let calendar: Calendar
    private let dayFormatter: DateFormatter

    private(set) var dayRows: [DayRow] = []
    private(set) var summaryText: String?
    private(set) var isLoaded = false
    private(set) var errorText: String?

    struct DayRow: Identifiable {
        let id: Date
        let text: String
    }

    init(eventStore: TrainingEventStore, calendar: Calendar = .current) {
        self.eventStore = eventStore
        self.calendar = calendar
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        self.dayFormatter = formatter
    }

    func load() async {
        do {
            let events = try await eventStore.allEvents()
            let trend = ProgressTrend.daily(events: events, calendar: calendar)

            dayRows = trend.map { day in
                DayRow(
                    id: day.dayStart,
                    text: "\(dayFormatter.string(from: day.dayStart))：\(day.sampleCount) 手 · 平均 \(day.meanScore) 分 · 失误 \(day.blunderCount)"
                )
            }

            let totalHands = trend.reduce(0) { $0 + $1.sampleCount }
            let totalScore = trend.reduce(0) { $0 + $1.scoreTotal }
            summaryText = totalHands > 0
                ? "共 \(totalHands) 手 · \(trend.count) 天 · 总平均 \(totalScore / totalHands) 分"
                : nil
            errorText = nil
        } catch {
            dayRows = []
            summaryText = nil
            errorText = "无法加载训练记录。"
        }
        isLoaded = true
    }
}
