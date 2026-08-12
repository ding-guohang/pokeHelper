import PokerCore

/// A plain-text, line-oriented rendering of a session.
///
/// Its only job is to be compared. A cross-process determinism test cannot pass
/// Swift values between processes, so the two runs have to agree on a byte
/// sequence, and every byte of that sequence has to be derived from the session
/// rather than from the process — no addresses, no hash values, no timestamps,
/// no set iteration.
///
/// Text rather than JSON so that a mismatch prints as a readable diff. The
/// point of this format is the moment it disagrees.
public enum SessionTranscript {
    /// Bumped whenever the format changes, so a stale comparison fails loudly
    /// rather than lining up two differently-shaped strings.
    public static let formatVersion = 1

    public static func render(_ run: SessionRun) -> String {
        var lines: [String] = []
        lines.append("transcript v\(formatVersion) seed=\(run.seed) hands=\(run.hands.count)")

        for hand in run.hands {
            lines.append(contentsOf: render(hand))
        }

        lines.append(
            "final " + run.finalStacks.map { String($0.centiBB) }.joined(separator: ",")
        )
        lines.append("total \(run.totalChips.centiBB)")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func render(_ hand: PlayedHand) -> [String] {
        var lines: [String] = []
        lines.append("hand \(hand.handIndex) button=\(hand.buttonSeat)")

        for seat in 0 ..< TableRules.seatCount {
            let cards = hand.holeCards[seat].map(\.code).joined(separator: " ")
            lines.append("  hole \(seat) \(cards)")
        }
        lines.append("  board \(hand.board.map(\.code).joined(separator: " "))")

        for action in hand.actions {
            lines.append(
                "  act \(action.seat) \(action.street.rawValue) "
                    + "\(describe(action.action)) pot=\(action.potAfter.centiBB)"
            )
        }

        lines.append("  street \(hand.result.streetReached.rawValue)")
        lines.append("  pot \(hand.result.potTotal.centiBB) rake \(hand.result.rake.centiBB)")
        for award in hand.result.pots {
            lines.append(
                "  award \(award.amount.centiBB) "
                    + "eligible=\(award.eligibleSeats.map(String.init).joined(separator: "/")) "
                    + "winners=\(award.winningSeats.map(String.init).joined(separator: "/"))"
            )
        }
        lines.append(
            "  delta " + hand.result.stackDeltasCentiBB.map(String.init).joined(separator: ",")
        )
        lines.append(
            "  stacks " + hand.endingStacks.map { String($0.centiBB) }.joined(separator: ",")
        )
        return lines
    }

    /// A stable spelling of an action, kind then amount.
    ///
    /// Written out rather than taken from `String(describing:)`: the compiler's
    /// reflection output for an enum with associated values is not a documented
    /// format, and a transcript that changes shape on a toolchain upgrade
    /// invalidates every committed fixture at once.
    public static func describe(_ action: DecisionAction) -> String {
        switch action {
        case .fold: "fold"
        case .check: "check"
        case let .call(to: amount): "call:\(amount.centiBB)"
        case let .bet(to: amount): "bet:\(amount.centiBB)"
        case let .raise(to: amount): "raise:\(amount.centiBB)"
        case let .allIn(to: amount): "allin:\(amount.centiBB)"
        }
    }

    /// Just the opponent action sequence, for the part of the determinism
    /// scenario that is about the opponents rather than the cards.
    ///
    /// Includes the seat and street, not only the action: two runs that folded
    /// the same number of times in a different order would otherwise compare
    /// equal.
    public static func opponentActions(_ run: SessionRun) -> [String] {
        run.hands.flatMap { hand in
            hand.actions
                .filter { $0.seat != TableRules.heroSeat }
                .map { "\(hand.handIndex):\($0.seat):\($0.street.rawValue):\(describe($0.action))" }
        }
    }
}
