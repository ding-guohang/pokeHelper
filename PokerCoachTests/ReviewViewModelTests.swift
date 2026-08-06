import XCTest
@testable import PokerCoach

@MainActor
final class ReviewViewModelTests: XCTestCase {
    func testReviewSortsWeakestAbilityFirst() async throws {
        let fixture = DashboardFixture.withTwoDimensions()

        await fixture.review.refresh()

        XCTAssertEqual(
            fixture.review.abilities.map(\.dimension),
            ["bet-sizing", "preflop-range"]
        )
    }
}
