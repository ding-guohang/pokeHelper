public struct BBAmount: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int

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
}

public struct EVAmount: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int

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
}
