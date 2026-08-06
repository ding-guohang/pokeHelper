import XCTest
@testable import PokerCoach

@MainActor
final class TodayViewModelTests: XCTestCase {
    func testWeakestDimensionBecomesPrimaryTraining() async throws {
        let fixture = DashboardFixture.withBetSizingWeakness()

        await fixture.today.refresh()

        XCTAssertEqual(fixture.today.primaryItem?.abilityDimension, "bet-sizing")
        XCTAssertEqual(fixture.today.durationText, "约 8 分钟")
    }
}
