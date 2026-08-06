import Testing
@testable import PokerCore

@Test func tablePositionMapsEverySeatForTwoThroughNinePlayers() throws {
    let expectedLabels: [(tableSize: Int, labels: [String])] = [
        (2, ["BTN/SB", "BB"]),
        (3, ["BTN", "SB", "BB"]),
        (4, ["BTN", "SB", "BB", "CO"]),
        (5, ["BTN", "SB", "BB", "HJ", "CO"]),
        (6, ["BTN", "SB", "BB", "UTG", "HJ", "CO"]),
        (7, ["BTN", "SB", "BB", "UTG", "LJ", "HJ", "CO"]),
        (8, ["BTN", "SB", "BB", "UTG", "UTG+1", "LJ", "HJ", "CO"]),
        (
            9,
            [
                "BTN", "SB", "BB", "UTG", "UTG+1", "UTG+2", "LJ", "HJ",
                "CO"
            ]
        ),
    ]

    for expectation in expectedLabels {
        for (offset, expectedLabel) in expectation.labels.enumerated() {
            let position = try TablePosition(
                tableSize: expectation.tableSize,
                heroSeatOffsetFromButton: offset
            )

            #expect(
                position.label == expectedLabel,
                "tableSize \(expectation.tableSize), offset \(offset)"
            )
        }
    }
}

@Test(arguments: [1, 10])
func tablePositionRejectsTableSizeOutsideTwoThroughNine(
    tableSize: Int
) {
    #expect(throws: TablePositionError.invalidTableSize(tableSize)) {
        try TablePosition(
            tableSize: tableSize,
            heroSeatOffsetFromButton: 0
        )
    }
}

@Test(arguments: [-1, 6])
func tablePositionRejectsOffsetOutsideTable(
    heroSeatOffsetFromButton: Int
) {
    #expect(
        throws: TablePositionError.invalidHeroSeatOffset(
            tableSize: 6,
            heroSeatOffsetFromButton: heroSeatOffsetFromButton
        )
    ) {
        try TablePosition(
            tableSize: 6,
            heroSeatOffsetFromButton: heroSeatOffsetFromButton
        )
    }
}
