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
    case overflow
}
