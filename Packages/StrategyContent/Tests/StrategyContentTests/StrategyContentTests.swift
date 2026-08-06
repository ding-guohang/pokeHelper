import XCTest
@testable import StrategyContent

final class StrategyContentTests: XCTestCase {
    func testStrategyContentProductIsImportable() {
        XCTAssertNotNil(StrategyContent.self)
    }
}
