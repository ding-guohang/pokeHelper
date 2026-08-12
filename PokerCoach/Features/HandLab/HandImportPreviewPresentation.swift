import HandHistory
import PokerCore

/// A display-ready view of an `ObservedHand`, computed by pure mapping.
///
/// Nothing here is business calculation: positions come from `TablePosition`,
/// amounts are the model's centi-BB integers rendered as big blinds, cards are
/// their two-character codes. A preview value must equal the model value it
/// stands for, so this type never rounds, re-derives or invents — the only way
/// to guarantee the screen shows what was parsed is for the screen to have no
/// arithmetic of its own beyond formatting.
struct HandImportPreview: Equatable {
    struct SeatRow: Equatable, Identifiable {
        let seat: Int
        let position: String
        let startingStack: String
        let holeCards: String
        let isHero: Bool

        var id: Int { seat }
    }

    struct StreetRow: Equatable, Identifiable {
        let street: Street
        let name: String
        let board: String
        let actions: [String]

        var id: String { street.rawValue }
    }

    let seats: [SeatRow]
    let streets: [StreetRow]
    let heroPosition: String
    let rake: String

    init(_ hand: ObservedHand) {
        seats = hand.seats.map { seat in
            SeatRow(
                seat: seat.seat,
                position: HandImportPreview.position(
                    tableSize: hand.tableSize,
                    offset: seat.seatOffsetFromButton
                ),
                startingStack: HandImportPreview.bb(seat.startingStackCentiBB),
                holeCards: HandImportPreview.holeCards(seat.holeCards),
                isHero: HandImportPreview.isKnown(seat.holeCards)
            )
        }

        streets = hand.streets.map { street in
            StreetRow(
                street: street.street,
                name: HandImportPreview.streetName(street.street),
                board: HandImportPreview.board(street.board),
                actions: street.actions.map { action in
                    HandImportPreview.action(
                        action,
                        tableSize: hand.tableSize,
                        seats: hand.seats
                    )
                }
            )
        }

        heroPosition = seats.first(where: \.isHero)?.position ?? ""
        rake = HandImportPreview.bb(hand.result.rakeCentiBB)
    }

    // MARK: - Formatting

    /// Position label from the button offset. The table size and offset always
    /// come from a parsed hand (2...9, valid offset), so the label is defined;
    /// an unexpected pair renders as "?" rather than crashing a preview.
    static func position(tableSize: Int, offset: Int) -> String {
        (try? TablePosition(tableSize: tableSize, heroSeatOffsetFromButton: offset))?.label ?? "?"
    }

    /// A centi-BB integer as big blinds: 10000 -> "100 BB", 50 -> "0.5 BB",
    /// 300 -> "3 BB". Trailing zeros in the fraction are trimmed so a whole
    /// number of blinds reads as one.
    static func bb(_ centiBB: Int) -> String {
        let whole = centiBB / 100
        let fraction = centiBB % 100
        if fraction == 0 {
            return "\(whole) BB"
        }
        let twoPlaces = String(format: "%02d", fraction)
        let trimmed = twoPlaces.hasSuffix("0") ? String(twoPlaces.dropLast()) : twoPlaces
        return "\(whole).\(trimmed) BB"
    }

    static func board(_ cards: [Card]) -> String {
        cards.map(\.code).joined(separator: " ")
    }

    static func holeCards(_ holeCards: HoleCards) -> String {
        switch holeCards {
        case let .known(first, second):
            "\(first.code) \(second.code)"
        case .unknown:
            "未知"
        }
    }

    static func isKnown(_ holeCards: HoleCards) -> Bool {
        if case .known = holeCards { return true }
        return false
    }

    static func streetName(_ street: Street) -> String {
        switch street {
        case .preflop: "翻前"
        case .flop: "翻牌"
        case .turn: "转牌"
        case .river: "河牌"
        }
    }

    /// One voluntary action as "<position> <verb> [<amount>]", the position taken
    /// from the acting seat's offset so the line reads without a seat-number
    /// lookup.
    static func action(_ action: ObservedAction, tableSize: Int, seats: [ObservedSeat]) -> String {
        let position: String
        if let offset = seats.first(where: { $0.seat == action.seat })?.seatOffsetFromButton {
            position = self.position(tableSize: tableSize, offset: offset)
        } else {
            position = "座位 \(action.seat)"
        }

        let verb: String
        switch action.kind {
        case .fold: verb = "弃牌"
        case .check: verb = "过牌"
        case .call: verb = "跟注"
        case .bet: verb = "下注"
        case .raiseTo: verb = "加注至"
        }

        if let amount = action.amountCentiBB {
            return "\(position) \(verb) \(bb(amount))"
        }
        return "\(position) \(verb)"
    }
}
