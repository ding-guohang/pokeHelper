/// Why an ICM computation could not produce an exact result.
///
/// The validation cases are distinct and equatable so a test can assert which
/// rule fired, and they are checked in a fixed precedence (see
/// `ICMCalculator.equities`) so a single-defect input maps to exactly one error.
/// `overflow` is separate: the input was legal but the exact answer does not fit
/// in `Int`, and the calculator reports that rather than returning an
/// approximation.
public enum ICMError: Error, Equatable, Sendable {
    case noPlayers
    case emptyPayouts
    case nonPositiveStack
    case negativePayout
    case morePayoutsThanPlayers
    /// More than 64 seats: the finishing-order recursion tracks placed players
    /// in an `Int` bit mask, which holds 64 bits. Real poker tables are far
    /// smaller; this guards a public API against a silently-wrong result.
    case tooManySeats
    /// A bubble-factor query where winning the all-in does not change the hero's
    /// ICM equity (e.g. a flat prize structure), so the ratio has a zero
    /// denominator and cannot be formed. Reported rather than dividing by zero.
    case noEquityGain
    /// A bubble-factor query naming the same seat as hero and opponent.
    case sameSeat
    /// A bubble-factor query naming a seat outside `0..<count`.
    case seatOutOfRange
    case overflow
}
