/// An exact rational number, stored as a reduced `Int` numerator over a
/// strictly positive `Int` denominator.
///
/// ICM equity is a computed quotient — three equal stacks each own `1/3` of the
/// prize pool, a denominator that divides no power of ten. Any fixed-point scale
/// (cents, milli-cents) would be forced to round it, i.e. be silently wrong, so
/// unlike the domain-defined granularities elsewhere in the project (centi-BB,
/// basis points) ICM needs an exact rational. A `Fraction` is not a float: it is
/// exact truth, fully consistent with "floats are for display only."
///
/// Arithmetic is exact or it fails. Every operation is a throwing method that
/// reduces before multiplying and traps any `Int` overflow as
/// `ICMError.overflow` rather than falling back to a float or a truncated
/// integer — a large-but-legal input that cannot be represented exactly is
/// reported, never approximated.
public struct Fraction: Sendable, Hashable, Comparable {
    public let numerator: Int
    public let denominator: Int

    /// Normalizes on construction: reduces by the GCD and forces a positive
    /// denominator (`6/-3` becomes `-2/1`, `0/5` becomes `0/1`).
    ///
    /// A zero denominator is a programmer error, not a recoverable input, and
    /// ICM never produces one (stacks are positive, so every running total is
    /// positive); it traps.
    public init(numerator: Int, denominator: Int) {
        precondition(denominator != 0, "A fraction cannot have a zero denominator")

        var n = numerator
        var d = denominator
        if d < 0 {
            n = -n
            d = -d
        }
        if n == 0 {
            self.numerator = 0
            self.denominator = 1
            return
        }
        let g = Fraction.greatestCommonDivisor(n, d)
        self.numerator = n / g
        self.denominator = d / g
    }

    /// A whole number as `whole/1`.
    public init(_ whole: Int) {
        self.numerator = whole
        self.denominator = 1
    }

    /// `self + other`, exact or `ICMError.overflow`.
    ///
    /// Combines over the least common multiple of the denominators rather than
    /// their raw product, so the intermediate stays as small as the exact
    /// answer allows before the reduction in `init` runs again.
    public func adding(_ other: Fraction) throws -> Fraction {
        let g = Fraction.greatestCommonDivisor(denominator, other.denominator)
        let (lcm, overflowLCM) = (denominator / g).multipliedReportingOverflow(by: other.denominator)
        if overflowLCM { throw ICMError.overflow }

        let (leftScaled, overflowLeft) = numerator.multipliedReportingOverflow(by: other.denominator / g)
        if overflowLeft { throw ICMError.overflow }
        let (rightScaled, overflowRight) = other.numerator.multipliedReportingOverflow(by: denominator / g)
        if overflowRight { throw ICMError.overflow }

        let (sum, overflowSum) = leftScaled.addingReportingOverflow(rightScaled)
        if overflowSum { throw ICMError.overflow }
        return Fraction(numerator: sum, denominator: lcm)
    }

    /// `self * other`, exact or `ICMError.overflow`.
    ///
    /// Cross-reduces the two numerator/denominator pairs before multiplying, so
    /// products that cancel to something small never build a large intermediate.
    public func multiplied(by other: Fraction) throws -> Fraction {
        let leftGCD = Fraction.greatestCommonDivisor(numerator, other.denominator)
        let rightGCD = Fraction.greatestCommonDivisor(other.numerator, denominator)

        let (num, overflowNum) = (numerator / leftGCD).multipliedReportingOverflow(by: other.numerator / rightGCD)
        if overflowNum { throw ICMError.overflow }
        let (den, overflowDen) = (denominator / rightGCD).multipliedReportingOverflow(by: other.denominator / leftGCD)
        if overflowDen { throw ICMError.overflow }
        return Fraction(numerator: num, denominator: den)
    }

    /// `self * k`, exact or `ICMError.overflow`. Used to weight a finish
    /// probability by an integer payout.
    public func multiplied(byInteger k: Int) throws -> Fraction {
        let g = Fraction.greatestCommonDivisor(k, denominator)
        let (num, overflow) = numerator.multipliedReportingOverflow(by: k / g)
        if overflow { throw ICMError.overflow }
        return Fraction(numerator: num, denominator: denominator / g)
    }

    public static func < (lhs: Fraction, rhs: Fraction) -> Bool {
        // Both denominators are positive, so the inequality direction survives
        // cross-multiplication. Comparison is not on the ICM computation path
        // (only sorting/inspection in tests), so an overflow here is a caller
        // bug and traps rather than throwing.
        let (left, overflowLeft) = lhs.numerator.multipliedReportingOverflow(by: rhs.denominator)
        let (right, overflowRight) = rhs.numerator.multipliedReportingOverflow(by: lhs.denominator)
        precondition(!overflowLeft && !overflowRight, "Fraction comparison overflowed")
        return left < right
    }

    /// Euclid on magnitudes. Callers pass non-negative ICM quantities, so the
    /// `Int.min` magnitude overflow is unreachable and is not guarded here.
    static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        var x = a < 0 ? -a : a
        var y = b < 0 ? -b : b
        while y != 0 {
            (x, y) = (y, x % y)
        }
        return x
    }
}
