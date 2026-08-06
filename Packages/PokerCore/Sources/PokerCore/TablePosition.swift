public enum TablePositionError: Error, Equatable, Sendable {
    case invalidTableSize(Int)
    case invalidHeroSeatOffset(
        tableSize: Int,
        heroSeatOffsetFromButton: Int
    )
}

public struct TablePosition: Hashable, Sendable {
    public let tableSize: Int
    public let heroSeatOffsetFromButton: Int
    public let label: String

    public init(
        tableSize: Int,
        heroSeatOffsetFromButton: Int
    ) throws(TablePositionError) {
        guard let labels = Self.labelsByTableSize[tableSize] else {
            throw TablePositionError.invalidTableSize(tableSize)
        }
        guard labels.indices.contains(heroSeatOffsetFromButton) else {
            throw TablePositionError.invalidHeroSeatOffset(
                tableSize: tableSize,
                heroSeatOffsetFromButton: heroSeatOffsetFromButton
            )
        }

        self.tableSize = tableSize
        self.heroSeatOffsetFromButton = heroSeatOffsetFromButton
        label = labels[heroSeatOffsetFromButton]
    }

    private static let labelsByTableSize: [Int: [String]] = [
        2: ["BTN/SB", "BB"],
        3: ["BTN", "SB", "BB"],
        4: ["BTN", "SB", "BB", "CO"],
        5: ["BTN", "SB", "BB", "HJ", "CO"],
        6: ["BTN", "SB", "BB", "UTG", "HJ", "CO"],
        7: ["BTN", "SB", "BB", "UTG", "LJ", "HJ", "CO"],
        8: ["BTN", "SB", "BB", "UTG", "UTG+1", "LJ", "HJ", "CO"],
        9: [
            "BTN", "SB", "BB", "UTG", "UTG+1", "UTG+2", "LJ", "HJ",
            "CO"
        ],
    ]
}
