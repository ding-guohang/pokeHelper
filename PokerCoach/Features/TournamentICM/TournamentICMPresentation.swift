import TournamentEngine

/// Display-only conversions for the tournament ICM calculator.
///
/// The engine keeps ICM equities and bubble factors as exact `Fraction`s; this
/// is the single place they become decimal text, by integer long division only
/// — no `Double`, no `NumberFormatter` — matching the project's "floats are for
/// display, and only become text once" discipline (see `StrategyNumberText`).
enum TournamentICMPresentation {
    /// The fraction rounded half-up to `places` decimal places, as a fixed-point
    /// string. Uses magnitude arithmetic so the sign and `Int.min` are handled
    /// without overflow.
    static func decimalString(_ fraction: Fraction, places: Int) -> String {
        precondition(places >= 0, "Decimal places cannot be negative")

        let negative = fraction.numerator < 0
        let denominator = fraction.denominator.magnitude
        var whole = fraction.numerator.magnitude / denominator
        var remainder = fraction.numerator.magnitude % denominator

        var digits: [UInt] = []
        for _ in 0..<places {
            remainder *= 10
            digits.append(remainder / denominator)
            remainder %= denominator
        }

        // Round half-up on the next digit, propagating any carry up through the
        // decimals and into the whole part.
        remainder *= 10
        if remainder / denominator >= 5 {
            var index = digits.count - 1
            var carry = true
            while index >= 0, carry {
                if digits[index] == 9 {
                    digits[index] = 0
                } else {
                    digits[index] += 1
                    carry = false
                }
                index -= 1
            }
            if carry { whole += 1 }
        }

        var result = negative ? "-" : ""
        result += String(whole)
        if places > 0 {
            result += "."
            result += digits.map(String.init).joined()
        }
        return result
    }

    /// A readable Chinese message for each engine error the calculator can hit.
    static func message(for error: ICMError) -> String {
        switch error {
        case .noPlayers: "请至少输入一位玩家的筹码。"
        case .emptyPayouts: "请至少输入一个名次的派彩。"
        case .nonPositiveStack: "每位玩家的筹码必须为正整数。"
        case .negativePayout: "派彩不能为负数。"
        case .morePayoutsThanPlayers: "派彩名次数不能多于玩家数。"
        case .tooManySeats: "玩家数不能超过 64。"
        case .noEquityGain: "该派彩结构下赢得此次全下不改变权益，无法计算泡沫系数。"
        case .sameSeat: "英雄与对手必须是不同座位。"
        case .seatOutOfRange: "座位编号超出范围。"
        case .overflow: "数值超出精确计算范围。"
        }
    }
}
