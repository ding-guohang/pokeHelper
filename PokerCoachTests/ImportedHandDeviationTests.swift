import XCTest
@testable import PokerCoach

/// The deviation magnitude is a strict decreasing function of the range weight.
///
/// Its only job is to order key nodes so the biggest departure is reviewed
/// first, which needs exactly this: a smaller weight — a line the range takes
/// less often — must always produce a larger magnitude. The endpoints anchor
/// the scale: a line never taken is a full-10,000 deviation, a line always
/// taken is none.
final class ImportedHandDeviationTests: XCTestCase {
    func testMagnitudeStrictlyDecreasesWithWeight() {
        let weights = [0, 1, 2_500, 4_999, 5_000, 7_500, 9_999, 10_000]
        for (lower, higher) in zip(weights, weights.dropFirst()) {
            XCTAssertGreaterThan(
                deviationMagnitude(weightBasisPoints: lower),
                deviationMagnitude(weightBasisPoints: higher),
                "权重 \(lower) 的偏离幅度应严格大于权重 \(higher) 的"
            )
        }
    }

    func testEndpoints() {
        XCTAssertEqual(deviationMagnitude(weightBasisPoints: 0), 10_000)
        XCTAssertEqual(deviationMagnitude(weightBasisPoints: 10_000), 0)
    }
}
