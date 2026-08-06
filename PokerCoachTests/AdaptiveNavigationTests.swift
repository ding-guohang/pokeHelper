import XCTest
@testable import PokerCoach

final class AdaptiveNavigationTests: XCTestCase {
    func testAllPrimaryDestinationsHaveChineseLabels() {
        XCTAssertEqual(AppDestination.allCases.map(\.title), ["今日", "学习", "训练", "复盘"])
        XCTAssertEqual(AppDestination.train.systemImage, "suit.spade.fill")
    }
}
