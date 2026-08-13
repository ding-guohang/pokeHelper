import XCTest
import TournamentEngine
@testable import PokerCoach

final class TournamentICMPresentationTests: XCTestCase {
    func testDecimalStringRoundsExactRationalsWithoutFloatingPoint() {
        // 10000/3 = 3333.333… → 3333.33 (third digit is 3, no round up).
        XCTAssertEqual(
            TournamentICMPresentation.decimalString(Fraction(numerator: 10000, denominator: 3), places: 2),
            "3333.33"
        )
        // 2/3 = 0.666… → 0.67 (round half-up carries the last digit).
        XCTAssertEqual(
            TournamentICMPresentation.decimalString(Fraction(numerator: 2, denominator: 3), places: 2),
            "0.67"
        )
        // Whole numbers keep trailing zeros to the requested places.
        XCTAssertEqual(
            TournamentICMPresentation.decimalString(Fraction(1), places: 2),
            "1.00"
        )
        // Sign is preserved.
        XCTAssertEqual(
            TournamentICMPresentation.decimalString(Fraction(numerator: -4, denominator: 3), places: 2),
            "-1.33"
        )
    }

    func testRoundingCarriesIntoTheWholePart() {
        // 199/100 = 1.99 exact; 1999/1000 = 1.999 → 2.00 (carry propagates up).
        XCTAssertEqual(
            TournamentICMPresentation.decimalString(Fraction(numerator: 1999, denominator: 1000), places: 2),
            "2.00"
        )
    }

    func testErrorMessagesAreDistinctPerCase() {
        let errors: [ICMError] = [
            .noPlayers, .emptyPayouts, .nonPositiveStack, .negativePayout,
            .morePayoutsThanPlayers, .tooManySeats, .noEquityGain, .sameSeat,
            .seatOutOfRange, .overflow,
        ]
        let messages = errors.map { TournamentICMPresentation.message(for: $0) }
        XCTAssertEqual(Set(messages).count, errors.count, "each ICMError should map to a distinct message")
    }
}
