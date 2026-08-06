public enum Suit: String, CaseIterable, Codable, Sendable {
    case clubs = "c"
    case diamonds = "d"
    case hearts = "h"
    case spades = "s"
}

public enum Rank: String, CaseIterable, Codable, Sendable {
    case two = "2"
    case three = "3"
    case four = "4"
    case five = "5"
    case six = "6"
    case seven = "7"
    case eight = "8"
    case nine = "9"
    case ten = "T"
    case jack = "J"
    case queen = "Q"
    case king = "K"
    case ace = "A"
}

public struct Card: Hashable, Codable, Sendable {
    public let rank: Rank
    public let suit: Suit

    public init(rank: Rank, suit: Suit) {
        self.rank = rank
        self.suit = suit
    }

    public init?(code: String) {
        guard code.count == 2 else {
            return nil
        }

        let codeCharacters = Array(code)
        guard
            let rank = Rank(rawValue: String(codeCharacters[0])),
            let suit = Suit(rawValue: String(codeCharacters[1]))
        else {
            return nil
        }

        self.init(rank: rank, suit: suit)
    }

    public var code: String {
        rank.rawValue + suit.rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let code = try container.decode(String.self)

        guard let card = Card(code: code) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Card code must be a valid two-character rank and suit"
            )
        }

        self = card
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(code)
    }
}
