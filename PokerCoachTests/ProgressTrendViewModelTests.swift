import XCTest
import PokerCore
import TrainingDomain
@testable import PokerCoach

@MainActor
final class ProgressTrendViewModelTests: XCTestCase {
    /// A UTC calendar so day boundaries match the injected event timestamps
    /// deterministically.
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testAggregatesInjectedEventsIntoDayRowsAndSummary() async {
        let calendar = utcCalendar
        let day1a = calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 10))!
        let day1b = calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 15))!
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 9))!
        let store = StubEventStore(events: [
            makeEvent(occurredAt: day1a, score: 80, quality: .acceptable),
            makeEvent(occurredAt: day1b, score: 60, quality: .blunder),
            makeEvent(occurredAt: day2, score: 100, quality: .excellent),
        ])

        let viewModel = ProgressTrendViewModel(eventStore: store, calendar: calendar)
        await viewModel.load()

        XCTAssertEqual(viewModel.dayRows.count, 2)
        XCTAssertEqual(viewModel.dayRows[0].text, "2026-08-11：2 手 · 平均 70 分 · 失误 1")
        XCTAssertEqual(viewModel.dayRows[1].text, "2026-08-12：1 手 · 平均 100 分 · 失误 0")
        XCTAssertEqual(viewModel.summaryText, "共 3 手 · 2 天 · 总平均 80 分")
        XCTAssertNil(viewModel.errorText)
    }

    func testEmptyStoreShowsNoRowsAndNoSummary() async {
        let viewModel = ProgressTrendViewModel(eventStore: StubEventStore(events: []), calendar: utcCalendar)
        await viewModel.load()

        XCTAssertTrue(viewModel.dayRows.isEmpty)
        XCTAssertNil(viewModel.summaryText)
        XCTAssertTrue(viewModel.isLoaded)
    }

    private func makeEvent(occurredAt: Date, score: Int, quality: DecisionQuality) -> TrainingEvent {
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
}

/// An in-memory store that just returns fixed events.
private final class StubEventStore: TrainingEventStore, @unchecked Sendable {
    private let events: [TrainingEvent]
    init(events: [TrainingEvent]) { self.events = events }
    func append(_ event: TrainingEvent) async throws {}
    func allEvents() async throws -> [TrainingEvent] { events }
    func events(after checkpoint: UUID?) async throws -> [TrainingEvent] { events }
}
