public struct BBAmount: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int

    private enum CodingKeys: String, CodingKey {
        case centiBB
    }

    public init(rawValue: Int) {
        precondition(rawValue >= 0, "BBAmount cannot be negative")
        self.rawValue = rawValue
    }

    public init(centiBB: Int) {
        self.init(rawValue: centiBB)
    }

    public var centiBB: Int {
        rawValue
    }

    public static func < (lhs: BBAmount, rhs: BBAmount) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static func + (lhs: BBAmount, rhs: BBAmount) -> BBAmount {
        BBAmount(rawValue: lhs.rawValue + rhs.rawValue)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let centiBB = try container.decode(Int.self, forKey: .centiBB)

        guard centiBB >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .centiBB,
                in: container,
                debugDescription: "BBAmount cannot be negative"
            )
        }

        rawValue = centiBB
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(centiBB, forKey: .centiBB)
    }
}

public struct EVAmount: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int

    private enum CodingKeys: String, CodingKey {
        case milliBB
    }

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(milliBB: Int) {
        self.init(rawValue: milliBB)
    }

    public var milliBB: Int {
        rawValue
    }

    public static func < (lhs: EVAmount, rhs: EVAmount) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static func - (lhs: EVAmount, rhs: EVAmount) -> EVAmount {
        EVAmount(rawValue: lhs.rawValue - rhs.rawValue)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rawValue = try container.decode(Int.self, forKey: .milliBB)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(milliBB, forKey: .milliBB)
    }
}
