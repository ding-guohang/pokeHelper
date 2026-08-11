import PokerCore

/// How this app writes the two number kinds strategy content is made of.
///
/// Extracted so the key-hand comparison and the training feedback screen cannot
/// print the same basis-point value two different ways. Both are integers in
/// the domain — basis points and milli-BB — and both become text exactly once,
/// here.
enum StrategyNumberText {
    /// A frequency in basis points as a percentage to one decimal place.
    ///
    /// Rounded to nearest rather than truncated: 4633 is 46.3%, not 46.3% by
    /// accident of the division.
    static func frequency(basisPoints: Int) -> String {
        let tenthsOfPercent = (basisPoints + 5) / 10
        return "\(tenthsOfPercent / 10).\(tenthsOfPercent % 10)%"
    }

    /// An EV in milli-BB, to three decimal places, with a typographic minus.
    static func ev(_ amount: EVAmount) -> String {
        let sign = amount.milliBB < 0 ? "−" : ""
        let magnitude = amount.milliBB.magnitude
        return "\(sign)\(magnitude / 1_000).\(String(format: "%03llu", magnitude % 1_000)) BB"
    }
}
