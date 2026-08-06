public enum DecisionAction: Hashable, Codable, Sendable {
    case fold
    case check
    case call(to: BBAmount)
    case bet(to: BBAmount)
    case raise(to: BBAmount)
    case allIn(to: BBAmount)

    private enum CodingKeys: String, CodingKey {
        case kind
        case toCentiBB
    }

    private enum Kind: String, Codable {
        case fold
        case check
        case call
        case bet
        case raise
        case allIn
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .fold:
            try Self.rejectUnexpectedAmount(in: container)
            self = .fold
        case .check:
            try Self.rejectUnexpectedAmount(in: container)
            self = .check
        case .call:
            self = .call(to: try Self.decodeAmount(from: container))
        case .bet:
            self = .bet(to: try Self.decodeAmount(from: container))
        case .raise:
            self = .raise(to: try Self.decodeAmount(from: container))
        case .allIn:
            self = .allIn(to: try Self.decodeAmount(from: container))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .fold:
            try container.encode(Kind.fold, forKey: .kind)
        case .check:
            try container.encode(Kind.check, forKey: .kind)
        case let .call(to: amount):
            try container.encode(Kind.call, forKey: .kind)
            try container.encode(amount.centiBB, forKey: .toCentiBB)
        case let .bet(to: amount):
            try container.encode(Kind.bet, forKey: .kind)
            try container.encode(amount.centiBB, forKey: .toCentiBB)
        case let .raise(to: amount):
            try container.encode(Kind.raise, forKey: .kind)
            try container.encode(amount.centiBB, forKey: .toCentiBB)
        case let .allIn(to: amount):
            try container.encode(Kind.allIn, forKey: .kind)
            try container.encode(amount.centiBB, forKey: .toCentiBB)
        }
    }

    private static func decodeAmount(from container: KeyedDecodingContainer<CodingKeys>) throws -> BBAmount {
        let centiBB = try container.decode(Int.self, forKey: .toCentiBB)

        guard centiBB >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .toCentiBB,
                in: container,
                debugDescription: "Decision action amount cannot be negative"
            )
        }

        return BBAmount(centiBB: centiBB)
    }

    private static func rejectUnexpectedAmount(in container: KeyedDecodingContainer<CodingKeys>) throws {
        guard !container.contains(.toCentiBB) else {
            throw DecodingError.dataCorruptedError(
                forKey: .toCentiBB,
                in: container,
                debugDescription: "Fold and check actions cannot include an amount"
            )
        }
    }
}
